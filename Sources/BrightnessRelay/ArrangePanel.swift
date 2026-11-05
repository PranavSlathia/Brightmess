import AppKit
import SwiftUI
import BrightnessCore

private final class ArrangeKeyPanel:NSPanel {override var canBecomeKey:Bool{true}}

struct ArrangeDeskAction:View {
    @ObservedObject var shortcuts:DeskShortcuts
    var perform:()->Void
    var body:some View {
        HStack {
            Button(action:perform){Label("Arrange this screen",systemImage:shortcuts.symbol(.arrange))}
            Spacer()
            if let chord=shortcuts.activeBinding(.arrange){Text(chord.label).font(.caption)}
        }.padding(.horizontal,16).padding(.vertical,8).background(DeckPaint.shelf)
    }
}

final class ArrangeOutlineView:NSView {
    private var icons=[String:NSImage]()
    var plan:ArrangementPlan? {didSet{
        icons=[:]
        for item in plan?.items ?? [] {
            if let value=item.window.id.split(separator:":").first,let pid=Int32(value),let icon=NSRunningApplication(processIdentifier:pid)?.icon {icons[item.window.id]=icon}
        }
        needsDisplay=true
    }}
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        guard let plan else{return}
        for (index,item) in plan.items.enumerated() {
            let rect=item.zone.offsetBy(dx:-plan.display.usable.minX,dy:-plan.display.usable.minY)
            let path=NSBezierPath(roundedRect:rect.insetBy(dx:2,dy:2),xRadius:8,yRadius:8)
            NSColor(calibratedRed:0.77,green:0.93,blue:0.44,alpha:NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0:0.10).setFill();path.fill()
            NSColor.black.withAlphaComponent(0.7).setStroke();path.lineWidth=5;path.stroke()
            NSColor(calibratedRed:0.87,green:0.92,blue:0.73,alpha:1).setStroke();path.lineWidth=2;path.stroke()
            let text="\(index+1)  \(item.window.app)"
            let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:15,weight:.semibold),.foregroundColor:NSColor(calibratedRed:0.96,green:0.98,blue:0.91,alpha:1)]
            let label=NSAttributedString(string:text,attributes:attributes)
            let detail=NSAttributedString(string:item.window.title,attributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor(calibratedRed:0.87,green:0.92,blue:0.83,alpha:1)])
            let labelRect=CGRect(x:rect.minX+12,y:rect.minY+12,width:min(rect.width-24,max(label.size().width+50,min(310,detail.size().width+24))),height:54)
            NSColor(calibratedRed:0.08,green:0.24,blue:0.18,alpha:1).setFill()
            NSBezierPath(roundedRect:labelRect,xRadius:6,yRadius:6).fill()
            let icon=icons[item.window.id] ?? NSImage(systemSymbolName:"macwindow",accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[.white]))
            icon?.draw(in:CGRect(x:labelRect.minX+10,y:labelRect.minY+7,width:20,height:20),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            label.draw(with:CGRect(x:labelRect.minX+37,y:labelRect.minY+8,width:labelRect.width-45,height:20),options:[.usesLineFragmentOrigin,.truncatesLastVisibleLine])
            detail.draw(with:CGRect(x:labelRect.minX+12,y:labelRect.minY+31,width:labelRect.width-24,height:18),options:[.usesLineFragmentOrigin,.truncatesLastVisibleLine])
        }
    }
}

