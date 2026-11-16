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
    @FocusState private var applyFocused:Bool
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
                    HStack {
                        Text("Include windows").font(.caption)
                        Spacer()
                        Button("All"){model.selectAll(true)}.accessibilityLabel("Select all windows")
                        Button("None"){model.selectAll(false)}.accessibilityLabel("Deselect all windows")
                    }.controlSize(.small)
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
                            .focused($applyFocused).accessibilityIdentifier("arrange.apply")
                            .disabled(!model.canApply)
                    }
                }
            }
            Text(model.waitingForShortcutRelease ? "Release shortcut keys, then press Enter to apply." :
                 model.stage == .result ? "Enter Done · ⌘Z Undo · Esc Close" :
                 model.working ? "Esc Stop" : model.canApply ? "Enter Apply · S Smart · E Equal · W Windows · Esc Close" :
                 model.stage == .loading ? "Finding windows… · Esc Close" : model.windows.isEmpty ? "Tab Options · Space Activate · Esc Close":"S Smart · E Equal · W Windows · Esc Close")
                .font(.system(size:11)).foregroundStyle(DeckPaint.muted)
                .fixedSize(horizontal:false,vertical:true)
        }.padding(18).frame(width:540).foregroundStyle(DeckPaint.ink).background(DeckPaint.ground)
            .tint(DeckPaint.accent).clipShape(RoundedRectangle(cornerRadius:12))
            .onChange(of:model.stage){_,stage in if stage == .preview && model.canApply {applyFocused=true}}
            .onAppear{if model.canApply {applyFocused=true}}
    }
}

