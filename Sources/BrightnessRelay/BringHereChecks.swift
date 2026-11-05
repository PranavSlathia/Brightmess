#if DEBUG
import AppKit
import ApplicationServices
import BrightnessCore

@MainActor final class PickerFixture:WindowRetrievalPort {
    let base=FixtureWindowDesk()
    var trusted:Bool {get{base.trusted} set{base.trusted=newValue}}
    var screens:[ShelfScreen] {get{base.screens} set{base.screens=newValue}}
    var writes:[UUID] {base.writes}
    var delayMove=false,movePending:CheckedContinuation<Void,Never>?
    init(){
        base.entries=[]
        for (app,title,screen) in [("Zen","Project notes",base.tv),("Arc","Research",base.tv),("Arc","Reading",base.tv),("Safari","Reading list",base.tv),("Preview","Contact sheet",base.samsung)] {
            base.entries.append(.init(app:app,title:title,owner:0,element:AXUIElementCreateSystemWide(),original:screen))
        }
    }
    func current(previous:NSRunningApplication?)->DeskWindow? {base.current(previous:previous)}
    func inventory(excluding destination:UInt32,screens:[ShelfScreen]) async->[DeskWindow]{await base.inventory(excluding:destination,screens:screens)}
    func retrievalInventory(excluding destination:UInt32,screens:[ShelfScreen]) async->[DeskWindow]{await inventory(excluding:destination,screens:screens)}
    func move(_ window:DeskWindow,to destination:UInt32)throws{try base.move(window,to:destination)}
    func icon(for window:DeskWindow)->NSImage? {
        let path=window.app=="Zen" ? "/Applications/Zen.app/Contents/Resources/firefox.icns":nil
        return path.flatMap{NSImage(contentsOfFile:$0)} ?? base.icon(for:window)
    }
    func retrieve(_ window:DeskWindow,to destination:UInt32,progress:@escaping @MainActor(String)->Void) async throws {
        progress(window.retrievalState == .fullScreen ? "Leaving full screen…":"Bringing window here…")
        if delayMove {delayMove=false;await withCheckedContinuation{movePending=$0}}
        try Task.checkCancellation();try move(window,to:destination)
    }
}

@MainActor enum BringHereChecks {
    static func run() async throws {
        func check(_ value:Bool,_ message:String)throws{if !value {throw TVError("Picker check: "+message)}}
        let port=PickerFixture(),model=BringHereModel(port:port)
        model.open(destination:port.base.samsung);await model.finish()
        try check(model.rows.map(\.key)==["Z","A","S"],"initials")
        model.key("tab");try check(model.selected==1,"Tab and arrow selection must agree")
        model.key("backtab");try check(model.selected==0,"Shift-Tab selection")
        model.key("a");try check(model.rows.map(\.key)==["1","2"],"numbered choices")
        let exact=model.rows[1].windows[0].id
        model.key("2");await model.finish()
        try check(port.writes==[exact] && !model.visible,"exact window and successful dismissal")
        model.open(destination:port.base.tv);await model.finish()
        try check(model.rows.contains{$0.app=="Arc"},"reverse")
        model.key("/");model.search("Reading");model.key("z")
        try check(port.writes.count==1 && model.rows.count==1,"search never runs initials")
        model.key("escape");try check(model.stage == .apps,"search cancellation")
        model.close();port.base.delay=true;model.open(destination:port.base.samsung)
        while port.base.pending==nil {await Task.yield()}
        model.close();port.base.pending?.resume();port.base.pending=nil;await Task.yield()
        try check(!model.visible && model.entries.isEmpty,"late scan cannot reopen picker")
        model.open(destination:port.base.samsung);await model.finish()
        port.delayMove=true;model.key("z")
        while port.movePending==nil {await Task.yield()}
        model.key("escape");port.movePending?.resume();port.movePending=nil;await Task.yield()
        try check(port.writes==[exact],"cancel before write")
        model.open(destination:port.base.samsung);await model.finish()
        let first=model.rows[0].windows[0].id;port.base.entries.removeAll{$0.id==first}
        model.select(0);await model.finish()
        try check(port.writes==[exact],"closed window cannot substitute sibling")
        port.trusted=false;model.close();model.open(destination:port.base.samsung)
        try check(model.rows.isEmpty && model.visible,"permission state")
        try check(!model.handlesKey("tab") && !model.handlesKey(" ") && !model.handlesKey("return") && model.handlesKey("escape"),"native recovery keys must pass through")
        port.trusted=true;model.close();model.open(destination:port.base.samsung);await model.finish()
        model.topologyChanged();try check(model.rows.isEmpty,"display change invalidates choices")
        model.close()
        print("Bring Here checks passed: exact IDs, initials, numbered choices, reverse, search, cancellation, stale scans, closed windows, permission and topology.")
    }
    static func render(_ args:CLIArguments) async throws {
        guard let path=args.positional(at:0) else{throw TVError("Supply an output folder")}
        let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for dark in [false,true] {
            for state in ["apps","multiple","search","empty","permission","blocked","working","reverse","many"] {
                let port=PickerFixture(),model=BringHereModel(port:port),view=BringHerePanel(model:model)
                view.fixtureAppearance=dark
                if state=="permission" {port.trusted=false}
                if state=="blocked" {port.base.entries[0].retrievalState = .blocked("Exit Split View first")}
                if state=="working" {port.base.entries[0].retrievalState = .fullScreen}
                if state=="many" {
                    for i in 0..<10 {port.base.entries.append(.init(app:"App \(i)",title:"A long sample document title \(i)",owner:0,element:AXUIElementCreateSystemWide(),original:port.base.tv))}
                }
                model.open(destination:state=="reverse" ? port.base.tv:port.base.samsung);await model.finish()
                if state=="multiple" || state=="many" {model.key("a")}
                if state=="search" || state=="empty" {model.key("/");model.search(state=="search" ? "read":"missing sample")}
                if state=="blocked" {model.key("z")}
                if state=="working" {port.delayMove=true;model.key("z");while port.movePending==nil {await Task.yield()}}
                view.draw();view.panel.displayIfNeeded()
                guard let root=view.panel.contentView,let bitmap=root.bitmapImageRepForCachingDisplay(in:root.bounds) else{throw TVError("Capture unavailable")}
                root.cacheDisplay(in:root.bounds,to:bitmap)
                guard let png=bitmap.representation(using:.png,properties:[:]) else{throw TVError("PNG unavailable")}
                try png.write(to:folder.appendingPathComponent(state+(dark ? "-dark":"-light")+".png"))
                view.stop();port.movePending?.resume();port.movePending=nil
            }
        }
        print("Rendered 18 production picker fixture states.")
    }
}
#endif
