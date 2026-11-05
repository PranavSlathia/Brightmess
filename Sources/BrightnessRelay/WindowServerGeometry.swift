import AppKit
import ApplicationServices
import BrightnessCore
import Darwin

/// Metadata only: no images, window names, ScreenCaptureKit or permission prompt.
enum WindowServerGeometry {
    private typealias GetWindow = @convention(c) (AXUIElement,UnsafeMutablePointer<UInt32>)->Int32
    // Rectangle uses this AX-to-window-ID bridge too. Resolve at runtime so a
    // missing private symbol cannot prevent launch on a future macOS version.
    private static let getWindow:GetWindow? = {
        guard let handle=dlopen(nil,RTLD_LAZY),let symbol=dlsym(handle,"_AXUIElementGetWindow") else{return nil}
        return unsafeBitCast(symbol,to:GetWindow.self)
    }()
    static func id(_ element:AXUIElement)->UInt32? {
        if let number=AXDesk.value(element,"AXWindowNumber") as? NSNumber,number.uint32Value != 0 {return number.uint32Value}
        var id:UInt32=0
        guard getWindow?(element,&id)==AXError.success.rawValue,id != 0 else{return nil}
        return id
    }
    static func records(only windowID:UInt32?=nil)->[WindowGeometry.Record]? {
        let options:CGWindowListOption=windowID == nil ? [.optionAll,.excludeDesktopElements]:.optionIncludingWindow
        guard let rows=CGWindowListCopyWindowInfo(options,windowID ?? kCGNullWindowID) as? [[String:Any]] else{return nil}
        return rows.compactMap { row in
            guard let id=row[kCGWindowNumber as String] as? NSNumber,
                  let owner=row[kCGWindowOwnerPID as String] as? NSNumber,
                  let bounds=row[kCGWindowBounds as String] as? NSDictionary,
                  let frame=CGRect(dictionaryRepresentation:bounds) else{return nil}
            return .init(id:id.uint32Value,owner:owner.int32Value,frame:frame)
        }
    }
}
