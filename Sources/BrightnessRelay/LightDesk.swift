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
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let notice = model.syncNotice {
                Label(notice, systemImage: "info.circle").font(.caption).padding(.vertical, 4)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.actionsOpen { DeskShortcutEditor(shortcuts:model.shortcuts).id("desk.shortcuts") }
                        DeskWindowsView(windows:model.windows,shortcuts:model.shortcuts,requestAccess:model.requestKeyboardAccess)
                        if model.displays.isEmpty {
                            ContentUnavailableView("No external displays", systemImage: "display",
                                description: Text("Connect a display, then choose Re-detect in Desk details."))
                                .frame(maxWidth: .infinity, minHeight: 155)
                        }
                        ForEach(model.displays) { state in
                            DeskScreenStrip(model: model, state: state).id(state.id)
                        }
                        if let pair = model.tv.paired, !model.displays.contains(where: { $0.id == pair.display }) {
                            TVStrip(remote:model.tv,shortcuts:model.shortcuts,display:pair.display)
                        }
                        if model.toolsOpen { tools.id("desk.tools") }
                    }
                    .padding(12)
                }
                .onChange(of: model.toolsOpen) { _, open in
                    if open { proxy.scrollTo("desk.tools", anchor: .bottom) }
                }
                .onChange(of: model.actionsOpen) { _, open in
                    if open { proxy.scrollTo("desk.shortcuts",anchor:.top) }
                    else { model.shortcuts.cancelRecording() }
                }
                .onChange(of: model.detailedDisplay) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .top) }
                }
            }
            footer
        }
        .frame(width: DeskLayout.width, height: height)
        .background(DeskPaint.paper(dark))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 7) {
                Image(nsImage: DeskMark.image(.linked)).renderingMode(.template)
                    .foregroundStyle(DeskPaint.cream).accessibilityHidden(true)
                Text("BRIGHTMESS").font(.system(size: 10, weight: .bold)).tracking(1.5)
            }
            Text("Light desk")
                .font(.system(size: 35, weight: .bold, design: .serif)).tracking(-1.25)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 7) {
                Image(systemName: "laptopcomputer")
                Text("MacBook Air").fontWeight(.semibold)
                Text("·").accessibilityHidden(true)
                Text(model.deskStatus)
                    .fontWeight(.medium)
            }
            .font(.system(size: 12))
            .accessibilityElement(children: .combine)
        }
        .foregroundStyle(DeskPaint.cream)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 19).padding(.vertical, 14)
        .background { ZStack { DeskPaint.ink; DeskHorizon() } }
        .overlay(alignment: .bottomTrailing) {
            Button { model.requestAirSync() } label: {
                Label(model.isSyncing ? "Syncing" : (model.justSynced ? "Synced" : "Sync now"),
                      systemImage: model.justSynced ? "checkmark" : "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(DeskPaint.ink, in: Capsule())
                    .overlay(Capsule().stroke(DeskPaint.mint.opacity(0.62), lineWidth: 1))
            }
            .buttonStyle(.plain).foregroundStyle(DeskPaint.cream).disabled(model.isSyncing)
            .help("Request a fresh reading from the Air")
            .padding(.trailing, 15).padding(.bottom, 9)
        }
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
                Label(model.displays.isEmpty ? "No screens" : "All connected", systemImage: "link")
                    .foregroundStyle(.secondary).font(.caption)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.borderless)
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(DeskPaint.surface(dark))
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
        .background(DeskPaint.surface(dark), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct DeskScreenStrip: View {
    @ObservedObject var model: BrightnessMenuModel
    let state: ManagedDisplayState
    @Environment(\.colorScheme) private var scheme
    private var connected: Bool { state.connectionState.isConnected }
    private var expanded: Bool { model.detailedDisplay == state.id }
    private var title: String {
        state.display.vendorID == 0x4c2d && state.display.name == "LU28R55" ? "Samsung" : state.display.name
    }
    private var kindName: String {
        switch state.display.shape {
        case .portraitMonitor: return "Portrait monitor"
        case .monitor: return "Monitor"
        case .television: return "Television"
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Button { model.toggleDetails(state.id) } label: {
                    DeskDeviceArt(kind: state.display.shape, brightness: state.brightness, connected: connected)
                        .frame(width: 114, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(expanded ? "Hide" : "Show") details for \(title)")
                .help("Toggle display details for \(state.display.name)")
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(1)
                        Spacer(minLength: 2)
                        Button { model.toggleDetails(state.id) } label: {
                            HStack(spacing: 3) {
                                Text("Details")
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            }.font(.caption).frame(minHeight: 23)
                        }
                        .buttonStyle(.borderless).help("Display details")
                        .accessibilityLabel("\(expanded ? "Hide" : "Show") details for \(state.display.name)")
                        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                    }
                    Text(connected ? kindName : "\(kindName) · Disconnected")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        stepButton(.down, "minus", "Dim")
                        Slider(value: Binding(
                            get: { Double(level ?? 0) },
                            set: { model.sliderChanged(displayID: state.id, value: $0) }
                        ), in: 0...100, onEditingChanged: { editing in
                            if editing { model.sliderBegan(state.id) } else { model.sliderEnded(displayID: state.id) }
                        })
                        .controlSize(.small)
                        .tint(scheme == .dark ? DeskPaint.mint : DeskPaint.spruce)
                        .accessibilityLabel("Brightness for \(state.display.name)")
                        .accessibilityValue(level.map { "\($0) percent" } ?? "Unavailable")
                        stepButton(.up, "plus", "Brighten")
                    }
                    .disabled(!connected)
                    .help(connected ? output : "This screen is disconnected.")
                }
            }
            .padding(.horizontal, 12).padding(.top, 11)
            HStack(spacing: 10) {
                Toggle("Follow Air", isOn: Binding(get: { state.followsAutomatic },
                    set: { model.setFollowsAutomatic($0, displayID: state.id) }))
                    .toggleStyle(.switch).controlSize(.small)
                    .tint(scheme == .dark ? DeskPaint.mint : DeskPaint.spruce).disabled(!connected)
                    .accessibilityLabel("Follow Air on \(state.display.name)")
                Spacer()
                Button { model.toggleConnection(displayID: state.id) } label: {
                    Label(connected && !mayConnect && model.connectionControlAvailable ? "Last screen" : connectionLabel,
                          systemImage: connected ? (mayConnect ? "eject" : "lock") : "cable.connector")
                }
                .buttonStyle(.bordered).controlSize(.small).disabled(!mayConnect)
                .accessibilityLabel("\(connectionLabel) \(state.display.name)")
                .help(connectionHint)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 13).padding(.top, 5).padding(.bottom, 10)
            if state.display.shape == .television && (model.tv.paired == nil || model.tv.paired?.display == state.id) {
                TVStrip(remote:model.tv,shortcuts:model.shortcuts,display:state.id)
            }
            if let error = frontError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
            if expanded {
                Divider()
                details.padding(12)
            }
        }
        .background(DeskPaint.surface(scheme == .dark), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.primary.opacity(0.10), lineWidth: 1).allowsHitTesting(false))
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
