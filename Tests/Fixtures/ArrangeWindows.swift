import AppKit

// Three owned, disposable native windows for arrangement acceptance. No AX,
// external-window control, network, user documents or persistent preferences.
final class ArrangeWindows:NSObject,NSApplicationDelegate,NSWindowDelegate {
    var windows=[NSWindow](),labels=[NSTextField]()
    func applicationDidFinishLaunching(_ notification:Notification){
        let menu=NSMenu(),item=NSMenuItem(),appMenu=NSMenu()
        appMenu.addItem(withTitle:"Quit Arrange Windows Test",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        item.submenu=appMenu;menu.addItem(item);NSApp.mainMenu=menu
        for index in 0..<3 {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:340),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
            window.title="Arrange test \(index+1)";window.isReleasedWhenClosed=false;window.delegate=self
            // Fixture-only: remain visible on the destination's active Space
            // when the test buttons move them between physical displays.
            window.collectionBehavior=[.canJoinAllSpaces]
            window.contentMinSize=NSSize(width:320,height:200)
            let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=14
            stack.edgeInsets=NSEdgeInsets(top:20,left:20,bottom:20,right:20)
            stack.addArrangedSubview(NSTextField(labelWithString:"Disposable arrangement window \(index+1)"))
            stack.addArrangedSubview(NSTextField(wrappingLabelWithString:"Only these three test windows may be arranged. No personal documents or TV input changes."))
            let label=NSTextField(wrappingLabelWithString:"");labels.append(label);stack.addArrangedSubview(label)
            stack.addArrangedSubview(NSButton(title:"Place tests on Samsung",target:self,action:#selector(samsung)))
            stack.addArrangedSubview(NSButton(title:"Place tests on TV",target:self,action:#selector(tv)))
            stack.addArrangedSubview(NSButton(title:"Close all tests",target:self,action:#selector(quit)))
            window.contentView=stack;windows.append(window)
        }
        samsung();windows.forEach{$0.orderFront(nil)};windows.last?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func place(_ name:String){
        guard let screen=NSScreen.screens.first(where:{$0.localizedName==name}) else{return}
        for (index,window) in windows.enumerated(){
            window.setFrame(NSRect(x:screen.visibleFrame.minX+40+CGFloat(index*30),y:screen.visibleFrame.maxY-400-CGFloat(index*40),width:500,height:340),display:true)
        };update()
    }
    @objc func samsung(){place("LU28R55")}
    @objc func tv(){place("Beyond TV")}
    @objc func quit(){NSApp.terminate(nil)}
    func update(){for (index,window) in windows.enumerated(){
        labels[index].stringValue="Display: \(window.screen?.localizedName ?? "unknown")\nFrame: \(NSStringFromRect(window.frame))"
    }}
    func windowDidMove(_ notification:Notification){update()}
    func windowDidResize(_ notification:Notification){update()}
    func windowDidChangeScreen(_ notification:Notification){update()}
    func windowWillClose(_ notification:Notification){quit()}
}
let app=NSApplication.shared,owner=ArrangeWindows()
app.setActivationPolicy(.regular);app.delegate=owner
withExtendedLifetime(owner){app.run()}
