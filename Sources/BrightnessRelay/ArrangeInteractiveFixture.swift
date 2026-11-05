#if DEBUG
import AppKit
import SwiftUI
import BrightnessCore

/// Interactive computer-use harness. No receiver, hardware driver, Keychain
/// identity, real AX window port or global shortcut registration is created.
@MainActor final class ArrangeInteractiveFixture:NSObject,NSApplicationDelegate {
    private static var retained:ArrangeInteractiveFixture?
    private var window:NSWindow?
    private var controller:ArrangePanelController?
    private var shortcuts:DeskShortcuts?
    private let suite="dev.pranav.brightmess.arrange-fixture."+UUID().uuidString

    static func run(){
        let app=NSApplication.shared,fixture=ArrangeInteractiveFixture()
        retained=fixture;app.setActivationPolicy(.regular);app.delegate=fixture
        let menu=NSMenu(),appItem=NSMenuItem(),appMenu=NSMenu()
        appMenu.addItem(withTitle:"Quit Arrange Fixture",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appItem.submenu=appMenu;menu.addItem(appItem);app.mainMenu=menu
        app.run()
    }
    func applicationDidFinishLaunching(_ notification:Notification){
        guard let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? NSScreen.main,
              let display=ArrangeNativePort.display(for:screen),let defaults=UserDefaults(suiteName:suite) else{NSApp.terminate(nil);return}
        let port=ArrangeFixturePort(screen:display),model=ArrangeModel(port:port)
        let controller=ArrangePanelController(model:model),shortcuts=DeskShortcuts.fixture(defaults:defaults)
        self.controller=controller;self.shortcuts=shortcuts
        let view=ArrangeFixtureLauncher(port:port,shortcuts:shortcuts,open:{controller.toggle()})
        let window=NSWindow(contentRect:CGRect(x:0,y:0,width:570,height:470),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="BRIGHTMESS Arrange Fixture — simulated windows"
        window.isReleasedWhenClosed=false;window.contentView=NSHostingView(rootView:view)
        window.setFrameOrigin(CGPoint(x:screen.visibleFrame.midX-window.frame.width/2,y:screen.visibleFrame.midY-window.frame.height/2))
        self.window=window;window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func applicationWillTerminate(_ notification:Notification){
        controller?.stop();shortcuts?.stop();UserDefaults.standard.removePersistentDomain(forName:suite)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
}

private struct ArrangeFixtureLauncher:View {
    @ObservedObject var port:ArrangeFixturePort
    @ObservedObject var shortcuts:DeskShortcuts
    var open:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:14){
            Text("Arrange here · interaction test").font(.title2.bold())
            Text("Simulated windows only. Your real windows, TV and installed BRIGHTMESS stay untouched.").fixedSize(horizontal:false,vertical:true)
            ArrangeDeskAction(shortcuts:shortcuts,perform:open)
            Text("Simulated writes: \(port.writes)").font(.headline).accessibilityIdentifier("arrange.fixture.writes")
            DeskShortcutEditor(shortcuts:shortcuts)
            Text("Shortcut registration is simulated here. No global keys are claimed. Apply, Undo and Return/Escape use the real panel controls.")
                .font(.caption).foregroundStyle(DeckPaint.muted).fixedSize(horizontal:false,vertical:true)
            HStack{Spacer();Button("Quit fixture"){NSApp.terminate(nil)}}
        }.padding(18).frame(width:570).foregroundStyle(DeckPaint.ink).background(DeckPaint.ground).tint(DeckPaint.accent)
    }
}
#endif
