import AppKit
import ApplicationServices
import BrightnessCore

struct DeskWindow: Identifiable {
    let id = UUID()
    let app: String, title: String, owner: pid_t, element: AXUIElement
    var original: CGDirectDisplayID
    var shelfTicket: UUID?
    var displayTitle: String { title.isEmpty ? "Untitled window" : title }
}

struct ShelfScreen {
    let id: CGDirectDisplayID, name: String, frame: CGRect, usable: CGRect
}

@MainActor protocol WindowDeskPort {
    var trusted: Bool { get }
    var screens: [ShelfScreen] { get }
    func current(previous: NSRunningApplication?) -> DeskWindow?
    func inventory(excluding destination: CGDirectDisplayID, screens: [ShelfScreen]) async -> [DeskWindow]
    func move(_ window: DeskWindow, to destination: CGDirectDisplayID) throws
    func icon(for window: DeskWindow) -> NSImage?
}

private enum AXDesk {
    static func value(_ el: AXUIElement,_ key: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el,key as CFString,&v) == .success ? v : nil
    }
    static func settable(_ el: AXUIElement,_ attr: String) -> Bool {
        var v=DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(el,attr as CFString,&v) == .success && v.boolValue
    }
    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p=value(el,kAXPositionAttribute), let s=value(el,kAXSizeAttribute),
              CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else{return nil}
        var point=CGPoint.zero,size=CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size),
              size.width>0,size.height>0 else{return nil}
        return CGRect(origin:point,size:size)
    }
    static func screen(_ rect:CGRect,in screens:[ShelfScreen])->ShelfScreen? {
        screens.compactMap { screen -> (ShelfScreen,CGFloat)? in
            let r=screen.frame.intersection(rect)
            return r.isEmpty || r.isNull ? nil : (screen,r.width*r.height)
        }.max{$0.1<$1.1}?.0
    }
    static func entry(_ el:AXUIElement,pid:pid_t,name:String,screens:[ShelfScreen],
                      excluding destination:UInt32?=nil,readTitle:Bool=true)->DeskWindow? {
        AXUIElementSetMessagingTimeout(el,0.25)
        guard let rect=frame(el),let s=screen(rect,in:screens),s.id != destination,
              value(el,kAXRoleAttribute) as? String == kAXWindowRole,
              value(el,kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              value(el,kAXMinimizedAttribute) as? Bool != true,value(el,"AXFullScreen") as? Bool != true,
              settable(el,kAXPositionAttribute) else{return nil}
        return DeskWindow(app:name,title:readTitle ? (value(el,kAXTitleAttribute) as? String ?? ""):"",owner:pid,element:el,original:s.id)
    }
}

/// AppKit metadata stays on the main actor. Potentially slow, read-only AX
/// enumeration runs off it, once per open/refresh, never on an idle timer.
@MainActor final class MacWindowDesk: WindowDeskPort {
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
        let apps=NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated}
            .map{($0.processIdentifier,$0.localizedName ?? "Application")}
        let job=Task.detached(priority:.userInitiated) { () -> [DeskWindow] in
            var out=[DeskWindow]()
            for (pid,name) in apps {
                guard !Task.isCancelled else{return []}
                let ax=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(ax,0.25)
                for el in AXDesk.value(ax,kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                    guard !Task.isCancelled else{return []}
                    if let w=AXDesk.entry(el,pid:pid,name:name,screens:screens,excluding:destination) {out.append(w)}
                }
            }
            return out.sorted{($0.app,$0.title)<($1.app,$1.title)}
        }
        return await withTaskCancellationHandler(operation:{await job.value},onCancel:{job.cancel()})
    }
    func move(_ w:DeskWindow,to id:UInt32)throws {
        try WindowPlacement.move(original:w.original,destination:id,trusted:trusted,
            usable:{ id in self.screens.first{$0.id==id}?.usable },read:{
                var pid:pid_t=0
                guard AXUIElementGetPid(w.element,&pid) == .success,pid==w.owner,
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
}
