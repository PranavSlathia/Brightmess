#if DEBUG
import AppKit
import ApplicationServices
import SwiftUI
import BrightnessCore

@MainActor final class ArrangeFixturePort:ArrangePort,ObservableObject {
    var trusted=true
    let screen:ArrangementDisplay
    var windows:[ArrangementWindow]
    var frames=[String:CGRect]()
    @Published var writes=0
    init(screen:ArrangementDisplay){
        self.screen=screen
        windows=[("Terminal","Build output",CGSize(width:720,height:900)),("Aside","Reading list",CGSize(width:850,height:950)),("Zen","Video reference",CGSize(width:1100,height:650)),("Notes","Project notes",CGSize(width:650,height:750))].enumerated().map { index,item in
            .init(id:"fixture-\(index)",app:item.0,title:item.1,frame:CGRect(x:screen.usable.minX+CGFloat(index*45),y:screen.usable.minY+CGFloat(index*65),width:item.2.width,height:item.2.height))
        }
        frames=Dictionary(uniqueKeysWithValues:windows.map{($0.id,$0.frame)})
    }
    func display(_ id:UInt32)async->ArrangementDisplay? {id==screen.id ? screen:nil}
    func capture(_ display:ArrangementDisplay)async throws->[ArrangementWindow]{
        guard trusted else{throw TVError("Enable Accessibility for BRIGHTMESS to arrange windows.")}
        return windows.map{.init(id:$0.id,app:$0.app,title:$0.title,frame:frames[$0.id] ?? $0.frame,minimum:$0.minimum,resizable:$0.resizable)}
    }
    func read(_ id:String)async throws->CGRect{guard let frame=frames[id] else{throw TVError("Closed fixture")};return frame}
    func write(_ id:String,frame:CGRect)async throws{frames[id]=frame;writes+=1}
}

