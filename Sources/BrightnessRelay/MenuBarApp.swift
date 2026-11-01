import AppKit
import BrightnessCore
import Combine
import Foundation
import SwiftUI

extension Notification.Name {
    static let brightnessRelayWakeAll = Notification.Name("dev.pranav.brightness-relay.wake-all")
    static let brightnessRelayShowMenu = Notification.Name("dev.pranav.brightness-relay.show-menu")
}

@MainActor
enum BrightnessMenuBarApplication {
    private static var controller: MenuBarController?

    static func run(server: RelayHTTPServer) {
        let application = NSApplication.shared
        let controller = MenuBarController(server: server)
        self.controller = controller
        application.delegate = controller
        controller.start()
        application.run()
    }
}

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let server: RelayHTTPServer
    private let model: BrightnessMenuModel
    private let keyController: BrightnessKeyController
    private let shadeController = DisplayShadeController()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var didStart = false
    private var terminationSignal: DispatchSourceSignal?

    init(server: RelayHTTPServer) {
        self.server = server
        self.model = BrightnessMenuModel(server: server)
        self.keyController = BrightnessKeyController(
            coordinator: server.displayCoordinator
        )
        super.init()

        keyController.setOnStatus { [weak self] status in
            DispatchQueue.main.async {
                self?.model.keyboardStatusChanged(status)
            }
        }
        model.setKeyboardAccessHandler { [weak keyController] in
            keyController?.requestAccessibility()
        }
        server.setUIStatusProvider { [weak self] in
            MainActor.assumeIsolated { self?.model.diagnostics ?? [:] }
        }

        server.setOnApplied { [weak self] status in
            DispatchQueue.main.async {
                self?.show(status)
            }
        }
        server.setOnPresence { [weak self] presence, solar in
            DispatchQueue.main.async { self?.model.setPresence(presence, solar: solar) }
        }
        server.setOnAmbient { [weak self] sample, source, date in
            DispatchQueue.main.async {
                self?.model.updateAmbient(sample, source: source, receivedAt: date)
            }
        }
        server.setOnControl { [weak self] action, envelope in
            DispatchQueue.main.async {
                guard let self else { return }
                switch action {
                case .showMenu:
                    self.openPopover()
                case .wakeAll:
                    self.model.wakeAll()
                case .syncNow:
                    break
                case .setColor:
                    if let id = envelope.displayID, let value = envelope.value {
                        if value == -1 { self.model.setColorMode(.adaptive, id: id) }
                        else if value == 0 { self.model.setColorMode(.off, id: id) }
                        else { self.model.setColorValue(value, kind: "kelvin", id: id) }
                    }
                case .setConnection:
                    if let id = envelope.displayID, let value = envelope.value {
                        self.server.displayCoordinator.setConnected(value == 1, displayID: id)
                    }
                case .enableKeys:
                    self.keyController.requestAccessibility()
                }
            }
        }
        server.setOnListenerFailure { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.model.receiverFailed(error)
                self.setStatusIcon(symbol: "exclamationmark.triangle.fill")
            }
        }
        server.displayCoordinator.setOnChanged { [weak self] states in
            DispatchQueue.main.async {
                self?.model.updateDisplays(states)
            }
        }
        server.displayCoordinator.setShadeHandler { [weak self] request in
            DispatchQueue.main.async {
                self?.shadeController.apply(request)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        installObservers()
        keyController.start()
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { NSApp.terminate(nil) }
        term.resume()
        terminationSignal = term
        server.start { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    RelayLog.write("Menu receiver failed: \(error)")
                    self.model.receiverFailed(error)
                    self.setStatusIcon(symbol: "exclamationmark.triangle.fill")
                } else {
                    RelayLog.write("Menu receiver listening on port 47777")
                    self.model.receiverReady()
                }
            }
        }
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "dev.pranav.BrightnessRelay"
        statusItem.isVisible = true
        guard let button = statusItem.button else { return }
        setStatusIcon(symbol: "sun.max.fill")
        button.toolTip = "Brightness Relay — control displays"
        button.target = self
        button.action = #selector(togglePopover)

        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 370, height: 500)
        popover.contentViewController = NSHostingController(
            rootView: BrightnessPopoverView(model: model)
        )
        RelayLog.write("Menu bar status item installed")
    }

    private func installObservers() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(wakeAllDisplays),
            name: .brightnessRelayWakeAll,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showMenuFromNotification),
            name: .brightnessRelayShowMenu,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            openPopover()
        }
    }

    @objc private func showMenuFromNotification() {
        RelayLog.write("Received show-menu request")
        openPopover()
    }

    @objc private func wakeAllDisplays() {
        model.wakeAll()
    }

    @objc private func screenParametersChanged() {
        model.colorConfigurationChanged()
        shadeController.updateFrames()
        model.refreshDisplays()
    }

    @objc private func willSleep() { model.restoreColors() }
    @objc private func didWake() {
        model.resumeColors()
        keyController.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.model.colorConfigurationChanged()
            self?.model.refreshDisplays()
            self?.server.requestRefresh()
        }
    }

    func popoverDidClose(_ notification: Notification) { model.setVisible(false) }
    private func openPopover() {
        guard let button = statusItem.button else { return }
        model.refreshDisplays()
        model.setVisible(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        RelayLog.write("Brightness controller popover opened")
    }

    private func show(_ status: AppliedBrightnessStatus) {
        model.show(status)
        setStatusIcon(
            symbol: status.source == "solar-fallback" ? "sun.haze.fill" : "sun.max.fill"
        )
    }

    private func setStatusIcon(symbol: String) {
        let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Brightness Relay"
        )
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.restoreColors()
        keyController.stop()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

@MainActor
final class BrightnessMenuModel: ObservableObject {
    @Published private(set) var displays: [ManagedDisplayState]
    @Published private(set) var receiverStatus = "Starting receiver…"
    @Published private(set) var sourceTitle = "Waiting for MacBook Air"
    @Published private(set) var sourceDetail = "Solar fallback is ready"
    @Published private(set) var isSyncing = false
    @Published private(set) var keyboardStatus: BrightnessKeyStatus = .starting
    @Published private(set) var colorStates: [String: DisplayColorState] = [:]
    @Published private(set) var ambientDetail = "Waiting for Air colour helper"
    @Published private(set) var sourceAge = "No Air reading yet"
    let connectionControlAvailable: Bool

    private let server: RelayHTTPServer
    private let coordinator: DisplayCoordinator
    private var pendingSliderWrites: [String: DispatchWorkItem] = [:]
    private let colorController = DisplayColorController()
    private var onKeyboardAccess: (() -> Void)?
    private var timer: Timer?
    private var presence = SourcePresence()
    private var solarActive = false
    @Published var resetID: String?
    private var editingSliders = Set<String>()
    @Published private(set) var desiredSlider: [String: UInt16] = [:]
    private var lastAmbient: AmbientSample?
    private var lastColourPacketAt: Date?

    init(server: RelayHTTPServer) {
        self.server = server
        self.coordinator = server.displayCoordinator
        self.displays = server.displayCoordinator.snapshot()
        self.connectionControlAvailable = server.displayCoordinator.connectionControlAvailable
        colorController.onChanged = { [weak self] states in self?.colorStates = states }
        colorController.updateDisplays(displays)
    }

    func setVisible(_ visible: Bool) {
        timer?.invalidate(); timer = nil; resetID = nil
        if !visible {
            for id in editingSliders {
                pendingSliderWrites.removeValue(forKey: id)?.cancel()
                desiredSlider.removeValue(forKey: id); coordinator.cancelSlider(id)
            }
            editingSliders.removeAll()
        }
        if visible {
            refreshSourceAge()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSourceAge() }
            }
            RunLoop.main.add(timer, forMode: .common); self.timer = timer
        }
    }
    func setPresence(_ value: SourcePresence, solar: Bool) {
        presence = value; solarActive = solar
        colorController.maximumSampleAge = value.mode == .live ? 90 : 2700
        receiverStatus = "Receiver ready · " + (value.mode.map { $0.rawValue.capitalized + " mode" } ?? "Waiting")
        sourceTitle = value.raw.map { "MacBook Air · " + String(Int(($0 * 100).rounded())) + "%" } ?? "Waiting for Air brightness"
        sourceDetail = value.label(now: Date().timeIntervalSince1970, solar: solar)
        isSyncing = false
        if timer != nil { refreshSourceAge() }
    }

    func receiverReady() {
        receiverStatus = "Receiver ready"
    }

    func receiverFailed(_ error: Error) {
        receiverStatus = "Receiver failed: \(error)"
        isSyncing = false
    }

    func show(_ status: AppliedBrightnessStatus) { isSyncing = false }

    func updateDisplays(_ updated: [ManagedDisplayState]) {
        displays = updated
        colorController.updateDisplays(updated)
    }

    func requestAirSync() {
        isSyncing = true
        sourceDetail = "Requesting a fresh Air reading…"
        server.requestRefresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.isSyncing else { return }
            self.isSyncing = false
            self.sourceDetail = "No reply yet · last settings retained"
        }
    }

    func refreshDisplays() {
        coordinator.refresh(readHardware: false)
    }

    func redetectHardware() {
        coordinator.redetectHardware()
    }

    func wakeAll() {
        coordinator.reconnectAll()
    }

    func setFollowsAutomatic(_ follows: Bool, displayID: String) {
        coordinator.setFollowsAutomatic(follows, displayID: displayID)
    }

    func toggleConnection(displayID: String) {
        guard let display = displays.first(where: { $0.id == displayID }) else { return }
        pendingSliderWrites[displayID]?.cancel()
        coordinator.setConnected(!display.connectionState.isConnected, displayID: displayID)
    }

    func setKeyboardAccessHandler(_ handler: @escaping () -> Void) { onKeyboardAccess = handler }
    func keyboardStatusChanged(_ status: BrightnessKeyStatus) { keyboardStatus = status }
    func requestKeyboardAccess() { onKeyboardAccess?() }
    func setColorMode(_ mode: DisplayColorMode, id: String) { colorController.setMode(mode, id: id) }
    func setColorValue(_ value: Double, kind: String, id: String) { colorController.setValue(value, kind: kind, id: id) }
    func resetColor(id: String) { colorController.reset(id: id) }
    func restoreColors() { colorController.restoreAll() }
    func colorConfigurationChanged() { colorController.configurationChanged() }
    func resumeColors() { colorController.resume() }
    func editCurve(id: String, reset: Bool) { coordinator.editCurve(displayID: id, reset: reset); resetID = nil }
    func setExtraDim(_ amount: Double, id: String) { coordinator.setExtraDim(UInt16(amount.rounded()), displayID: id) }
    func updateAmbient(_ sample: AmbientSample?, source: String, receivedAt: Date) {
        lastAmbient = sample
        lastColourPacketAt = receivedAt
        colorController.accept(sample)
        if timer != nil { refreshSourceAge() }
    }
    private var measurementAgeText: String {
        guard let time = presence.measurement else { return "No Air reading yet" }
        let age = Int(max(0, Date().timeIntervalSince1970 - time))
        return age < 60 ? "Air reading \(age)s ago" : "Air reading \(age / 60) min ago"
    }
    private var ambientText: String {
        guard let sample = lastAmbient else {
            return presence.mode == .live ? "No recent Air colour reading" : (lastColourPacketAt == nil ? "Waiting for Air colour helper" : "Update Air helper for colour sensing")
        }
        if let reason = sample.unavailableReason(maximumAge: colorController.maximumSampleAge) { return reason }
        if let lux = sample.lux, let kelvin = sample.kelvin {
            return String(format: "Room %.0f K · %.0f lux", kelvin, lux)
        }
        return "Air colour unavailable"
    }
    private func refreshSourceAge() {
        sourceAge = measurementAgeText; ambientDetail = ambientText
        sourceDetail = presence.label(now: Date().timeIntervalSince1970, solar: solarActive)
    }

    var diagnostics: [String: Any] {
        ["keyboard": keyboardStatus.title,
         "sourceAge": measurementAgeText,
         "ambient": ambientText,
         "colors": colorStates.mapValues { state -> [String: Any] in
             ["mode": state.settings.mode.rawValue, "detail": state.detail,
              "targetKelvin": state.targetKelvin as Any? ?? NSNull(),
              "error": state.error as Any? ?? NSNull()]
         }]
    }

    func sliderBegan(_ id: String) { editingSliders.insert(id); coordinator.beginSlider(id) }
    func sliderChanged(displayID: String, value: Double) {
        let target = UInt16(min(max(value.rounded(), 0), 100))
        desiredSlider[displayID] = target
        guard pendingSliderWrites[displayID] == nil else { return }
        coordinator.setManualBrightness(target, displayID: displayID)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSliderWrites[displayID] = nil
            if let newest = self.desiredSlider[displayID], newest != target {
                self.coordinator.setManualBrightness(newest, displayID: displayID)
            }
        }
        pendingSliderWrites[displayID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
    }

    func sliderEnded(displayID: String) {
        pendingSliderWrites[displayID]?.cancel()
        pendingSliderWrites[displayID] = nil
        editingSliders.remove(displayID)
        guard let target = desiredSlider.removeValue(forKey: displayID) else { coordinator.cancelSlider(displayID); return }
        coordinator.setManualBrightness(target, displayID: displayID, final: true)
    }

    func openLog() {
        NSWorkspace.shared.open(RelayLog.fileURL)
    }

}