@MainActor final class ArrangePanelController:NSObject,NSWindowDelegate {
    let model:ArrangeModel
    private let outline=NSPanel(contentRect:.zero,styleMask:.borderless,backing:.buffered,defer:false)
    private let outlines=ArrangeOutlineView()
    private let panel=ArrangeKeyPanel(contentRect:CGRect(x:0,y:0,width:540,height:300),styleMask:.borderless,backing:.buffered,defer:false)
    private var observer:NSObjectProtocol?
    private var focusObserver:NSObjectProtocol?,keyMonitor:Any?
    private var previous:NSRunningApplication?,lastExternal:NSRunningApplication?
    private var keys=ArrangeKeyRouter(),applyKeyDown=false,pendingSuccess=false
    init(model:ArrangeModel?=nil){
        self.model=model ?? ArrangeModel();super.init()
        outline.isOpaque=false;outline.backgroundColor = .clear;outline.ignoresMouseEvents=true;outline.hasShadow=false
        outline.level = .floating;outline.collectionBehavior=[.moveToActiveSpace,.fullScreenAuxiliary]
        outline.contentView=outlines;outline.isReleasedWhenClosed=false
        panel.title="BRIGHTMESS · Arrange here";panel.titleVisibility = .hidden;panel.titlebarAppearsTransparent=true
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.isMovableByWindowBackground=true
        panel.isReleasedWhenClosed=false;panel.level = .floating;panel.collectionBehavior=[.moveToActiveSpace,.fullScreenAuxiliary];panel.delegate=self
        panel.standardWindowButton(.closeButton)?.isHidden=true;panel.standardWindowButton(.miniaturizeButton)?.isHidden=true;panel.standardWindowButton(.zoomButton)?.isHidden=true
        panel.contentView=NSHostingView(rootView:ArrangeHUD(model:self.model,close:{[weak self] in self?.dismiss(restoring:true)}))
        self.model.changed={[weak self] in self?.update()}
        self.model.appliedSuccessfully={[weak self] in self?.pendingSuccess=true;self?.finishSuccess()}
        let front=NSWorkspace.shared.frontmostApplication
        lastExternal=front?.processIdentifier == getpid() ? nil:front
        focusObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main){[weak self] note in
            guard let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != getpid(),app.activationPolicy == .regular else{return}
            MainActor.assumeIsolated{self?.lastExternal=app}
        }
        observer=NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main){[weak self] _ in MainActor.assumeIsolated{self?.model.topologyChanged()}}
    }
    func toggle(){
        if model.stage != .closed {dismiss(restoring:true);return}
        guard let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}),let display=ArrangeNativePort.display(for:screen) else{return}
        prepareOpening()
        model.open(display)
        panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func open(destination:UInt32) throws {
        guard !model.working else{throw TVError("An arrangement is still finishing.")}
        guard let screen=NSScreen.screens.first(where:{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value==destination}),let display=ArrangeNativePort.display(for:screen) else{throw TVError("Destination disconnected. No windows moved.")}
        prepareOpening();model.open(display);panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    private func prepareOpening() {
        let front=NSWorkspace.shared.frontmostApplication
        previous=front?.processIdentifier==getpid() ? lastExternal:front
        applyKeyDown=false;pendingSuccess=false
        keys.opened(modifiers:Self.modifiers(NSEvent.modifierFlags));model.waitingForShortcutRelease = !keys.armed
        if let keyMonitor{NSEvent.removeMonitor(keyMonitor)}
        keyMonitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp,.flagsChanged]){[weak self] event in
            guard let self else{return event};return self.handle(event)
        }
    }
    private static func modifiers(_ flags:NSEvent.ModifierFlags)->ArrangeKeyRouter.Modifiers {
        var result=ArrangeKeyRouter.Modifiers()
        for (flag,value) in [(NSEvent.ModifierFlags.command,ArrangeKeyRouter.Modifiers.command),(.control,.control),(.option,.option),(.shift,.shift)] {
            if flags.contains(flag){result.insert(value)}
        };return result
    }
    private func handle(_ event:NSEvent)->NSEvent? {
        if event.type == .flagsChanged {
            keys.flagsChanged(Self.modifiers(event.modifierFlags));publishArming();return event
        }
        let enter=event.keyCode==36 || event.keyCode==76
        if event.type == .keyUp {
            if enter && applyKeyDown {applyKeyDown=false;finishSuccess();return nil};return event
        }
        let names:[UInt16:String]=[36:"return",76:"enter",53:"escape"]
        let key=names[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased() ?? ""
        let phase:ArrangeKeyRouter.Phase
        switch model.stage {case .closed:phase = .closed;case .loading:phase = .loading;case .preview:phase = .preview;case .applying:phase = .applying;case .result:phase = .result}
        let action=keys.route(key:key,modifiers:Self.modifiers(event.modifierFlags),repeating:event.isARepeat,
            isKeyWindow:panel.isKeyWindow,phase:phase,canApply:model.canApply,canUndo:model.canUndo,
            hasWindows:!model.windows.isEmpty,editingText:(panel.firstResponder as? NSTextView)?.isEditable == true)
        publishArming()
        switch action {
        case .pass:return event
        case .consume:break
        case .apply:applyKeyDown=enter;model.apply()
        case .close:dismiss(restoring:true)
        case .smart:model.choose(.smart)
        case .equal:model.choose(.equal)
        case .windows:model.toggleWindows()
        case .undo:model.undo()
        }
        return nil
    }
    private func publishArming(){if model.waitingForShortcutRelease != !keys.armed {model.waitingForShortcutRelease = !keys.armed}}
    private func finishSuccess() {
        guard pendingSuccess,model.stage == .result,(!applyKeyDown || !panel.isKeyWindow) else{return}
        pendingSuccess=false
        NSAccessibility.post(element:NSApp as Any,notification:.announcementRequested,
            userInfo:[.announcement:model.message,.priority:NSAccessibilityPriorityLevel.medium.rawValue])
        dismiss(restoring:true)
    }
    private func dismiss(restoring:Bool) {
        let app=previous
        model.close()
        if model.stage == .closed,restoring,NSWorkspace.shared.frontmostApplication?.processIdentifier==getpid(),let app,!app.isTerminated {
            app.activate(options:[])
        }
    }
    func windowDidResignKey(_ notification:Notification){applyKeyDown=false;finishSuccess()}
    private func update(){
        guard model.stage != .closed,let display=model.display else{
            pendingSuccess=false;applyKeyDown=false;outline.orderOut(nil);panel.orderOut(nil)
            if let keyMonitor{NSEvent.removeMonitor(keyMonitor)};keyMonitor=nil;previous=nil;return
        }
        guard let screen=NSScreen.screens.first(where:{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value==display.id}) else{outline.orderOut(nil);return}
        if model.stage == .preview,let plan=model.plan {
            outline.setFrame(screen.visibleFrame,display:true);outlines.frame=CGRect(origin:.zero,size:screen.visibleFrame.size);outlines.plan=plan;outline.orderFrontRegardless()
        } else {outline.orderOut(nil)}
        let f=screen.visibleFrame,height:CGFloat=model.stage == .preview && model.showWindows ? 350:200
        panel.setContentSize(CGSize(width:min(540,f.width-32),height:min(height,f.height-60)))
        panel.setFrameOrigin(CGPoint(x:f.midX-panel.frame.width/2,y:f.minY+24));panel.orderFrontRegardless()
    }
    func stop(){
        model.close();model.changed=nil;model.appliedSuccessfully=nil;outline.orderOut(nil);panel.orderOut(nil)
        if let keyMonitor{NSEvent.removeMonitor(keyMonitor)};keyMonitor=nil
        if let observer{NotificationCenter.default.removeObserver(observer)};observer=nil
        if let focusObserver{NSWorkspace.shared.notificationCenter.removeObserver(focusObserver)};focusObserver=nil
    }
}
