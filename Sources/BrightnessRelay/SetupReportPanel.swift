import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BrightnessCore

@MainActor final class SetupReportModel:ObservableObject {
    @Published var report:SetupReport?
    @Published var exporting=false
    private(set) var exportReport:SetupReport?
    @Published var error:String?
    var refresh:(()->Void)?
    var recover:((SetupReport.Recovery)->Void)?
    func beginExport() {exportReport=report;error=nil;exporting=true}
    func save() {
        guard let report=exportReport else{return}
        let dialog=NSSavePanel();dialog.allowedContentTypes=[.json];dialog.nameFieldStringValue="BRIGHTMESS-diagnostics.json"
        guard dialog.runModal() == .OK,let url=dialog.url else{return}
        do {try report.json().write(to:url,options:.atomic);exporting=false}
        catch {self.error="Could not save the report. Choose another location and try again."}
    }
}
@MainActor final class SetupReportPanel {
    let model=SetupReportModel()
    private var window:NSWindow?
    func open() {
        if window == nil {
            let w=NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:620),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            w.title="BRIGHTMESS · Check my setup";w.isReleasedWhenClosed=false;w.minSize=NSSize(width:480,height:360)
            w.contentView=NSHostingView(rootView:SetupReportView(model:model));w.center();window=w
        }
        model.refresh?();window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
}
struct SetupReportView:View {
    @ObservedObject var model:SetupReportModel
    private func actionName(_ action:SetupReport.Recovery)->String {
        switch action {
        case .accessibility:return "Open Accessibility settings"
        case .sync:return "Sync now"
        case .tvSetup:return "Open TV setup"
        case .tvReconnect:return "Reconnect TV"
        case .inputs:return "Configure TV inputs"
        case .displays:return "Open display controls"
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("Check my setup").font(.title2.bold());Spacer();Button("Refresh"){model.refresh?()}}
            Text("A snapshot, not a background scan. Refresh to update reading ages.").font(.callout).foregroundStyle(DeckPaint.muted)
            if let report=model.report {
                if let next=report.suggested,let action=next.recovery {
                    HStack(alignment:.top) {
                        Image(systemName:"exclamationmark.circle")
                        VStack(alignment:.leading) {Text("Next step: "+next.title).fontWeight(.semibold);Text(next.detail).font(.callout)
                            Button(actionName(action)){model.recover?(action)}
                        }
                    }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
                }
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        ForEach(["Air","TV connection","TV inputs","Permissions","Displays"],id:\.self) {group in
                            VStack(alignment:.leading,spacing:9) {
                                Text(group).font(.headline)
                                ForEach(report.checks.filter{$0.group==group}) {check in
                                    HStack(alignment:.top,spacing:10) {
                                        Image(systemName:check.state == .ready ? "checkmark.circle":check.state == .attention ? "exclamationmark.circle":"questionmark.circle")
                                            .accessibilityLabel(check.state == .notVerified ? "Not verified":check.state.rawValue)
                                        VStack(alignment:.leading,spacing:3) {
                                            Text(check.title).fontWeight(.medium);Text(check.detail).font(.callout).foregroundStyle(DeckPaint.muted).textSelection(.enabled)
                                            if let action=check.recovery,check.state != .ready {Button(actionName(action)){model.recover?(action)}.controlSize(.small)}
                                        };Spacer(minLength:0)
                                    }
                                }
                            };Divider()
                        }
                    }
                }
                HStack {Text("BRIGHTMESS \(report.appVersion) · build \(report.build)").font(.caption).foregroundStyle(DeckPaint.muted);Spacer();Button("Export diagnostics…"){model.beginExport()}}
            } else {ProgressView("Reading current state…").frame(maxWidth:.infinity,maxHeight:.infinity)}
        }.padding(20).foregroundStyle(DeckPaint.ink).buttonStyle(SolarUtilityButtonStyle())
        .sheet(isPresented:$model.exporting) {
            VStack(alignment:.leading,spacing:12) {
                Text("Review diagnostics").font(.title2.bold())
                Text("Only the fields below will be saved. No pairing secrets, window titles, network addresses or personal paths. Nothing is uploaded.")
                ScrollView {Text(model.exportReport.flatMap{try? String(decoding:$0.json(),as:UTF8.self)} ?? "").font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
                if let error=model.error {Text(error).foregroundStyle(.red)}
                HStack {Button("Cancel"){model.exporting=false};Spacer();Button("Save report…"){model.save()}.keyboardShortcut(.defaultAction)}
            }.padding(20).frame(width:530,height:510)
        }
    }
}
