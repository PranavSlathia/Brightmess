import AppKit
import ApplicationServices
import BrightnessCore
import Darwin

@MainActor protocol ArrangePort:ArrangementDriver {
    var trusted:Bool {get}
    func capture(_ display:ArrangementDisplay) async throws -> [ArrangementWindow]
}

/// Own adapter so the isolated feature does not replace the main chat's
/// cross-display/fullscreen implementation. Only ordinary current-Space windows.
@MainActor final class ArrangeNativePort:ArrangePort {
    private var elements=[String:AXUIElement]()
    var trusted:Bool {AXIsProcessTrusted()}
    static func display(for screen:NSScreen)->ArrangementDisplay? {
        guard let number=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else{return nil}
        let r=screen.visibleFrame,top=CGDisplayBounds(CGMainDisplayID()).height
        return .init(id:number.uint32Value,name:screen.localizedName=="LU28R55" ? "Samsung":screen.localizedName=="Beyond TV" ? "TV":screen.localizedName,
            usable:CGRect(x:r.minX,y:top-r.maxY,width:r.width,height:r.height),scale:screen.backingScaleFactor)
    }
    func display(_ id:UInt32) async -> ArrangementDisplay? {
        NSScreen.screens.compactMap{Self.display(for:$0)}.first{$0.id==id}
    }
    func capture(_ display:ArrangementDisplay) async throws -> [ArrangementWindow] {
        guard trusted else{throw TVError("Enable Accessibility for BRIGHTMESS to arrange windows.")}
        let apps=NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated && !$0.isHidden}
            .map{($0.processIdentifier,$0.localizedName ?? "Application")}
        let screens=NSScreen.screens.compactMap{Self.display(for:$0)}
        let job=Task.detached(priority:.userInitiated) { () -> [(ArrangementWindow,AXUIElement)] in
            let records=ArrangeAX.records()
            var result=[(ArrangementWindow,AXUIElement)]()
            for (pid,name) in apps {
                try Task.checkCancellation()
                let app=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(app,0.25)
                for element in ArrangeAX.value(app,kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                    try Task.checkCancellation();AXUIElementSetMessagingTimeout(element,0.25)
                    guard ArrangeAX.value(element,kAXRoleAttribute) as? String==kAXWindowRole,
                          ArrangeAX.value(element,kAXSubroleAttribute) as? String==kAXStandardWindowSubrole,
                          (try? ArrangeAX.flag(element,kAXMinimizedAttribute)) == false,
                          (try? ArrangeAX.flag(element,"AXFullScreen")) == false,
                          ArrangeAX.settable(element,kAXPositionAttribute),
                          let id=ArrangeAX.id(element),let record=records[id],record.owner==pid,
                          let frame=ArrangeAX.resolvedFrame(element,id:id,record:record),
                          screens.max(by:{ArrangeAX.area($0.usable,frame)<ArrangeAX.area($1.usable,frame)})?.id==display.id,
                          ArrangeAX.area(display.usable,frame)>0 else{continue}
                    let minimum=ArrangeAX.minimum(element)
                    let window=ArrangementWindow(id:"\(pid):\(id)",app:name,title:ArrangeAX.value(element,kAXTitleAttribute) as? String ?? "Untitled window",
                        frame:frame,minimum:minimum,resizable:ArrangeAX.settable(element,kAXSizeAttribute))
                    result.append((window,element))
                }
            }
            return result
        }
        let result=try await withTaskCancellationHandler(operation:{try await job.value},onCancel:{job.cancel()})
        elements.merge(Dictionary(result.map{($0.0.id,$0.1)},uniquingKeysWith:{$1})){$1}
        return result.map(\.0)
    }
    func read(_ id:String) async throws -> CGRect {
        guard trusted,let element=elements[id] else{throw TVError("Window unavailable or Accessibility permission removed.")}
        let job=Task.detached(priority:.userInitiated){try ArrangeAX.checkedFrame(element,id:id)}
        return try await withTaskCancellationHandler(operation:{try await job.value},onCancel:{job.cancel()})
    }
    func write(_ id:String,frame:CGRect) async throws {
        guard trusted,let element=elements[id],ArrangementPlanner.valid(frame) else{throw TVError("Window unavailable or invalid target.")}
        let job=Task.detached(priority:.userInitiated) {
            try Task.checkCancellation();try ArrangeAX.checkedIdentity(element,id:id)
            var size=frame.size,origin=frame.origin
            if ArrangeAX.settable(element,kAXSizeAttribute),let value=AXValueCreate(.cgSize,&size) {
                _ = AXUIElementSetAttributeValue(element,kAXSizeAttribute as CFString,value)
            }
            // A resize can temporarily withdraw/update WindowServer geometry.
            // Keep exact identity checks here; bounded geometry readback belongs
            // after the single write sequence, never between resize and move.
            try Task.checkCancellation();try ArrangeAX.checkedIdentity(element,id:id)
            guard let value=AXValueCreate(.cgPoint,&origin),AXUIElementSetAttributeValue(element,kAXPositionAttribute as CFString,value) == .success else {
                throw TVError("An app refused its position. Undo this attempt or refresh the preview.")
            }
            try Task.checkCancellation()
            if ArrangeAX.settable(element,kAXSizeAttribute),let value=AXValueCreate(.cgSize,&size) {
                _ = AXUIElementSetAttributeValue(element,kAXSizeAttribute as CFString,value)
            }
        }
        try await withTaskCancellationHandler(operation:{try await job.value},onCancel:{job.cancel()})
    }
}

