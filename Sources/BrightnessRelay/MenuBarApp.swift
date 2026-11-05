import AppKit
import ApplicationServices
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
    private let bringHere = BringHerePanel()
    private var didStart = false
    private var terminationSignal: DispatchSourceSignal?
    private var markMode:DeskMark.Mode = .linked
    private let markCue=DeskMarkCue()

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
        bringHere.requestAccess = {
            if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {NSWorkspace.shared.open(url)}
        }
        model.openWindowPicker = {[weak self] in self?.openWindowPicker()}
        model.shortcuts.perform = { [weak self] action in
            guard let self else { return }
            if action == .bringHere {self.openWindowPicker()}
            else if action == .move { self.model.windows.toggle(captured:self.popover.isShown) }
            else if let port = action.monitorPort {
                let ready = self.model.samsungSources.canActivate(port)
                self.model.samsungSources.activate(port)
                if !ready { NSSound.beep() }
            }
            else { self.model.tv.activate(action); if !self.model.tv.ready { NSSound.beep() } }
        }
        model.shortcuts.tvNeeded = { [weak model] needed in model?.tv.keepForShortcuts(needed) }
        server.setUIStatusProvider { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return [:] }
                var result = self.model.diagnostics
                result["panel"] = "Source Deck"
                result["panelVisible"] = self.popover.isShown
                result["tvPaired"] = self.model.tv.paired != nil
                result["tvRemoteReady"] = self.model.tv.ready
                result["tvNotice"] = self.model.tv.notice
                result["tvConnectionError"] = self.model.tv.lastConnectionError ?? NSNull() as Any
                if let tv = self.model.tv.paired {
                    result["tvInputs"] = ["ps5": tv.routeLabel(.ps5), "mac": tv.routeLabel(.mac),
                        "ps5InputID": tv.ps5, "macInputID": tv.mini]
                }
                result["deskActions"] = self.model.shortcuts.diagnostics
                result["windowMoves"] = self.model.windows.successfulMoves
                result["bringHere"] = self.bringHere.model.diagnostics
                result["windowAccessibility"] = AXIsProcessTrusted()
                result["tvLastSent"] = self.model.tv.lastSent ?? NSNull() as Any
                result["samsungSources"] = self.model.samsungSources.diagnostics
                result["uiBuild"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? NSNull()
                return result
            }
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
                self.setStatusIcon(.attention)
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
        model.windows.observeFocus()
        model.shortcuts.start()
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
                    self.setStatusIcon(.attention)
                } else {
                    RelayLog.write("Menu receiver listening on port 47777")
                    self.model.receiverReady()
                }
            }
        }
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "dev.pranav.BrightnessRelay"
        statusItem.isVisible = true
        guard let button = statusItem.button else { return }
        setStatusIcon(.linked)
        button.toolTip = "BRIGHTMESS: open Source Deck"
        button.setAccessibilityLabel("BRIGHTMESS: open Source Deck")
        button.target = self
        button.action = #selector(togglePopover)

        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        let panelHeight = DeskLayout.height(for: NSScreen.main?.visibleFrame.height)
        popover.contentSize = NSSize(width: DeskLayout.width, height: panelHeight)
        popover.contentViewController = NSHostingController(
            rootView: BrightnessPopoverView(model: model, height: panelHeight)
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
            let mouseClick = NSApp.currentEvent.map { [.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp].contains($0.type) } ?? false
            let clicked = mouseClick ? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation,$0.frame,false) } : nil
            openPopover(clickedScreen:clicked)
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
        setStatusIcon(markMode)
        model.windows.topologyChanged()
        bringHere.model.topologyChanged()
        model.colorConfigurationChanged()
        shadeController.updateFrames()
        model.refreshDisplays()
    }

    @objc private func willSleep() { bringHere.dismiss(restoring:false);model.samsungSources.stop(); model.restoreColors(); model.shortcuts.suspendInput(); model.tv.sleeping(true) }
    @objc private func didWake() {
        model.resumeColors()
        model.tv.sleeping(false)
        keyController.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.model.colorConfigurationChanged()
            self?.model.refreshDisplays()
            self?.server.requestRefresh()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        markCue.reset();updateMarkImage()
        model.setVisible(false); model.shortcuts.cancelRecording(); model.windows.close(); model.tv.close()
    }
    private func openPopover(clickedScreen:NSScreen?=nil) {
        if bringHere.model.visible {bringHere.dismiss(restoring:false)}
        guard let button = statusItem.button else { return }
        guard !popover.isShown else { return }
        let destination=clickedScreen ?? button.window?.screen
        model.windows.capture(screen:destination)
        let height=DeskLayout.height(for:destination?.visibleFrame.height)
        if popover.contentSize.height != height {
            popover.contentSize=NSSize(width:DeskLayout.width,height:height)
            popover.contentViewController=NSHostingController(rootView:BrightnessPopoverView(model:model,height:height))
        }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.tv.open()
        model.refreshDisplays()
        model.setVisible(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if popover.isShown {
            markCue.open(reduced:{NSWorkspace.shared.accessibilityDisplayShouldReduceMotion}) { [weak self] in
                self?.updateMarkImage()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        RelayLog.write("Brightness controller popover opened")
    }

    private func openWindowPicker(){
        if popover.isShown {popover.performClose(nil)}
        bringHere.toggle()
    }

    private func show(_ status: AppliedBrightnessStatus) {
        setStatusIcon(status.source == "solar-fallback" ? .solar : .linked)
    }

    private func setStatusIcon(_ mode: DeskMark.Mode) {
        markMode=mode
        updateMarkImage()
        statusItem?.button?.toolTip = mode.label
        statusItem?.button?.setAccessibilityLabel(mode.label)
    }

    private func updateMarkImage() {
        let image=DeskMark.image(markMode,frame:markCue.frame)
        if statusItem?.button?.image !== image { statusItem?.button?.image=image }
    }

    func applicationWillTerminate(_ notification: Notification) {
        markCue.reset()
        bringHere.stop()
        model.shortcuts.stop(); model.windows.stop(); model.tv.shutdown()
        model.samsungSources.stop()
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
    var openWindowPicker:(()->Void)?
    let windows = DeskWindows()
    let tv: TVRemote
    let shortcuts: DeskShortcuts
    let samsungSources: SamsungSources
    @Published var actionsOpen = false
    @Published private(set) var displays: [ManagedDisplayState]
    @Published private(set) var receiverStatus = "Starting receiver…"
    @Published private(set) var sourceTitle = "Waiting for MacBook Air"
    @Published private(set) var sourceDetail = "Waiting for Air"
    @Published private(set) var isSyncing = false
    @Published private(set) var keyboardStatus: BrightnessKeyStatus = .starting
    @Published private(set) var colorStates: [String: DisplayColorState] = [:]
    @Published private(set) var ambientDetail = "Waiting for Air colour helper"
    @Published private(set) var sourceAge = "No Air reading yet"
    @Published private(set) var readbackNow = Date()
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
    @Published var detailedDisplay: String?
    private var panelVisible = false
    @Published var toolsOpen = false { didSet { updateAgeTimer() } }
    @Published private(set) var syncNotice: String?
    private var syncID: UUID?
    @Published private(set) var justSynced = false
    var deskStatus: String {
        if receiverStatus.hasPrefix("Receiver failed") { return "Receiver unavailable" }
        if isSyncing { return "Syncing" }
        return sourceDetail
    }
    var canReconnect: Bool {
        connectionControlAvailable && displays.contains { $0.connectionState == .disconnected }
    }
    func toggleDetails(_ id: String) {
        detailedDisplay = detailedDisplay == id ? nil : id; resetID = nil
    }
    func step(_ direction: BrightnessStepDirection, id: String) {
        coordinator.adjustManualBrightness(direction: direction, fine: false, displayID: id)
    }
    private var editingSliders = Set<String>()
    @Published private(set) var desiredSlider: [String: UInt16] = [:]
    private var lastAmbient: AmbientSample?
    private var lastColourPacketAt: Date?

    init(server: RelayHTTPServer, fixture: Bool = false, shortcutDefaults: UserDefaults = .standard) {
        tv = TVRemote(fixture:fixture)
        #if DEBUG
        shortcuts = fixture ? DeskShortcuts.fixture(defaults:shortcutDefaults) : DeskShortcuts(defaults:shortcutDefaults)
        #else
        shortcuts = DeskShortcuts(defaults:shortcutDefaults)
        #endif
        self.server = server
        self.coordinator = server.displayCoordinator
        samsungSources = SamsungSources(coordinator: server.displayCoordinator, defaults: shortcutDefaults, fixture: fixture)
        self.displays = server.displayCoordinator.snapshot()
        self.connectionControlAvailable = server.displayCoordinator.connectionControlAvailable
        samsungSources.updateDisplays(displays)
        colorController.onChanged = { [weak self] states in self?.colorStates = states }
        colorController.updateDisplays(displays)
    }

    func setVisible(_ visible: Bool) {
        panelVisible = visible; resetID = nil
        if !visible {
            detailedDisplay = nil; toolsOpen = false
            for id in editingSliders {
                pendingSliderWrites.removeValue(forKey: id)?.cancel()
                desiredSlider.removeValue(forKey: id); coordinator.cancelSlider(id)
            }
            editingSliders.removeAll()
        }
        if visible { refreshSourceAge(); coordinator.refreshReadbacksIfDue(); samsungSources.refresh() }
        updateAgeTimer()
    }

    private func updateAgeTimer() {
        timer?.invalidate(); timer = nil
        guard panelVisible else { return }
        refreshSourceAge()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.readbackNow = Date()
                if self.toolsOpen { self.refreshSourceAge() }
                self.coordinator.refreshReadbacksIfDue()
            }
        }
        t.tolerance = 0.15
        RunLoop.main.add(t, forMode: .common); timer = t
    }
    func setPresence(_ value: SourcePresence, solar: Bool) {
        let answered = isSyncing && value.state == .awake && value.measurement != presence.measurement
        let lost = isSyncing && value.lostAt != nil && value.lostAt != presence.lostAt
        presence = value; solarActive = solar
        colorController.maximumSampleAge = value.mode == .live ? 90 : 2700
        receiverStatus = "Receiver ready · " + (value.mode.map { $0.rawValue.capitalized + " mode" } ?? "Waiting")
        sourceTitle = value.raw.map { "MacBook Air · " + String(Int(($0 * 100).rounded())) + "%" } ?? "Waiting for Air brightness"
        sourceDetail = value.label(now: Date().timeIntervalSince1970, solar: solar)
        if answered || lost {
            let id = syncID
            isSyncing = false; justSynced = answered
            syncNotice = lost ? "Air unavailable. Keeping the last settings." : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.syncID == id else { return }
                self.justSynced = false; self.syncID = nil
            }
        } else if value.state == .awake && !isSyncing { syncNotice = nil }
        if timer != nil { refreshSourceAge() }
    }

    func receiverReady() {
        receiverStatus = "Receiver ready"
    }

    func receiverFailed(_ error: Error) {
        receiverStatus = "Receiver failed: \(error)"
        isSyncing = false
    }



    func updateDisplays(_ updated: [ManagedDisplayState]) {
        readbackNow = Date()
        displays = updated
        samsungSources.updateDisplays(updated)
        if let detailedDisplay, !updated.contains(where: { $0.id == detailedDisplay }) { self.detailedDisplay = nil; resetID = nil }
        colorController.updateDisplays(updated)
    }

    func requestAirSync() {
        guard !isSyncing else { return }
        let request = UUID(); syncID = request; syncNotice = nil
        isSyncing = true; justSynced = false
        sourceDetail = "Requesting a fresh Air reading…"
        server.requestRefresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.isSyncing, self.syncID == request else { return }
            self.isSyncing = false
            self.syncID = nil; self.syncNotice = "Air hasn’t replied. Keeping the last settings."
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
        window.title = "BRIGHTMESS shade for \(displayID)"
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

struct DisplayColorControls: View {
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
                    .disabled(!connected || (state.settings.mode == .off && state.settings.strength == 0.65 &&
                        state.settings.trim == 0 && state.settings.manualKelvin == 6500 && state.error == nil))
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
