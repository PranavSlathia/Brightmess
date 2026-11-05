// Read-only diagnostic for the reported Aside screen-assignment bug.
// No window titles, URLs, screenshots, movement, focus changes or permissions.
import AppKit
import ApplicationServices
import Darwin

typealias WindowIDFunction = @convention(c) (AXUIElement,UnsafeMutablePointer<UInt32>)->Int32
let symbols=dlopen(nil,RTLD_LAZY)
let getID=symbols.flatMap{dlsym($0,"_AXUIElementGetWindow")}.map{unsafeBitCast($0,to:WindowIDFunction.self)}

func value(_ element:AXUIElement,_ name:String)->CFTypeRef? {
    var result:CFTypeRef?
    return AXUIElementCopyAttributeValue(element,name as CFString,&result) == .success ? result:nil
}
func frame(_ element:AXUIElement)->CGRect? {
    guard let p=value(element,kAXPositionAttribute),let s=value(element,kAXSizeAttribute),
          CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID() else{return nil}
    var point=CGPoint.zero,size=CGSize.zero
    guard AXValueGetValue(p as! AXValue,.cgPoint,&point),AXValueGetValue(s as! AXValue,.cgSize,&size) else{return nil}
    return CGRect(origin:point,size:size)
}
print("Accessibility trusted:",AXIsProcessTrusted())
let screens=NSScreen.screens.map { screen -> (UInt32,String,CGRect) in
    let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
    return (id,screen.localizedName,CGDisplayBounds(id))
}
for screen in screens {print("Display:",screen)}
let name=CommandLine.arguments.dropFirst().first ?? "Aside"
guard let app=NSWorkspace.shared.runningApplications.first(where:{$0.localizedName==name}) else{exit(2)}
let ax=AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(ax,0.5)
var sawTV=false
for (index,window) in ((value(ax,kAXWindowsAttribute) as? [AXUIElement]) ?? []).enumerated() {
    guard let frame=frame(window) else {print("AX window",index,"frame unavailable");continue}
    var windowID:UInt32=0
    let idStatus=getID?(window,&windowID)
    let source=screens.filter{!$0.2.intersection(frame).isEmpty}.max{
        let a=$0.2.intersection(frame),b=$1.2.intersection(frame);return a.width*a.height < b.width*b.height
    }
    print("AX window",index,"id",windowID,"id status",idStatus ?? -1,"frame",frame,"assigned",source?.1 ?? "none","fullScreen",value(window,"AXFullScreen") as? Bool ?? false)
    if source?.1=="Beyond TV" {sawTV=true}
}
for window in CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? [] {
    guard window[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier,
          window[kCGWindowLayer as String] as? Int == 0 else{continue}
    print("WindowServer ID:",window[kCGWindowNumber as String] ?? "unknown","frame:",window[kCGWindowBounds as String] ?? "unavailable")
}
guard sawTV else {fputs("FAIL: the reported \(name) window on TV was not assigned to TV by the legacy AX-only geometry path.\n",stderr);exit(1)}
print("PASS: \(name) is assigned to TV by legacy AX geometry.")