@MainActor
private final class DisplayShadeController {
    private var windows: [String: NSWindow] = [:]
    private var fadingOut: [String: UUID] = [:]
    private var requests: [String: DisplayShadeRequest] = [:]

    func apply(_ request: DisplayShadeRequest) {
        let id = request.display.id, prior = requests[id]
        requests[id] = request
        guard let screen = screen(for: request.display.displayID) else {
            windows[request.display.id]?.orderOut(nil)
            return
        }

        let shouldShade = request.isConnected &&
            ((request.usesSoftwareDimming && request.brightness < 100) || request.extraDim > 0)
        guard shouldShade else {
            guard let window = windows[id] else { return }
            if request.isConnected && (prior?.extraDim ?? 0) > 0 {
                let token = UUID(); fadingOut[id] = token
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22; window.contentView?.animator().alphaValue = 0
                } completionHandler: { [weak self, weak window] in
                    DispatchQueue.main.async {
                        guard self?.fadingOut[id] == token else { return }
                        self?.fadingOut[id] = nil; window?.orderOut(nil)
                    }
                }
            } else if !request.isConnected || fadingOut[id] == nil { window.orderOut(nil) }
            return
        }
        fadingOut[id] = nil

        let window = windows[request.display.id] ?? makeWindow(for: request.display.id)
        windows[request.display.id] = window
        window.setFrame(screen.frame, display: true)
        let alpha: CGFloat = request.extraDim > 0 ? CGFloat(request.extraDim) / 100 : 1 - CGFloat(request.brightness) / 100
        window.contentView?.alphaValue = min(max(alpha, 0), 1)
        window.orderFrontRegardless()
    }

    func updateFrames() {
        for request in requests.values {
            apply(request)
        }
    }

    private func makeWindow(for displayID: String) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Brightness Relay shade for \(displayID)"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        window.collectionBehavior = [
            .stationary,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = view
        return window
    }

    private func screen(for displayID: UInt32) -> NSScreen? {
        NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        }
    }
}

