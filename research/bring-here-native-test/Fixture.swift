import AppKit

/// Owns one disposable window. No AX calls, remote control, global keys or network.
final class Fixture:NSObject,NSApplicationDelegate,NSWindowDelegate {
    var window:NSWindow!
    let lifecycleAudit=CommandLine.arguments.contains("--audit-full-screen")
    let startFullScreen=CommandLine.arguments.contains("--full-screen")
    var initialNumber=0,fullNumber=0
    let position=NSTextField(labelWithString:"")
    func applicationDidFinishLaunching(_ note:Notification){
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:340),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        window.title="BRIGHTMESS movement test";window.delegate=self;window.isReleasedWhenClosed=false
        window.collectionBehavior=[.fullScreenPrimary];window.contentMinSize=NSSize(width:360,height:240)
        let content=NSStackView();content.orientation = .vertical;content.alignment = .leading;content.spacing=16
        content.edgeInsets=NSEdgeInsets(top:30,left:30,bottom:30,right:30)
        let heading=NSTextField(labelWithString:"Disposable window movement test")
        heading.font = .systemFont(ofSize:20,weight:.bold);content.addArrangedSubview(heading)
        let explanation=NSTextField(wrappingLabelWithString:"Only this test window should move. No documents or TV inputs are changed. Close it when testing is complete.")
        content.addArrangedSubview(explanation);content.addArrangedSubview(position)
        content.addArrangedSubview(NSButton(title:"Toggle full screen",target:self,action:#selector(fullScreen)))
        content.addArrangedSubview(NSButton(title:"Reset this window to TV",target:self,action:#selector(reset)))
        content.addArrangedSubview(NSButton(title:"Close test",target:self,action:#selector(quit)))
        window.contentView=content
        let menu=NSMenu(),app=NSMenu(),item=NSMenuItem();app.addItem(withTitle:"Quit Window Test",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");item.submenu=app;menu.addItem(item);NSApp.mainMenu=menu
        reset();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        if CommandLine.arguments.contains("--on-samsung"),let screen=NSScreen.screens.first(where:{$0.localizedName=="LU28R55"}) {
            window.setFrame(NSRect(x:screen.visibleFrame.midX-270,y:screen.visibleFrame.midY-170,width:540,height:340),display:true);update()
        }
        if startFullScreen {DispatchQueue.main.asyncAfter(deadline:.now()+0.5){self.window.toggleFullScreen(nil)}}
        if lifecycleAudit {
            initialNumber=window.windowNumber
            print("FIXTURE normal id=\(initialNumber)");fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5){self.window.toggleFullScreen(nil)}
            DispatchQueue.main.asyncAfter(deadline:.now()+12){
                fputs("FIXTURE lifecycle deadline\n",stderr);NSApp.terminate(nil)
            }
        }
    }
    @objc func fullScreen(){window.toggleFullScreen(nil)}
    @objc func reset(){
        guard !window.styleMask.contains(.fullScreen) else{return}
        let screen=NSScreen.screens.first{$0.localizedName.localizedCaseInsensitiveContains("beyond")} ?? NSScreen.main!
        window.setFrame(NSRect(x:screen.visibleFrame.midX-270,y:screen.visibleFrame.midY-170,width:540,height:340),display:true)
        update()
    }
    @objc func quit(){NSApp.terminate(nil)}
    func update(){position.stringValue="Current display: \(window.screen?.localizedName ?? "unknown") · \(window.styleMask.contains(.fullScreen) ? "Full screen":"Normal window")"}
    func windowDidMove(_ n:Notification){update()}
    func windowDidChangeScreen(_ n:Notification){update()}
    func windowDidEnterFullScreen(_ n:Notification){
        update()
        if startFullScreen {print("FIXTURE ready full-screen id=\(window.windowNumber)");fflush(stdout)}
        if lifecycleAudit {
            fullNumber=window.windowNumber;print("FIXTURE full-screen id=\(fullNumber)");fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5){self.window.toggleFullScreen(nil)}
        }
    }
    func windowDidExitFullScreen(_ n:Notification){
        update()
        if lifecycleAudit {
            print("FIXTURE restored id=\(window.windowNumber), full-screen identity changed=\(fullNumber != window.windowNumber)");fflush(stdout)
            NSApp.terminate(nil)
        }
    }
    func windowWillClose(_ n:Notification){quit()}
}
let app=NSApplication.shared,fixture=Fixture()
app.setActivationPolicy(.regular);app.delegate=fixture
withExtendedLifetime(fixture){app.run()}
