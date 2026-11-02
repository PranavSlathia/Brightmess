import AppKit
import BrightnessCore
import BrightnessHardware
import SwiftUI

enum DeskLayout {
    static let width: CGFloat = 450
    static func height(for available: CGFloat?) -> CGFloat {
        min(595, max(320, (available ?? 700) - 52))
    }
}

struct BrightnessPopoverView: View {
    @ObservedObject var model: BrightnessMenuModel
    var height: CGFloat = DeskLayout.height(for: nil)

    private var displays:[ManagedDisplayState] {
        model.displays.sorted {
            let l=$0.display.desktopX ?? .greatestFiniteMagnitude,r=$1.display.desktopX ?? .greatestFiniteMagnitude
            return l==r ? $0.id<$1.id:l<r
        }
    }
    var body: some View {
        VStack(spacing:0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:0) {
                        SourceDeckTV(remote:model.tv,shortcuts:model.shortcuts,displays:displays)
                        DeskWindowsView(windows:model.windows,shortcuts:model.shortcuts,requestAccess:model.requestKeyboardAccess)
                        levels
                        if let id=model.detailedDisplay,let state=displays.first(where:{$0.id==id}){
                            DeskScreenStrip(model:model,state:state,detailsOnly:true).id("detail-"+id)
                        }
                        if model.actionsOpen {DeskShortcutEditor(shortcuts:model.shortcuts).id("desk.shortcuts")}
                        if model.toolsOpen {tools.id("desk.tools")}
                    }
                }
                .onChange(of:model.toolsOpen){_,open in if open{proxy.scrollTo("desk.tools",anchor:.bottom)}}
                .onChange(of:model.actionsOpen){_,open in
                    if open {proxy.scrollTo("desk.shortcuts",anchor:.bottom)} else {model.shortcuts.cancelRecording()}
                }
                .onChange(of:model.detailedDisplay){_,id in if let id{proxy.scrollTo("detail-"+id,anchor:.top)}}
                .onAppear {
                    if model.actionsOpen {DispatchQueue.main.async {proxy.scrollTo("desk.shortcuts",anchor:.bottom)}}
                }
            }
            footer
        }.frame(width:DeskLayout.width,height:height).background(DeckPaint.ground)
        .foregroundStyle(DeckPaint.ink).tint(DeckPaint.accent)
    }
    private var header: some View {
        HStack(spacing:7) {
            Image(nsImage:DeskMark.image(.linked)).renderingMode(.original).accessibilityHidden(true)
            Text("BRIGHTMESS").font(.system(size:12,weight:.bold)).tracking(0.7)
            Spacer(minLength:2)
            Text(model.deskStatus=="Live" ? "Air live":model.deskStatus)
                .lineLimit(1).font(.system(size:11,weight:.medium))
                .help(model.sourceTitle+" · "+model.sourceAge)
            Button {model.requestAirSync()} label:{
                Label(model.isSyncing ? "Syncing" : model.justSynced ? "Synced":"Sync now",systemImage:"arrow.clockwise")
            }.buttonStyle(.plain).font(.system(size:11,weight:.semibold)).disabled(model.isSyncing)
        }.padding(.horizontal,16).frame(height:36)
        .foregroundStyle(DeckPaint.cream).background(DeckPaint.forest)
        .overlay(alignment:.bottom){Rectangle().fill(DeckPaint.cream.opacity(0.2)).frame(height:1)}
    }
    private var levels:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{
                Text("Display levels").font(.system(size:15,weight:.bold));Spacer()
                Text("\(displays.filter{$0.connectionState.isConnected}.count) connected").font(.caption).foregroundStyle(DeckPaint.muted)
            }
            if let notice=model.syncNotice{Label(notice,systemImage:"info.circle").font(.caption)}
            if displays.isEmpty {
                ContentUnavailableView("No external displays",systemImage:"display",description:Text("Connect a display or choose Re-detect in Desk details."))
            } else {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:12) {
                    ForEach(displays){state in DeskScreenStrip(model:model,state:state)}
                }
            }
        }.padding(.horizontal,16).padding(.vertical,12).frame(maxWidth:.infinity,minHeight:195,alignment:.topLeading)
        .overlay(alignment:.top){Divider()}
    }
    private var footer: some View {
        HStack {
            Button { model.actionsOpen.toggle() } label: {
                Label("Shortcuts & icons",systemImage:"keyboard")
            }.accessibilityValue(model.actionsOpen ? "Expanded" : "Collapsed")
            Spacer()
            Button { model.toolsOpen.toggle() } label: {
                Label(model.toolsOpen ? "Close desk details" : "Desk details", systemImage: "slider.horizontal.3")
            }
            .accessibilityValue(model.toolsOpen ? "Expanded" : "Collapsed")
            Spacer()
            if model.keyboardStatus.needsPermission {
                Button("Enable keyboard", systemImage: "keyboard", action: model.requestKeyboardAccess)
            }
            if model.displays.contains(where: { !$0.connectionState.isConnected }) {
                Button("Reconnect all", systemImage: "display.2", action: model.wakeAll)
                    .disabled(!model.canReconnect)
                    .help(model.canReconnect ? "Reconnect all recorded screens" : "Reconnection is unavailable or already in progress")
            } else {
                Text(model.displays.isEmpty ? "No screens" : "Displays connected")
                    .foregroundStyle(DeckPaint.muted).font(.caption)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.borderless)
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(DeckPaint.ground)
        .overlay(alignment: .top) { Divider() }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Source details").font(.headline)
            Text(model.sourceTitle + " · " + model.sourceAge)
            Text(model.ambientDetail)
            Text(model.receiverStatus)
            Text(model.keyboardStatus.title)
            if model.receiverStatus.hasPrefix("Receiver failed") { Text("Open the log to inspect the receiver.").foregroundStyle(.orange) }
            HStack {
                Button("Re-detect", systemImage: "arrow.triangle.2.circlepath", action: model.redetectHardware)
                Button("Open log", systemImage: "doc.text.magnifyingglass", action: model.openLog)
            }
            .buttonStyle(.bordered)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DeckPaint.ground, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct SourceDeckTV: View {
    @ObservedObject var remote:TVRemote
    @ObservedObject var shortcuts:DeskShortcuts
    let displays:[ManagedDisplayState]
    var body:some View {
        if let paired=remote.paired {
            TVStrip(remote:remote,shortcuts:shortcuts,display:paired.display)
        } else if let candidate=displays.first(where:{$0.display.shape == .television}) {
            TVStrip(remote:remote,shortcuts:shortcuts,display:candidate.id)
        } else {
            Text("No paired TV").font(.headline).padding().frame(maxWidth:.infinity,alignment:.leading)
                .foregroundStyle(DeckPaint.cream).background(DeckPaint.forest)
        }
    }
}

private struct DeskScreenStrip: View {
    @ObservedObject var model: BrightnessMenuModel
    let state: ManagedDisplayState
    var detailsOnly=false
    private var connected: Bool { state.connectionState.isConnected }
    private var expanded: Bool { model.detailedDisplay == state.id }
    private var title: String {
        state.display.vendorID == 0x4c2d && state.display.name == "LU28R55" ? "Samsung" : state.display.name
    }
    private var connectionLabel: String {
        switch state.connectionState {
        case .connected: return "Disconnect"
        case .disconnected: return "Reconnect"
        case .disconnecting: return "Disconnecting…"
        case .reconnecting: return "Reconnecting…"
        }
    }
    private var connectionHint: String {
        if !model.connectionControlAvailable { return "Display connection control is unavailable on this Mac." }
        if connected && model.displays.filter({ $0.connectionState.isConnected }).count < 2 {
            return "The last active screen must stay connected."
        }
        return connected ? "Remove this screen from the macOS layout." : "Restore this screen to the macOS layout."
    }
    private var mayConnect: Bool {
        model.connectionControlAvailable && !state.connectionState.isTransitioning &&
            (!connected || model.displays.filter { $0.connectionState.isConnected }.count > 1)
    }
    private var level: UInt16? { model.desiredSlider[state.id] ?? state.brightness }
    private var output: String {
        guard connected else { return "Disconnected" }
        guard let b = state.brightness else { return "Not available" }
        switch state.brightnessOrigin {
        case .lastSet: return "\(b)% · last hardware command"
        case .liveHardware: return "\(b)% · hardware readback"
        case .liveSoftware: return "\(b)% · software dimming"
        case .unavailable: return "Not available"
        }
    }
    private var frontError: String? {
        guard let e = state.lastError, e != "Live DDC readback unavailable",
              e != "DDC unavailable — using software dimming" else { return nil }
        return e
    }

    private var origin:String {
        guard connected else{return "Disconnected"}
        if state.brightness==nil {return "Not available"}
        switch state.brightnessOrigin {
        case .lastSet:return "Last set"
        case .liveHardware:return "Hardware readback"
        case .liveSoftware:return "Software dimming"
        case .unavailable:return "Not available"
        }
    }
    var body:some View {
        if detailsOnly { details.padding(14).frame(maxWidth:.infinity,alignment:.leading) }
        else {
            VStack(alignment:.leading,spacing:9) {
                HStack(spacing:6) {
                    Button { model.toggleDetails(state.id) } label:{DeckDisplayGlyph(display:state.display)}
                        .buttonStyle(.plain).accessibilityLabel("Details for "+title)
                    VStack(alignment:.leading,spacing:1) {
                        Text(title).font(.system(size:14,weight:.bold)).lineLimit(1)
                        Text(origin).font(.system(size:11)).foregroundStyle(DeckPaint.muted)
                    }
                }
                HStack(spacing:4) {
                    stepButton(.down,"minus","Dim")
                    Slider(value:Binding(get:{Double(level ?? 0)},set:{model.sliderChanged(displayID:state.id,value:$0)}),
                           in:0...100,onEditingChanged:{editing in
                        if editing {model.sliderBegan(state.id)} else {model.sliderEnded(displayID:state.id)}
                    }).controlSize(.small).accessibilityLabel("Brightness for "+title)
                    .accessibilityValue(level.map{"\($0) percent"} ?? "Unavailable")
                    stepButton(.up,"plus","Brighten")
                }.disabled(!connected).help(output)
                HStack(spacing:3){
                    Toggle("Follow Air",isOn:Binding(get:{state.followsAutomatic},set:{model.setFollowsAutomatic($0,displayID:state.id)}))
                        .toggleStyle(.switch).controlSize(.mini).disabled(!connected).accessibilityLabel("Follow Air on "+title)
                    Spacer(minLength:0)
                    Button(expanded ? "Close":"Details"){model.toggleDetails(state.id)}
                        .buttonStyle(.borderless).accessibilityLabel("Display details for "+title)
                        .accessibilityValue(expanded ? "Expanded":"Collapsed")
                }.font(.system(size:11,weight:.medium))
                Button {model.toggleConnection(displayID:state.id)} label:{
                    Label(connected && !mayConnect && model.connectionControlAvailable ? "Last screen":connectionLabel,
                          systemImage:connected ? (mayConnect ? "eject":"lock"):"cable.connector")
                }.controlSize(.small).disabled(!mayConnect).help(connectionHint).accessibilityLabel(connectionLabel+" "+title)
                if let error=frontError {Text(error).font(.caption).foregroundStyle(DeckPaint.muted)}
            }.padding(.trailing,7).frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private func stepButton(_ direction: BrightnessStepDirection, _ icon: String, _ verb: String) -> some View {
        Button { model.step(direction, id: state.id) } label: {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
                .frame(width: 14, height: 16)
        }
        .buttonStyle(.bordered).controlSize(.small)
        .accessibilityLabel("\(verb) \(state.display.name)")
        .help("\(verb) this display by one brightness step")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.display.name).font(.headline)
            Text("Output: \(output)").font(.callout)
            if let w=state.display.desktopWidth,let h=state.display.desktopHeight {
                Text("\(Int(w)) × \(Int(h)) desktop points" + (connected ? "" : " · last known")).font(.caption)
            }
            if let target = state.mappedTarget { Text("Mapped target: \(target)%").font(.callout) }
            if !mayConnect { Text(connectionHint).font(.caption).foregroundStyle(.secondary) }
            if let note = state.lastError, frontError == nil { Text(note).font(.caption).foregroundStyle(.secondary) }
            Text(state.calibration.summary).font(.caption)
            if let note = state.learningNote { Text(note).font(.caption) }
            HStack {
                if state.calibration.canUndo { Button("Undo last match") { model.editCurve(id: state.id, reset: false) } }
                if state.calibration.isCalibrated {
                    if model.resetID == state.id {
                        Button("Confirm reset") { model.editCurve(id: state.id, reset: true) }
                        Button("Cancel") { model.resetID = nil }
                    } else { Button("Reset calibration") { model.resetID = state.id } }
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            if state.controlMethod == .hardwareDDC {
                HStack {
                    Text("Extra dim at minimum")
                    Slider(value: Binding(get: { Double(state.extraDim) },
                        set: { model.setExtraDim($0, id: state.id) }), in: 0...60, step: 1)
                        .accessibilityLabel("Extra dim at minimum for \(state.display.name)")
                    Text(state.extraDim == 0 ? "Off" : "\(state.extraDim)%")
                }
                .font(.caption).disabled(!connected)
            }
            Divider()
            DisplayColorControls(model: model, displayID: state.id, connected: connected)
        }
    }
}