private struct BrightnessPopoverView: View {
    @ObservedObject var model: BrightnessMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            if model.displays.isEmpty {
                ContentUnavailableView(
                    "No External Displays",
                    systemImage: "display.trianglebadge.exclamationmark",
                    description: Text("Connect a display, then refresh.")
                )
                .frame(height: 170)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.displays) { display in
                            DisplayControlCard(model: model, state: display)
                        }
                    }
                }
                .frame(maxHeight: 520)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 370)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Brightness Relay")
                        .font(.headline)
                    Text(model.receiverStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: model.requestAirSync) {
                    Image(systemName: model.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Sync from MacBook Air now")
                .disabled(model.isSyncing)
            }
            HStack {
                Text(model.sourceTitle)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(model.sourceDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(model.sourceAge)
                .font(.caption2).foregroundStyle(.secondary)
            Text(model.ambientDetail)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "keyboard")
                Text(model.keyboardStatus.title)
                Spacer()
                if model.keyboardStatus.needsPermission {
                    Button("Enable", action: model.requestKeyboardAccess)
                }
            }
            .font(.caption2)
            .help("Brightness keys adjust connected screens. Option+Shift uses 1% steps. Disable competing key handlers in Lunar or MonitorControl.")
            HStack(spacing: 13) {
            Button("Reconnect All", systemImage: "display.2") {
                model.wakeAll()
            }
            .help("Reconnect screens removed from the macOS display layout")

            Button("Re-detect", systemImage: "arrow.triangle.2.circlepath") {
                model.redetectHardware()
            }
            .help("Retry DDC and refresh monitor readings")

            Spacer()

            Button(action: model.openLog) {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .help("Open receiver log")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        }
    }
}

