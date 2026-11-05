import BrightnessCore
import SwiftUI

@MainActor private final class SamsungSourceForm: ObservableObject {
    @Published var editing: MonitorPort?
    @Published var draftName = ""
    @Published var draftCode = ""
    @Published var validationError: String?
    @Published var testPort: MonitorPort?
    @Published var sourceConnected = false
    @Published var recoveryReady = false
    init(testPort: MonitorPort? = nil) { self.testPort = testPort }
}

struct SamsungSourceControls: View {
    @ObservedObject var sources: SamsungSources
    @ObservedObject var shortcuts: DeskShortcuts
    let now: Date
    @StateObject private var form: SamsungSourceForm

    init(sources: SamsungSources, shortcuts: DeskShortcuts, now: Date, initialTestPort: MonitorPort? = nil) {
        self.sources = sources; self.shortcuts = shortcuts; self.now = now
        _form = StateObject(wrappedValue: SamsungSourceForm(testPort: initialTestPort))
    }

    private func action(_ port: MonitorPort) -> DeskAction {
        switch port { case .displayPort: return .samsungDP; case .hdmi1: return .samsungHDMI1; case .hdmi2: return .samsungHDMI2 }
    }
    private func qualified(_ port: MonitorPort) -> Bool {
        sources.target.map { sources.profile.canActivate(port, location: $0.ioLocation) } ?? false
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Samsung sources").font(.system(size:15,weight:.bold))
                Spacer()
                Button(sources.busy ? "Working…" : "Read input") { sources.refresh() }.disabled(sources.busy)
            }
            Text(sources.readLabel(at: now)).font(.caption).foregroundStyle(DeckPaint.muted)
            ForEach(MonitorPort.allCases, id: \.self) { port in
                HStack(spacing: 8) {
                    Image(systemName: shortcuts.symbol(action(port))).frame(width: 20).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sources.route(port).name).font(.system(size:12,weight:.semibold)).lineLimit(1)
                        Text(port.title + (qualified(port)
                            ? (port == .displayPort ? " · code read back" : " · round trip verified")
                            : (port == .displayPort ? " · needs input readback" : " · needs verification")))
                            .font(.caption).foregroundStyle(DeckPaint.muted)
                    }.help(sources.route(port).name)
                    Spacer(minLength: 4)
                    if let key = shortcuts.activeBinding(action(port)) { Text(key.label).font(.caption) }
                    Button("Switch") { sources.activate(port) }.disabled(!sources.canActivate(port))
                        .accessibilityLabel("Switch Samsung to " + sources.route(port).name + " on " + port.title)
                    Menu {
                        Button("Name and mapping…") { beginEditing(port) }
                        if port != .displayPort {
                            Button("Test round trip…") { form.testPort = port; form.sourceConnected = false; form.recoveryReady = false }
                            if qualified(port) { Button("Reset verification") { sources.revoke(port) } }
                        }
                        Button("Configure shortcut…") { shortcuts.record(action(port)) }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(sources.busy)
                    .accessibilityLabel("Configure " + port.title + " on Samsung")
                }
            }
            if let editing = form.editing {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Configure " + editing.title).font(.system(size:12,weight:.semibold))
                    TextField("Device name", text: $form.draftName).accessibilityLabel("Device name for " + editing.title)
                    DisclosureGroup("Advanced DDC mapping") {
                        TextField("DDC code, decimal", text: $form.draftCode)
                            .accessibilityLabel("DDC input code for " + editing.title)
                        Text("Candidate codes are not proof of support. Changing a code clears its verification.").font(.caption)
                    }
                    HStack {
                        Button("Save") {
                            guard let code = UInt16(form.draftCode), code > 0, code <= 255 else {
                                form.validationError = "Enter a decimal input code from 1–255."; return
                            }
                            guard sources.configure(editing, name: form.draftName, code: code) else {
                                form.validationError = sources.notice; return
                            }
                            form.validationError = nil
                            form.editing = nil
                        }
                        Button("Cancel") { form.editing = nil }
                    }
                    if let error = form.validationError { Text(error).font(.caption).foregroundStyle(DeckPaint.ink) }
                }.disabled(sources.busy)
            }
            if let testPort = form.testPort {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Test " + testPort.title + " and return").font(.system(size:12,weight:.semibold))
                    Text("This briefly changes the Samsung input, then requests DisplayPort again after about 3 seconds. Keep this app on the other screen.").font(.caption)
                    Toggle("An awake video device is connected to " + testPort.title, isOn: $form.sourceConnected)
                    Toggle("I can use the other Mac screen and restore DisplayPort with the Samsung JOG control", isOn: $form.recoveryReady)
                    HStack {
                        Button("Test and return") { sources.test(testPort, sourceConnected: form.sourceConnected, recoveryReady: form.recoveryReady) }
                            .disabled(!form.sourceConnected || !form.recoveryReady || sources.busy || !qualified(.displayPort))
                        Button("Close test setup") { form.testPort = nil }.disabled(sources.busy)
                    }
                }.font(.caption)
            }
            if let proof = sources.pending {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Did the HDMI device's picture appear, then the Mac return without using the JOG control?")
                        .font(.system(size:12,weight:.semibold))
                    HStack {
                        Button("Yes, both pictures") { sources.confirm(proof.token, sawBothPictures: true); form.testPort = nil }
                        Button("No · keep disabled") { sources.confirm(proof.token, sawBothPictures: false) }
                    }
                }
            }
            Text(sources.notice).font(.caption).foregroundStyle(DeckPaint.muted)
            if shortcuts.recording?.monitorPort != nil || !shortcuts.notice.isEmpty {
                Text(shortcuts.notice).font(.caption).foregroundStyle(DeckPaint.muted)
            }
        }.controlSize(.small).padding(.vertical, 4)
        .onAppear { sources.refresh() }
    }
    private func beginEditing(_ port: MonitorPort) {
        form.editing = port; form.draftName = sources.route(port).name; form.draftCode = String(sources.route(port).code)
        form.validationError = nil
    }
}
