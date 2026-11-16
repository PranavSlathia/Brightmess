#if DEBUG
import AppKit
import SwiftUI
import AppIntents
import BrightnessCore

@MainActor enum WorkflowChecks {
    static func run() async throws {
        func check(_ value:Bool,_ message:String)throws{if !value{throw TVError("Workflow check: "+message)}}
        let coordinator=DeskIntentCoordinator.shared
        let oldOpen=coordinator.open,oldSource=coordinator.selectSource,oldDisplay=coordinator.pointerDisplay
        defer {coordinator.open=oldOpen;coordinator.selectSource=oldSource;coordinator.pointerDisplay=oldDisplay}
        var opens=[Bool](),sent=[DeskAction]()
        coordinator.pointerDisplay={42}
        coordinator.open={id,arrange in try check(id==42,"destination changed");opens.append(arrange)}
        coordinator.selectSource={sent.append($0)}
        let bring=try await OpenBringHereIntent().perform()
        let arrange=try await PreviewArrangementIntent().perform()
        let tv=SelectTVSourceIntent();tv.source = .macMini;let command=try await tv.perform()
        try check(bring.value=="Picker opened" && arrange.value=="Preview opened" && command.value=="Command sent","non-dialog action results")
        try check(opens==[false,true] && sent==[.mac],"action routing")
        coordinator.pointerDisplay={nil}
        var rejected=false
        do {_ = try await OpenBringHereIntent().perform()} catch {rejected=true}
        try check(rejected && opens.count==2,"missing display performed action")
        coordinator.pointerDisplay={42};coordinator.open={_,_ in throw TVError("Accessibility denied")}
        rejected=false
        do {_ = try await PreviewArrangementIntent().perform()} catch {rejected=true}
        try check(rejected && opens.count==2,"denied access performed action")
        let remote=TVRemote(fixture:true)
        rejected=false
        do {try await remote.activateFromShortcut(.ps5)} catch {rejected=true}
        try check(rejected && remote.messagesSent==0,"offline command sent or queued")
        print("Workflow checks passed: three intent routes, captured display, unavailable display, denied access and offline TV no-send.")
    }
    static func render(_ folder:URL) throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for dark in [false,true] {
            for ready in [false,true] {
                let model=SetupReportModel()
                model.report=SetupReport.make(["appVersion":"0.14.0","build":"31","sourceState":ready ? "Live":"No recent Air reading","airReadingAgeSeconds":ready ? 2.0:190.0,"tvPaired":true,"tvRemoteReady":ready,"windowAccessibility":ready,"ps5Port":2,"macPort":1,"displays":[["connected":true,"method":"hardwareDDC","readingKind":"liveHardware","hardwareReadingAgeSeconds":5.0],["connected":true,"method":"softwareDimming","readingKind":"liveSoftware"]]])
                let view=NSHostingView(rootView:SetupReportView(model:model)
                    .buttonStyle(.borderless)
                    .environment(\.colorScheme,dark ? .dark:.light)
                    .environment(\.controlActiveState,.key)
                    .frame(width:580,height:620)
                    .background(dark ? Color(nsColor:.darkGray):Color(nsColor:.windowBackgroundColor)))
                view.appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
                let window=NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:620),styleMask:[.borderless],backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.appearance=view.appearance;window.contentView=view
                view.frame=NSRect(x:0,y:0,width:580,height:620);view.layoutSubtreeIfNeeded()
                window.displayIfNeeded();RunLoop.main.run(until:Date().addingTimeInterval(0.2));view.layoutSubtreeIfNeeded()
                guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{throw TVError("Fixture bitmap unavailable")}
                view.cacheDisplay(in:view.bounds,to:bitmap)
                guard let png=bitmap.representation(using:.png,properties:[:]) else{throw TVError("Fixture PNG unavailable")}
                try png.write(to:folder.appendingPathComponent("setup-\(ready ? "ready":"attention")-\(dark ? "dark":"light").png"))
                window.close()
            }
        }
    }
}
#endif
