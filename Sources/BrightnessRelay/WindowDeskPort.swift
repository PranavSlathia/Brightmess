import AppKit
import ApplicationServices
import BrightnessCore

struct DeskWindow: Identifiable {
    let id = UUID()
    let app: String, title: String, owner: pid_t, element: AXUIElement
    var original: CGDirectDisplayID
    var nativeWindowID:UInt32?
    var shelfTicket: UUID?
    var retrievalState: WindowRetrievalState = .normal
    var displayTitle: String { title.isEmpty ? "Untitled window" : title }
}

enum WindowRetrievalState: Equatable {
    case normal, fullScreen, blocked(String)
}

struct ShelfScreen {
    let id: CGDirectDisplayID, name: String, frame: CGRect, usable: CGRect
}

@MainActor protocol WindowRetrievalPort: WindowDeskPort {
    func retrievalInventory(excluding destination:UInt32,screens:[ShelfScreen]) async -> [DeskWindow]
    func retrieve(_ window:DeskWindow,to destination:UInt32,progress:@escaping @MainActor (String)->Void) async throws
}

@MainActor protocol WindowDeskPort {
    var trusted: Bool { get }
    var screens: [ShelfScreen] { get }
    func current(previous: NSRunningApplication?) -> DeskWindow?
    func inventory(excluding destination: CGDirectDisplayID, screens: [ShelfScreen]) async -> [DeskWindow]
    func move(_ window: DeskWindow, to destination: CGDirectDisplayID) throws
    func icon(for window: DeskWindow) -> NSImage?
}

enum AXDesk {
    static func value(_ el: AXUIElement,_ key: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el,key as CFString,&v) == .success ? v : nil
    }
    static func settable(_ el: AXUIElement,_ attr: String) -> Bool {
        var v=DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(el,attr as CFString,&v) == .success && v.boolValue
    }
    static func accessibilityFrame(_ el: AXUIElement) -> CGRect? {
        guard let p=value(el,kAXPositionAttribute), let s=value(el,kAXSizeAttribute),
              CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else{return nil}
        var point=CGPoint.zero,size=CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size),
              point.x.isFinite,point.y.isFinite,size.width.isFinite,size.height.isFinite,
              size.width>0,size.height>0 else{return nil}
        return CGRect(origin:point,size:size)
    }
    static func frame(_ el:AXUIElement,records:[WindowGeometry.Record]?=nil)->CGRect? {
        var owner:pid_t=0
        guard AXUIElementGetPid(el,&owner) == .success else{return nil}
        let id=WindowServerGeometry.id(el)
        return WindowGeometry.resolve(accessibility:accessibilityFrame(el),windowID:id,owner:owner,
            records:records ?? id.flatMap{WindowServerGeometry.records(only:$0)})
    }
    static func matches(_ window:DeskWindow)->Bool {
        window.nativeWindowID.map{WindowServerGeometry.id(window.element)==$0} ?? true
    }
    static func screen(_ rect:CGRect,in screens:[ShelfScreen])->ShelfScreen? {
        screens.compactMap { screen -> (ShelfScreen,CGFloat)? in
            let r=screen.frame.intersection(rect)
            return r.isEmpty || r.isNull ? nil : (screen,r.width*r.height)
        }.max{$0.1<$1.1}?.0
    }
    static func entry(_ el:AXUIElement,pid:pid_t,name:String,screens:[ShelfScreen],
                      excluding destination:UInt32?=nil,readTitle:Bool=true,retrieval:Bool=false,
                      records:[WindowGeometry.Record]?=nil,geometryUnavailable:(()->Void)?=nil)->DeskWindow? {
        AXUIElementSetMessagingTimeout(el,0.25)
        guard value(el,kAXRoleAttribute) as? String == kAXWindowRole,
              value(el,kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              value(el,kAXMinimizedAttribute) as? Bool != true else{return nil}
        guard let rect=frame(el,records:records) else{geometryUnavailable?();return nil}
        guard let s=screen(rect,in:screens),s.id != destination else{return nil}
        let full=value(el,"AXFullScreen") as? Bool == true
        let movable=settable(el,kAXPositionAttribute)
        guard retrieval || (!full && movable) else{return nil}
        var window=DeskWindow(app:name,title:readTitle ? (value(el,kAXTitleAttribute) as? String ?? ""):"",owner:pid,element:el,original:s.id)
        window.nativeWindowID=WindowServerGeometry.id(el)
        if full {
            window.retrievalState=settable(el,"AXFullScreen") && WindowRetrieval.coversDisplay(rect,s.frame)
                ? .fullScreen : .blocked("Exit full screen or Split View first")
        } else if !movable {window.retrievalState = .blocked("This app does not allow moving this window")}
        return window
    }
}