struct ArrangeHUD:View {
    @ObservedObject var model:ArrangeModel
    var close:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.firstTextBaseline) {
                Text("Arrange "+(model.display?.name ?? "this screen")).font(.system(size:19,weight:.bold)).lineLimit(1)
                    .help(model.display?.name ?? "This screen")
                Spacer()
                if model.stage == .preview && model.port.trusted && !model.windows.isEmpty {
                    Picker("Layout",selection:Binding(get:{model.mode},set:{model.choose($0)})) {
                        Text("Smart").tag(ArrangementMode.smart);Text("Equal").tag(ArrangementMode.equal)
                    }.pickerStyle(.segmented).labelsHidden().frame(width:140)
                }
                Button(model.working ? "Stop":"Close",action:close).keyboardShortcut(.cancelAction)
            }
            if model.stage == .loading {
                ProgressView().controlSize(.small).accessibilityLabel("Finding windows")
            } else if model.stage == .preview && model.showWindows {
                    ScrollView {
                        VStack(alignment:.leading,spacing:6) {
                            ForEach(model.windows) { window in
                                Toggle(isOn:Binding(get:{model.selected.contains(window.id)},set:{model.include(window.id,$0)})) {
                                    HStack {
                                        Text(window.app).fontWeight(.semibold).frame(width:95,alignment:.leading)
                                        Text(window.title).lineLimit(1).foregroundStyle(DeckPaint.muted)
                                    }
                                }.toggleStyle(.checkbox).help(window.app+" · "+window.title)
                                .accessibilityLabel("Include \(window.app), \(window.title)")
                            }
                        }.padding(.top,6)
                    }.frame(height:min(120,CGFloat(model.windows.count)*28))
            }
            Text(model.message).font(.system(size:12)).fixedSize(horizontal:false,vertical:true)
                .foregroundStyle(DeckPaint.muted).accessibilityAddTraits(.updatesFrequently)
            if model.stage == .preview && model.showWindows {
                Text("Excluded windows stay in place and may be covered. Full-screen windows are not included.")
                    .font(.system(size:11)).foregroundStyle(DeckPaint.muted).fixedSize(horizontal:false,vertical:true)
            }
            HStack {
                if !model.port.trusted {
                    Button("Open Accessibility") {
                        if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"){NSWorkspace.shared.open(url)}
                    }
                    Spacer()
                    Button("Refresh"){model.refresh()}.disabled(model.working)
                } else {
                    if model.stage == .preview && !model.windows.isEmpty {
                        Button("Windows (\(model.selected.count)/\(model.windows.count))"){model.toggleWindows()}
                            .help("Include or exclude individual windows")
                    }
                    Button("Undo"){model.undo()}.disabled(!model.canUndo).keyboardShortcut("z",modifiers:.command)
                    Spacer()
                    Button(model.stage == .result ? "New preview":"Refresh"){model.refresh()}.disabled(model.working)
                    if model.stage == .result {
                        Button("Done",action:close).keyboardShortcut(.defaultAction)
                    } else {
                        Button("Apply arrangement"){model.apply()}.keyboardShortcut(.defaultAction)
                            .buttonStyle(.borderedProminent)
                            .disabled(model.plan == nil || model.working || model.stage != .preview)
                    }
                }
            }
        }.padding(18).frame(width:540).foregroundStyle(DeckPaint.ink).background(DeckPaint.ground)
            .tint(DeckPaint.accent).clipShape(RoundedRectangle(cornerRadius:12))
    }
}

@MainActor final class ArrangePanelController:NSObject {
    let model:ArrangeModel
    private let outline=NSPanel(contentRect:.zero,styleMask:.borderless,backing:.buffered,defer:false)
    private let outlines=ArrangeOutlineView()
    private let panel=ArrangeKeyPanel(contentRect:CGRect(x:0,y:0,width:540,height:300),styleMask:.borderless,backing:.buffered,defer:false)
    private var observer:NSObjectProtocol?
    init(model:ArrangeModel?=nil){
        self.model=model ?? ArrangeModel();super.init()
        outline.isOpaque=false;outline.backgroundColor = .clear;outline.ignoresMouseEvents=true;outline.hasShadow=false
        outline.level = .floating;outline.collectionBehavior=[.moveToActiveSpace,.fullScreenAuxiliary]
        outline.contentView=outlines;outline.isReleasedWhenClosed=false
        panel.title="BRIGHTMESS · Arrange here";panel.titleVisibility = .hidden;panel.titlebarAppearsTransparent=true
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.isMovableByWindowBackground=true
        panel.isReleasedWhenClosed=false;panel.level = .floating;panel.collectionBehavior=[.moveToActiveSpace,.fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden=true;panel.standardWindowButton(.miniaturizeButton)?.isHidden=true;panel.standardWindowButton(.zoomButton)?.isHidden=true
        panel.contentView=NSHostingView(rootView:ArrangeHUD(model:self.model,close:{[weak self] in self?.model.close()}))
        self.model.changed={[weak self] in self?.update()}
        observer=NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main){[weak self] _ in MainActor.assumeIsolated{self?.model.topologyChanged()}}
    }
    func toggle(){
        if model.stage != .closed {model.close();return}
        guard let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}),let display=ArrangeNativePort.display(for:screen) else{return}
        model.open(display)
        panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    private func update(){
        guard model.stage != .closed,let display=model.display else{outline.orderOut(nil);panel.orderOut(nil);return}
        guard let screen=NSScreen.screens.first(where:{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value==display.id}) else{outline.orderOut(nil);return}
        if model.stage == .preview,let plan=model.plan {
            outline.setFrame(screen.visibleFrame,display:true);outlines.frame=CGRect(origin:.zero,size:screen.visibleFrame.size);outlines.plan=plan;outline.orderFrontRegardless()
        } else {outline.orderOut(nil)}
        let f=screen.visibleFrame,height:CGFloat=model.stage == .preview && model.showWindows ? 320:170
        panel.setContentSize(CGSize(width:min(540,f.width-32),height:min(height,f.height-60)))
        panel.setFrameOrigin(CGPoint(x:f.midX-panel.frame.width/2,y:f.minY+24));panel.orderFrontRegardless()
    }
    func stop(){model.close();outline.orderOut(nil);panel.orderOut(nil);if let observer{NotificationCenter.default.removeObserver(observer)};observer=nil}
}