@MainActor enum ArrangeChecks {
    static func nativeWindows(screenName:String)async throws {
        let apps=NSWorkspace.shared.runningApplications.filter{$0.bundleIdentifier=="dev.pranav.brightmess.arrange-windows-test" && !$0.isTerminated}
        guard apps.count==1,let app=apps.first,
              let screen=NSScreen.screens.first(where:{$0.localizedName==screenName}),
              let display=ArrangeNativePort.display(for:screen) else{throw TVError("Expected one owned three-window fixture and the named display")}
        let port=ArrangeNativePort()
        guard port.trusted else{throw TVError("Native fixture check requires existing Accessibility access")}
        let windows=try await port.capture(display).filter{$0.id.hasPrefix("\(app.processIdentifier):")}
        guard windows.count==3,let plan=ArrangementPlanner.plan(windows:windows,display:display,mode:.smart) else{throw TVError("Expected exactly three normal owned fixture windows on this display")}
        let appAX=AXUIElementCreateApplication(app.processIdentifier)
        print("Owned fixture enhanced UI: \(String(describing:AXDesk.value(appAX,"AXEnhancedUserInterface")))")
        let result=await ArrangementTransaction.apply(plan,driver:port)
        for item in plan.items {
            print("Fixture \(item.window.id): before=\(item.window.frame), target=\(item.target), observed=\(String(describing:try? await port.read(item.window.id)))")
        }
        let recovery=await ArrangementTransaction.undo(result.undo,driver:port)
        print(recovery.message)
        guard result.complete,recovery.remaining.entries.isEmpty else{throw TVError("Native arrangement failed: \(result.message)")}
        print("Native arrangement and Undo passed for three owned windows on \(screenName).")
    }
    static func run()async throws {
        let d=ArrangementDisplay(id:1,name:"Samsung",usable:CGRect(x:0,y:0,width:1440,height:2560))
        let port=ArrangeFixturePort(screen:d),model=ArrangeModel(port:port)
        model.open(d);await model.finish()
        guard model.plan?.items.count==4,port.writes==0 else{throw TVError("Preview moved windows or missed choices")}
        model.selectAll(false)
        guard model.plan==nil,model.selected.isEmpty,port.writes==0 else{throw TVError("Deselect-all changed windows")}
        model.selectAll(true)
        model.include("fixture-0",false)
        model.choose(.equal)
        guard model.plan?.items.count==3,port.writes==0 else{throw TVError("Exclusion/mode change wrote native frames")}
        model.apply();await model.finish()
        guard port.writes==3,model.canUndo,model.stage == .result else{throw TVError("Arrangement did not preserve Undo")}
        model.undo();await model.finish()
        guard port.writes==6,!model.canUndo else{throw TVError("Undo failed")}
        model.refresh();await model.finish();model.topologyChanged()
        guard model.plan==nil else{throw TVError("Topology retained an unsafe plan")}
        model.close();port.trusted=false;model.open(d);await model.finish()
        guard model.plan==nil,model.message.contains("Accessibility") else{throw TVError("Permission state missing")}
        model.close()
        print("Arrange model checks passed: preview-only, exclusion, mode, apply, undo, topology and denied access.")
    }
    static func render(folder:URL)async throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for portrait in [true,false] {for dark in [false,true] {
            let size=portrait ? CGSize(width:1440,height:2560):CGSize(width:1920,height:1080)
            let d=ArrangementDisplay(id:1,name:portrait ? "Samsung":"TV",usable:CGRect(origin:.zero,size:size))
            let model=ArrangeModel(port:ArrangeFixturePort(screen:d));model.open(d);await model.finish()
            let root=NSView(frame:CGRect(origin:.zero,size:size));root.wantsLayer=true
            root.layer?.backgroundColor=(dark ? NSColor(calibratedRed:0.10,green:0.17,blue:0.18,alpha:1):NSColor(calibratedRed:0.78,green:0.84,blue:0.81,alpha:1)).cgColor
            let label=NSTextField(labelWithString:"Synthetic desktop · BRIGHTMESS zone preview")
            label.font = .systemFont(ofSize:14);label.textColor=dark ? .white:.black
            label.frame=CGRect(x:28,y:0,width:650,height:20)
            let outlines=ArrangeOutlineView(frame:root.bounds);outlines.plan=model.plan;root.addSubview(outlines)
            root.addSubview(label)
            let hud=NSHostingView(rootView:ArrangeHUD(model:model,close:{}).environment(\.controlActiveState,.key))
            hud.frame=CGRect(x:(size.width-540)/2,y:24,width:540,height:170);root.addSubview(hud)
            let window=NSWindow(contentRect:root.bounds,styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:dark ? .darkAqua:.aqua);window.contentView=root
            root.layoutSubtreeIfNeeded();window.displayIfNeeded()
            let suffix=(portrait ? "portrait":"landscape")+(dark ? "-dark":"-light")
            try capture(root,to:folder.appendingPathComponent(suffix+".png"))
            try capture(hud,to:folder.appendingPathComponent(suffix+"-controls.png"))
            model.close();window.close()
            if !portrait {
                for state in ["expanded","empty","permission","result"] {
                    let port=ArrangeFixturePort(screen:d)
                    if state=="empty"{port.windows=[]}
                    if state=="permission"{port.trusted=false}
                    let sample=ArrangeModel(port:port);sample.open(d);await sample.finish()
                    if state=="expanded"{sample.showWindows=true}
                    if state=="result"{sample.apply();await sample.finish()}
                    let host=NSHostingView(rootView:ArrangeHUD(model:sample,close:{}).environment(\.controlActiveState,.key))
                    let size=CGSize(width:540,height:state=="expanded" ? 320:170)
                    let w=NSWindow(contentRect:CGRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
                    w.isReleasedWhenClosed=false;w.appearance=NSAppearance(named:dark ? .darkAqua:.aqua);w.contentView=host
                    host.frame=CGRect(origin:.zero,size:size);host.layoutSubtreeIfNeeded();w.displayIfNeeded()
                    try capture(host,to:folder.appendingPathComponent(state+(dark ? "-dark":"-light")+".png"))
                    sample.close();w.close()
                }
            }
        }}
        print("Rendered full-screen zone outlines and controls in portrait/landscape, light/dark; fixture data only.")
    }
    private static func capture(_ view:NSView,to url:URL)throws {
        guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{throw TVError("Native fixture capture unavailable")}
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let data=bitmap.representation(using:.png,properties:[:]) else{throw TVError("PNG encoding failed")}
        try data.write(to:url)
    }
}
#endif
