#if DEBUG
import AppKit
import ApplicationServices
import BrightnessCore

/// The actual menu model and placement routing with two fake screens; no AX reads,
/// TCC prompts, TV commands, window activations or display writes.
@MainActor final class FixtureWindowDesk: WindowDeskPort {
    let samsung: UInt32 = 51000, tv: UInt32 = 51001
    var trusted = true
    var screens = [ShelfScreen(id:51000,name:"Samsung",frame:CGRect(x:0,y:0,width:1692,height:3008),usable:CGRect(x:0,y:26,width:1692,height:2982)),
                   ShelfScreen(id:51001,name:"Beyond TV",frame:CGRect(x:-1920,y:0,width:1920,height:1080),usable:CGRect(x:-1920,y:26,width:1920,height:1054))]
    var entries = [DeskWindow]()
    var writes = [UUID]()
    var delay = false
    var pending: CheckedContinuation<Void,Never>?
    init() {
        for (app,title,screen) in [("Safari","Reading list",tv),("Safari","Project notes",tv),("Preview","Contact sheet",tv),
                                   ("TextEdit","Draft",samsung),("Safari","Recipes",samsung)] {
            entries.append(DeskWindow(app:app,title:title,owner:0,element:AXUIElementCreateSystemWide(),original:screen))
        }
    }
    func current(previous: NSRunningApplication?) -> DeskWindow? { entries.first { $0.title == "Draft" } }
    func inventory(excluding destination: UInt32, screens: [ShelfScreen]) async -> [DeskWindow] {
        let result=entries.filter { $0.original != destination && screens.map(\.id).contains($0.original) }
        if delay { delay=false; await withCheckedContinuation { pending=$0 } }; return result
    }
    func move(_ window: DeskWindow, to dest: UInt32) throws {
        guard trusted, screens.contains(where:{$0.id==dest}),let i=entries.firstIndex(where:{$0.id==window.id}),
              entries[i].original == window.original, window.original != dest else { throw TVError("Window or destination changed.") }
        writes.append(window.id);entries[i].original=dest
    }
    func icon(for window: DeskWindow) -> NSImage? {
        let ids=["Safari":"com.apple.Safari","Preview":"com.apple.Preview","TextEdit":"com.apple.TextEdit"]
        return ids[window.app].flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier:$0) }
            .map { NSWorkspace.shared.icon(forFile:$0.path) }
    }
}

@MainActor enum DeskShelfChecks {
    static func run() async throws {
        func check(_ b:Bool,_ m:String)throws{if !b{throw TVError("Shelf check: "+m)}}
        let port=FixtureWindowDesk(), shelf=DeskWindows(port:port)
        func open(_ id:UInt32) async { shelf.capture(destination:id); await shelf.finishScan() }
        await open(port.samsung)
        try check(Set(shelf.choices.map(\.title)) == ["Reading list","Project notes","Contact sheet"],"open must expose every remote window even with local focus")
        guard let chosen=shelf.choices.first(where:{$0.title=="Reading list"}) else{throw TVError("Missing Safari fixture")}
        shelf.bring(chosen); await shelf.finishScan()
        try check(port.writes==[chosen.id] && shelf.choices.count==2,"exact window and sibling")
        await open(port.tv)
        try check(Set(shelf.choices.map(\.title)) == ["Draft","Recipes","Reading list"],"reverse open")
        shelf.bring(chosen)
        try check(port.writes.count==1,"stale action from previous destination")
        guard let returning=shelf.choices.first(where:{$0.id==chosen.id}) else{throw TVError("Missing return tile")}
        shelf.bring(returning);await shelf.finishScan()
        try check(port.writes==[chosen.id,chosen.id],"round trip")
        port.delay=true; shelf.capture(destination:port.tv)
        let deadline=ContinuousClock.now + .seconds(3)
        while port.pending==nil { if ContinuousClock.now>=deadline {throw TVError("Fixture scan did not begin")};await Task.yield() }
        await open(port.samsung);port.pending?.resume();port.pending=nil
        await Task.yield()
        try check(shelf.destinationName=="Samsung" && shelf.choices.allSatisfy{$0.original==port.tv},"late inventory")
        guard let vanished=shelf.choices.first else{throw TVError("Missing closed-window fixture")};port.entries.removeAll{$0.id==vanished.id}
        shelf.bring(vanished);await shelf.finishScan()
        try check(port.writes.count==2 && !shelf.choices.contains(where:{$0.id==vanished.id}),"closed window")
        port.trusted=false;await open(port.samsung);try check(!shelf.trusted && shelf.choices.isEmpty,"permission denied")
        port.trusted=true;port.screens.removeAll{$0.id==port.tv};await open(port.tv)
        try check(shelf.choices.isEmpty && shelf.hint.contains("connected"),"missing destination")
        shelf.close();try check(shelf.choices.isEmpty && shelf.focus==nil,"close clears private window data")
        print("Source Deck shelf checks passed: both destinations, sibling windows, stale scans/clicks, permission and disconnection.")
    }
}
#endif