private enum ArrangeAX {
    static func flag(_ element:AXUIElement,_ key:String)throws->Bool {
        var value:CFTypeRef?
        let status=AXUIElementCopyAttributeValue(element,key as CFString,&value)
        if status == .attributeUnsupported{return false}
        guard status == .success,let flag=value as? Bool else{throw TVError("A window is not responding. Refresh the preview before arranging.")}
        return flag
    }
    static func value(_ element:AXUIElement,_ key:String)->CFTypeRef? {
        var value:CFTypeRef?
        return AXUIElementCopyAttributeValue(element,key as CFString,&value) == .success ? value:nil
    }
    static func settable(_ element:AXUIElement,_ key:String)->Bool {
        var result=DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element,key as CFString,&result) == .success && result.boolValue
    }
    struct Record {let owner:Int32,frame:CGRect,onScreen:Bool}
    static func id(_ element:AXUIElement)->UInt32? {WindowServerGeometry.id(element)}
    static func records(_ only:UInt32?=nil)->[UInt32:Record] {
        let options:CGWindowListOption=only == nil ? [.optionOnScreenOnly,.excludeDesktopElements]:.optionIncludingWindow
        let rows=CGWindowListCopyWindowInfo(options,only ?? kCGNullWindowID) as? [[String:Any]] ?? []
        var values=[UInt32:Record]()
        for row in rows {
            guard let id=row[kCGWindowNumber as String] as? NSNumber,let pid=row[kCGWindowOwnerPID as String] as? NSNumber,
                  let bounds=row[kCGWindowBounds as String] as? NSDictionary,let frame=CGRect(dictionaryRepresentation:bounds),
                  ArrangementPlanner.valid(frame) else{continue}
            values[id.uint32Value] = .init(owner:pid.int32Value,frame:frame,onScreen:row[kCGWindowIsOnscreen as String] as? Bool == true)
        };return values
    }
    static func area(_ a:CGRect,_ b:CGRect)->CGFloat {let r=a.intersection(b);return r.isNull || r.isEmpty ? 0:r.width*r.height}
    static func resolvedFrame(_ element:AXUIElement,id:UInt32,record:Record)->CGRect? {
        guard record.onScreen,let logical=AXDesk.accessibilityFrame(element) else{return nil}
        return WindowGeometry.resolve(accessibility:logical,windowID:id,owner:record.owner,
            records:[.init(id:id,owner:record.owner,frame:record.frame)])
    }
    static func checkedIdentity(_ element:AXUIElement,id expected:String)throws {
        var pid:pid_t=0
        guard AXUIElementGetPid(element,&pid) == .success,let id=id(element),"\(pid):\(id)"==expected,
              try !flag(element,kAXMinimizedAttribute),try !flag(element,"AXFullScreen") else {
            throw TVError("That exact window is unavailable. Refresh the preview.")
        }
    }
    static func checkedFrame(_ element:AXUIElement,id expected:String)throws->CGRect {
        try checkedIdentity(element,id:expected)
        var pid:pid_t=0
        guard AXUIElementGetPid(element,&pid) == .success,let id=id(element),"\(pid):\(id)"==expected,
              let record=records(id)[id],record.owner==pid,
              let frame=resolvedFrame(element,id:id,record:record) else{throw TVError("That exact window is not on this desktop or its geometry is settling. Refresh the preview.")}
        return frame
    }
    static func minimum(_ element:AXUIElement)->CGSize {
        var size=CGSize(width:320,height:200)
        if let value=ArrangeAX.value(element,"AXMinSize"),CFGetTypeID(value)==AXValueGetTypeID() {
            var reported=CGSize.zero
            if AXValueGetValue(value as! AXValue,.cgSize,&reported),reported.width.isFinite,reported.height.isFinite {
                size.width=max(size.width,reported.width);size.height=max(size.height,reported.height)
            }
        };return size
    }
}