/// AppKit metadata stays on the main actor. Potentially slow, read-only AX
/// enumeration runs off it, once per open/refresh, never on an idle timer.
@MainActor final class MacWindowDesk: WindowRetrievalPort {
    private var retrieving=false
    var trusted:Bool { AXIsProcessTrusted() }
    var screens:[ShelfScreen] {
        let top=CGDisplayBounds(CGMainDisplayID()).height
        return NSScreen.screens.compactMap { s in
            guard let n=s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else{return nil}
            let id=n.uint32Value,r=s.visibleFrame
            return ShelfScreen(id:id,name:s.localizedName=="LU28R55" ? "Samsung":s.localizedName,frame:CGDisplayBounds(id),
                               usable:CGRect(x:r.minX,y:top-r.maxY,width:r.width,height:r.height))
        }
    }
    func icon(for window:DeskWindow)->NSImage? { NSRunningApplication(processIdentifier:window.owner)?.icon }
    func current(previous:NSRunningApplication?)->DeskWindow? {
        let front=NSWorkspace.shared.frontmostApplication,app=front?.processIdentifier==getpid() ? previous : front
        guard trusted,let app,!app.isTerminated,app.processIdentifier != getpid() else{return nil}
        let ax=AXUIElementCreateApplication(app.processIdentifier);AXUIElementSetMessagingTimeout(ax,0.25)
        guard let w=AXDesk.value(ax,kAXFocusedWindowAttribute),CFGetTypeID(w)==AXUIElementGetTypeID() else{return nil}
        return AXDesk.entry(w as! AXUIElement,pid:app.processIdentifier,name:app.localizedName ?? "Application",screens:screens,readTitle:false)
    }
    func inventory(excluding destination:UInt32,screens:[ShelfScreen]) async -> [DeskWindow] {
        await inventory(excluding:destination,screens:screens,retrieval:false)
    }
    func retrievalInventory(excluding destination:UInt32,screens:[ShelfScreen]) async -> [DeskWindow] {
        await inventory(excluding:destination,screens:screens,retrieval:true)
    }
    #if DEBUG
    func fixtureInventory(owner:pid_t,excluding destination:UInt32,screens:[ShelfScreen]) async->[DeskWindow] {
        guard NSRunningApplication(processIdentifier:owner)?.bundleIdentifier=="dev.pranav.Brightmess.WindowMoveFixture" else{return []}
        return await inventory(excluding:destination,screens:screens,retrieval:true,onlyOwner:owner)
    }
    #endif
    private func inventory(excluding destination:UInt32,screens:[ShelfScreen],retrieval:Bool,onlyOwner:pid_t?=nil) async -> [DeskWindow] {
        let apps=NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated}
            .filter{onlyOwner == nil || $0.processIdentifier==onlyOwner}
            .map{($0.processIdentifier,$0.localizedName ?? "Application")}
        let job=Task.detached(priority:.userInitiated) { () -> [DeskWindow] in
            let deadline=ProcessInfo.processInfo.systemUptime+1.5
            for attempt in 0..<16 {
                var out=[DeskWindow](),pendingGeometry=false
                let geometry=WindowServerGeometry.records()
                for (pid,name) in apps {
                    guard !Task.isCancelled else{return []}
                    let ax=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(ax,0.25)
                    for el in AXDesk.value(ax,kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                        guard !Task.isCancelled else{return []}
                        if let w=AXDesk.entry(el,pid:pid,name:name,screens:screens,excluding:destination,retrieval:retrieval,
                            records:geometry,geometryUnavailable:{pendingGeometry=true}) {out.append(w)}
                    }
                }
                // Opening again immediately after a move may overlap the
                // destination Space animation. Refresh only this in-flight
                // scan; never publish its temporary absence as the final list.
                if !pendingGeometry || attempt==15 || ProcessInfo.processInfo.systemUptime>=deadline {
                    return out.sorted{($0.app,$0.title)<($1.app,$1.title)}
                }
                do {try await Task.sleep(nanoseconds:100_000_000)}catch{return []}
            }
            return []
        }
        return await withTaskCancellationHandler(operation:{await job.value},onCancel:{job.cancel()})
    }
    func move(_ w:DeskWindow,to id:UInt32)throws {
        try WindowPlacement.move(original:w.original,destination:id,trusted:trusted,
            usable:{ id in self.screens.first{$0.id==id}?.usable },read:{
                var pid:pid_t=0
                guard AXUIElementGetPid(w.element,&pid) == .success,pid==w.owner,AXDesk.matches(w),
                      AXDesk.value(w.element,kAXMinimizedAttribute) as? Bool != true,
                      let rect=AXDesk.frame(w.element),let s=AXDesk.screen(rect,in:self.screens) else{return nil}
                return .init(screen:s.id,rect:rect,usable:s.usable,fullScreen:AXDesk.value(w.element,"AXFullScreen") as? Bool == true,
                             movable:AXDesk.settable(w.element,kAXPositionAttribute))
            },write:{ target in
                var origin=target.origin,size=target.size
                let resize=AXDesk.settable(w.element,kAXSizeAttribute) && AXDesk.frame(w.element)?.size != size
                func fit(){if resize,let v=AXValueCreate(.cgSize,&size){_ = AXUIElementSetAttributeValue(w.element,kAXSizeAttribute as CFString,v)}}
                fit()
                guard let v=AXValueCreate(.cgPoint,&origin),AXUIElementSetAttributeValue(w.element,kAXPositionAttribute as CFString,v) == .success else{return false}
                fit();return true
            })
        NSRunningApplication(processIdentifier:w.owner)?.activate(options:[])
        AXUIElementPerformAction(w.element,kAXRaiseAction as CFString)
    }
    func retrieve(_ window:DeskWindow,to destination:UInt32,progress:@escaping @MainActor (String)->Void) async throws {
        guard !retrieving else {throw TVError("A window move is still finishing. Try again shortly.")}
        retrieving=true;defer{retrieving=false}
        let task=Task.detached(priority:.userInitiated) { [self] in
            func snapshot() async throws -> WindowRetrieval.Snapshot {
                try Task.checkCancellation()
                let screens=await self.screens
                guard AXIsProcessTrusted() else{throw TVError("Enable Accessibility to move windows.")}
                var pid:pid_t=0
                let pidStatus=AXUIElementGetPid(window.element,&pid)
                if pidStatus == .cannotComplete {throw WindowRetrieval.ReadError.temporarilyUnavailable}
                guard pidStatus == .success,pid==window.owner else {
                    throw TVError("That window closed or is no longer available.")
                }
                if let expected=window.nativeWindowID {
                    guard let actual=WindowServerGeometry.id(window.element) else{throw WindowRetrieval.ReadError.temporarilyUnavailable}
                    guard actual==expected else{throw TVError("The app replaced that window. Refresh the choices; no different window will be moved.")}
                }
                guard AXDesk.value(window.element,kAXMinimizedAttribute) as? Bool != true else {
                    throw TVError("That window was minimized. Restore it and refresh the choices.")
                }
                // AppKit temporarily withdraws a fullscreen window's metadata
                // during exit, even though its AX element, PID and ID survive.
                // Keep exact identity checks, but let the bounded transaction
                // wait for its geometry instead of declaring it closed.
                guard let frame=AXDesk.frame(window.element),let screen=AXDesk.screen(frame,in:screens) else {
                    throw WindowRetrieval.ReadError.temporarilyUnavailable
                }
                return WindowRetrieval.Snapshot(screen:screen.id,rect:frame,usable:screen.usable,fullFrame:screen.frame,
                    fullScreen:AXDesk.value(window.element,"AXFullScreen") as? Bool == true,
                    canExitFullScreen:AXDesk.settable(window.element,"AXFullScreen"),movable:AXDesk.settable(window.element,kAXPositionAttribute))
            }
            try await WindowRetrieval.run(original:window.original,destination:destination,read:snapshot,target:{
                guard await self.trusted else{throw TVError("Accessibility permission was removed.")}
                guard let target=await self.screens.first(where:{$0.id==destination})?.usable else {
                    throw TVError("Destination display disconnected. No further move was sent.")
                };return target
            },exitFullScreen:{
                try Task.checkCancellation()
                guard AXUIElementSetAttributeValue(window.element,"AXFullScreen" as CFString,kCFBooleanFalse) == .success else {
                    throw TVError("This app refused to leave full screen. Exit full screen manually and try again.")
                }
            },write:{frame in
                try Task.checkCancellation()
                var size=frame.size,origin=frame.origin
                if AXDesk.settable(window.element,kAXSizeAttribute),let value=AXValueCreate(.cgSize,&size) {
                    _ = AXUIElementSetAttributeValue(window.element,kAXSizeAttribute as CFString,value)
                }
                try Task.checkCancellation()
                guard let value=AXValueCreate(.cgPoint,&origin),
                      AXUIElementSetAttributeValue(window.element,kAXPositionAttribute as CFString,value) == .success else {
                    throw TVError("The app refused the window move. Check its current position.")
                }
                try Task.checkCancellation()
                if AXDesk.settable(window.element,kAXSizeAttribute),let value=AXValueCreate(.cgSize,&size) {
                    _ = AXUIElementSetAttributeValue(window.element,kAXSizeAttribute as CFString,value)
                }
            },progress:{text in await progress(text)})
        }
        try await withTaskCancellationHandler(operation:{try await task.value},onCancel:{task.cancel()})
        try Task.checkCancellation()
        NSRunningApplication(processIdentifier:window.owner)?.activate(options:[])
        AXUIElementPerformAction(window.element,kAXRaiseAction as CFString)
    }
}