private struct DisplayControlCard: View {
    @ObservedObject var model: BrightnessMenuModel
    let state: ManagedDisplayState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: state.display.isMain ? "display" : "tv")
                    .foregroundStyle(state.connectionState.isConnected ? Color.primary : Color.secondary)
                Text(state.display.name)
                    .font(.subheadline.weight(.semibold))
                if state.display.isMain && state.connectionState.isConnected {
                    Text("MAIN")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Text(readingLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(readingColor)
            }

            HStack(spacing: 9) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(model.desiredSlider[state.id] ?? state.brightness ?? 50) },
                        set: { model.sliderChanged(displayID: state.id, value: $0) }
                    ),
                    in: 0 ... 100,
                    onEditingChanged: { editing in
                        if editing { model.sliderBegan(state.id) } else { model.sliderEnded(displayID: state.id) }
                    }
                )
                .accessibilityLabel("Brightness for " + state.display.name)
                .disabled(!state.connectionState.isConnected)
                Text("\(model.desiredSlider[state.id] ?? state.brightness ?? 0)%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 34, alignment: .trailing)
            }

            HStack(spacing: 10) {
                Toggle(
                    "Follow automatic",
                    isOn: Binding(
                        get: { state.followsAutomatic },
                        set: { model.setFollowsAutomatic($0, displayID: state.id) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                .disabled(!state.connectionState.isConnected)

                Spacer()

                Button {
                    model.toggleConnection(displayID: state.id)
                } label: {
                    Label(
                        connectionLabel,
                        systemImage: state.connectionState.isConnected ? "display.trianglebadge.exclamationmark" : "display"
                    )
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.medium))
                .disabled(!model.connectionControlAvailable || state.connectionState.isTransitioning ||
                          (state.connectionState.isConnected &&
                           model.displays.filter { $0.connectionState.isConnected }.count < 2))
                .help("Remove this screen from the macOS layout, then reconnect it here. At least one screen must stay connected.")
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(methodColor)
                    .frame(width: 6, height: 6)
                Text(methodLabel)
                if let error = state.lastError {
                    Text("· \(error)")
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let target = state.mappedTarget { Text("Mapped target \(target)%") }
                    Spacer()
                    Text(state.calibration.summary)
                }
                if let note = state.learningNote { Text(note) }
                HStack {
                    if state.calibration.canUndo { Button("Undo last match") { model.editCurve(id: state.id, reset: false) } }
                    if state.calibration.isCalibrated {
                        if model.resetID == state.id {
                            Button("Confirm reset") { model.editCurve(id: state.id, reset: true) }
                            Button("Cancel") { model.resetID = nil }
                        } else { Button("Reset calibration") { model.resetID = state.id } }
                    }
                }
                if state.controlMethod == .hardwareDDC {
                    HStack {
                        Text("Extra dim at minimum")
                        Slider(value: Binding(get: { Double(state.extraDim) },
                            set: { model.setExtraDim($0, id: state.id) }), in: 0...60, step: 1)
                            .accessibilityLabel("Extra dim at minimum for " + state.display.name)
                        Text(state.extraDim == 0 ? "Off" : "\(state.extraDim)%")
                    }
                    .disabled(!state.connectionState.isConnected)
                }
            }
            .buttonStyle(.borderless).font(.caption2)
            Divider()
            DisplayColorControls(model: model, displayID: state.id,
                                 connected: state.connectionState.isConnected)
        }
        .padding(11)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5)
        }
    }

    private var readingLabel: String {
        guard state.connectionState.isConnected else { return connectionLabel }
        guard let brightness = state.brightness else { return "Unavailable" }
        switch state.brightnessOrigin {
        case .liveHardware: return "\(brightness)% · Live"
        case .lastSet: return "\(brightness)% · Last set"
        case .liveSoftware: return "\(brightness)% · Software live"
        case .unavailable: return "Unavailable"
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

    private var readingColor: Color {
        switch state.brightnessOrigin {
        case .liveHardware, .liveSoftware: return .green
        case .lastSet, .unavailable: return .secondary
        }
    }

    private var methodLabel: String {
        switch state.controlMethod {
        case .detecting: return "Detecting control path"
        case .hardwareDDC: return "Hardware DDC"
        case .softwareDimming: return "Software dimming"
        }
    }

    private var methodColor: Color {
        switch state.controlMethod {
        case .detecting: return .orange
        case .hardwareDDC: return .blue
        case .softwareDimming: return .purple
        }
    }
}

private struct DisplayColorControls: View {
    @ObservedObject var model: BrightnessMenuModel
    let displayID: String
    let connected: Bool
    private var state: DisplayColorState { model.colorStates[displayID] ?? DisplayColorState() }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("White balance").font(.caption.weight(.semibold))
                Spacer()
                Button("Reset") { model.resetColor(id: displayID) }
                    .buttonStyle(.borderless).font(.caption2)
            }
            Picker("White balance", selection: Binding(
                get: { state.settings.mode },
                set: { model.setColorMode($0, id: displayID) }
            )) {
                ForEach(DisplayColorMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented).labelsHidden()
            .disabled(!connected)
            if state.settings.mode == .manual {
                HStack {
                    Text("Warm").font(.caption2)
                    Slider(value: Binding(get: { state.settings.manualKelvin },
                        set: { model.setColorValue($0, kind: "kelvin", id: displayID) }),
                        in: 3500...7500, step: 50)
                    Text("Cool").font(.caption2)
                }
                .disabled(!connected)
            }
            if state.settings.mode == .adaptive {
                HStack {
                    Text("Strength").font(.caption2).frame(width: 47, alignment: .leading)
                    Slider(value: Binding(get: { state.settings.strength },
                        set: { model.setColorValue($0, kind: "strength", id: displayID) }),
                        in: 0...1, step: 0.05)
                    Text("\(Int(state.settings.strength * 100))%").font(.caption2).frame(width: 29)
                }
                HStack {
                    Text("Trim").font(.caption2).frame(width: 47, alignment: .leading)
                    Slider(value: Binding(get: { state.settings.trim },
                        set: { model.setColorValue($0, kind: "trim", id: displayID) }),
                        in: -1000...1000, step: 50)
                    Text("\(Int(state.settings.trim))").font(.caption2).frame(width: 29)
                }
                .help("Negative is warmer; positive is cooler. This screen's trim is independent.")
            }
            Text(state.error ?? state.detail)
                .font(.caption2)
                .foregroundStyle(state.error == nil ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
