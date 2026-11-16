import AppKit
import ApplicationServices
import BrightnessCore

/// The three window workflows share this adapter. Serializes the short scoped
/// accessibility-state change; no observer, timer, geometry polling or retries.
enum NativeWindowFrameWriter {
    private static let batchLock=NSLock()
    static func write(_ frame:CGRect,to element:AXUIElement,owner:pid_t,windowID:UInt32?,
                      assistiveTechnologyActive:Bool) throws {
        batchLock.lock();defer{batchLock.unlock()}
        func validate() throws {
            try Task.checkCancellation()
            guard AXIsProcessTrusted() else{throw TVError("Accessibility permission was removed. No further move sent.")}
            var actual:pid_t=0
            guard AXUIElementGetPid(element,&actual) == .success,actual==owner,
                  AXDesk.value(element,kAXRoleAttribute) as? String == kAXWindowRole,
                  AXDesk.value(element,kAXMinimizedAttribute) as? Bool != true,
                  AXDesk.value(element,"AXFullScreen") as? Bool != true else {
                throw TVError("That exact window is no longer ready to move. Refresh the choices.")
            }
            if let windowID,WindowServerGeometry.id(element) != windowID {
                throw TVError("The app replaced that window. No different window was moved.")
            }
        }
        try validate()
        let app=AXUIElementCreateApplication(owner);AXUIElementSetMessagingTimeout(app,0.25)
        let resize=AXDesk.settable(element,kAXSizeAttribute) && AXDesk.accessibilityFrame(element)?.size != frame.size
        try WindowFrameBatch.write(frame,resize:resize,assistiveTechnologyActive:assistiveTechnologyActive,
            validate:validate,readEnhanced:{AXDesk.value(app,"AXEnhancedUserInterface") as? Bool},
            setEnhanced:{value in
                _ = AXUIElementSetAttributeValue(app,"AXEnhancedUserInterface" as CFString,value ? kCFBooleanTrue:kCFBooleanFalse)
                let observed=AXDesk.value(app,"AXEnhancedUserInterface") as? Bool
                // AppKit can return kAXErrorNotImplemented even though this
                // private flag changed. Require positive state readback for
                // both disable and restore, not a misleading status code.
                return observed == value
            },
            setSize:{size in
                var size=size
                // Apps own minimum/grid constraints. As before, size is best effort;
                // exact identity is checked again before the required position write.
                if let value=AXValueCreate(.cgSize,&size) {
                    _ = AXUIElementSetAttributeValue(element,kAXSizeAttribute as CFString,value)
                }
            },setPosition:{origin in
                var origin=origin
                guard let value=AXValueCreate(.cgPoint,&origin) else{throw TVError("Invalid position")}
                let result=AXUIElementSetAttributeValue(element,kAXPositionAttribute as CFString,value)
                guard result == .success else {
                    throw TVError("The app refused the window position. Check the window before trying again.")
                }
            })
    }
}
