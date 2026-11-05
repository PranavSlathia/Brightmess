#if DEBUG
import AppKit
import ApplicationServices
import BrightnessCore

@MainActor enum WindowGeometryChecks {
    static func moveFixture(to expectedScreen:String) async throws {
        // Deliberately refuses all user apps, including Terminal.
        let fixtures=NSWorkspace.shared.runningApplications.filter{$0.bundleIdentifier=="dev.pranav.Brightmess.WindowMoveFixture" && !$0.isTerminated}
        guard fixtures.count==1,let app=fixtures.first else{throw TVError("Expected one running disposable fixture app")}
        let port=MacWindowDesk(),screens=port.screens
        guard let destination=screens.first(where:{$0.name==expectedScreen}) else{throw TVError("Fixture destination missing")}
        let entries=await port.fixtureInventory(owner:app.processIdentifier,excluding:destination.id,screens:screens)
        guard entries.count==1,let window=entries.first else{throw TVError("Expected exactly one eligible disposable fixture window")}
        print("Fixture before: id=\(window.nativeWindowID ?? 0), state=\(window.retrievalState), frame=\(String(describing:AXDesk.frame(window.element)))")
        do {
            try await port.retrieve(window,to:destination.id){print("Fixture progress: \($0)")}
        } catch {
            print("Fixture after error: expected id=\(window.nativeWindowID ?? 0), current id=\(WindowServerGeometry.id(window.element) ?? 0), raw AX=\(String(describing:AXDesk.accessibilityFrame(window.element))), frame=\(String(describing:AXDesk.frame(window.element)))")
            throw error
        }
        print("Fixture move verified to \(expectedScreen).")
    }
    static func run() throws {
        let samsung=ShelfScreen(id:1,name:"Samsung",frame:CGRect(x:0,y:0,width:1440,height:2560),usable:CGRect(x:0,y:0,width:1440,height:2560))
        let tv=ShelfScreen(id:2,name:"TV",frame:CGRect(x:-1920,y:722,width:1920,height:1080),usable:CGRect(x:-1920,y:722,width:1920,height:1080))
        let stale=CGRect(x:0,y:0,width:1440,height:2539),actual=CGRect(x:-1920,y:722,width:1440,height:2539)
        let records:[WindowGeometry.Record]=[.init(id:4392,owner:42,frame:actual),.init(id:5000,owner:42,frame:stale)]
        guard let corrected=WindowGeometry.resolve(accessibility:stale,windowID:4392,owner:42,records:records),
              AXDesk.screen(corrected,in:[samsung,tv])?.id==tv.id,
              WindowGeometry.resolve(accessibility:stale,windowID:4392,owner:99,records:records)==nil,
              WindowGeometry.resolve(accessibility:stale,windowID:1,owner:42,records:records)==nil else {
            throw TVError("Window geometry check: stale AX position substituted Samsung or a sibling window")
        }
        print("Window geometry checks passed: exact identity, stale AX origin, TV assignment, sibling and owner mismatch refusal.")
    }
    static func live(appName:String,expectedScreen:String) async throws {
        guard AXIsProcessTrusted(),let app=NSWorkspace.shared.runningApplications.first(where:{$0.localizedName==appName}) else {
            throw TVError("Read-only geometry audit needs Accessibility and the named running app.")
        }
        let port=MacWindowDesk(),screens=port.screens
        guard let expected=screens.first(where:{$0.name==expectedScreen}) else{throw TVError("Expected display unavailable")}
        let ax=AXUIElementCreateApplication(app.processIdentifier),records=WindowServerGeometry.records()
        AXUIElementSetMessagingTimeout(ax,0.5)
        var matched=0
        for el in AXDesk.value(ax,kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            guard let entry=AXDesk.entry(el,pid:app.processIdentifier,name:appName,screens:screens,readTitle:false,retrieval:true,records:records) else{continue}
            print("\(appName) window ID \(entry.nativeWindowID ?? 0): AX \(String(describing:AXDesk.accessibilityFrame(el))), resolved \(String(describing:AXDesk.frame(el,records:records))), display \(entry.original)")
            if entry.original==expected.id {matched+=1}
        }
        guard matched>0 else{throw TVError("No eligible \(appName) window resolved to \(expectedScreen)")}
        let fromExpected=await port.retrievalInventory(excluding:expected.id,screens:screens)
        for other in screens where other.id != expected.id {
            let fromOther=await port.retrievalInventory(excluding:other.id,screens:screens)
            guard fromOther.contains(where:{$0.owner==app.processIdentifier && $0.original==expected.id}),
                  !fromExpected.contains(where:{$0.owner==app.processIdentifier && $0.original==expected.id}) else {
                throw TVError("Picker direction did not match the resolved window's display")
            }
        }
        print("Native geometry audit passed: \(appName) belongs to \(expectedScreen), included from the opposite display and excluded from its own. No windows moved.")
    }
}
#endif
