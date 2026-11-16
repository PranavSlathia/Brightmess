import AppKit

// One disposable window, never user documents or external AX targets.
final class MoveWindowFixture:NSObject,NSApplicationDelegate,NSWindowDelegate {
    var window:NSWindow!
    var label:NSTextField!
    func applicationDidFinishLaunching(_ notification:Notification) {
        let args=CommandLine.arguments
        let name=args.contains("--on-tv") ? "Beyond TV":"LU28R55"
        guard let screen=NSScreen.screens.first(where:{$0.localizedName==name}) else{NSApp.terminate(nil);return}
        window=NSWindow(contentRect:.zero,styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        window.title="BRIGHTMESS disposable move test";window.delegate=self;window.isReleasedWhenClosed=false
        window.collectionBehavior=[.fullScreenPrimary];window.tabbingMode = .disallowed
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=14
        stack.edgeInsets=NSEdgeInsets(top:20,left:20,bottom:20,right:20)
        stack.addArrangedSubview(NSTextField(labelWithString:"Disposable window — no personal content"))
        label=NSTextField(wrappingLabelWithString:"");stack.addArrangedSubview(label)
        stack.addArrangedSubview(NSButton(title:"Reset tall on Samsung",target:self,action:#selector(tall)))
        stack.addArrangedSubview(NSButton(title:"Reset wide on TV",target:self,action:#selector(wide)))
        stack.addArrangedSubview(NSButton(title:"Maximize on this display",target:self,action:#selector(maximize)))
        stack.addArrangedSubview(NSButton(title:"Toggle full screen",target:self,action:#selector(fullScreen)))
        stack.addArrangedSubview(NSButton(title:"Close test",target:self,action:#selector(closeTest)))
        window.contentView=stack
        let f=screen.visibleFrame
        let size=args.contains("--oversized") ? CGSize(width:min(1000,f.width-80),height:min(1800,f.height-80)):CGSize(width:620,height:420)
        window.setFrame(args.contains("--maximized") ? f:CGRect(x:f.minX+40,y:f.maxY-size.height-40,width:size.width,height:size.height),display:true)
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);update()
        if args.contains("--full-screen") {window.toggleFullScreen(nil)}
    }
    func update(){guard window != nil,label != nil else{return};label.stringValue="Display: \(window.screen?.localizedName ?? "unknown")\nFrame: \(NSStringFromRect(window.frame))"}
    func reset(_ name:String,_ size:CGSize){
        guard !window.styleMask.contains(.fullScreen),let screen=NSScreen.screens.first(where:{$0.localizedName==name}) else{return}
        let f=screen.visibleFrame
        window.setFrame(CGRect(x:f.minX+30,y:f.maxY-min(size.height,f.height-60)-30,width:min(size.width,f.width-60),height:min(size.height,f.height-60)),display:true);update()
    }
    @objc func tall(){reset("LU28R55",CGSize(width:900,height:1800))}
    @objc func wide(){reset("Beyond TV",CGSize(width:1800,height:900))}
    @objc func maximize(){guard !window.styleMask.contains(.fullScreen),let screen=window.screen else{return};window.setFrame(screen.visibleFrame,display:true);update()}
    @objc func fullScreen(){window.toggleFullScreen(nil)}
    @objc func closeTest(){NSApp.terminate(nil)}
    func windowDidMove(_ notification:Notification){update()}
    func windowDidResize(_ notification:Notification){update()}
    func windowWillClose(_ notification:Notification){NSApp.terminate(nil)}
}
let app=NSApplication.shared,delegate=MoveWindowFixture()
app.setActivationPolicy(.regular);app.delegate=delegate
withExtendedLifetime(delegate){app.run()}
