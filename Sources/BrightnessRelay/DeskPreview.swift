#if DEBUG
import AppKit
import SwiftUI
import BrightnessCore
import BrightnessHardware

/// Draw the production panel to a PNG from isolated fixtures. No receiver,
/// real display writes, keyboard hooks, or persistent user preferences.
@MainActor enum DeskPreview {
    final class Desk: DisplayDriver, DisplayConnections {
        let ledger: DisplayRecoveryLedger
        let isAvailable = true
        private var detached = Set<String>()
        func isOnline(_ display: ExternalDisplay) -> Bool { !detached.contains(display.id) }
        func disconnectedDisplays() -> [ExternalDisplay] { panels.filter { detached.contains($0.id) } }
        func disconnect(_ display: ExternalDisplay) throws {
            try ledger.record(display); detached.insert(display.id)
        }
        func reconnect(_ display: ExternalDisplay) throws -> UInt32 {
            try ledger.remove(displayID: display.id); detached.remove(display.id)
            return display.displayID
        }
        func recoverAll() throws -> [DisplayRecoveryOutcome] { [] }
        func displays() -> [ExternalDisplay] { panels.filter(isOnline) }
        let count: Int
        init(count: Int, temp: URL) { self.count = count; ledger = DisplayRecoveryLedger(fileURL: temp.appendingPathComponent("ledger")) }
        var panels: [ExternalDisplay] {
            Array(["LU28R55", "Beyond TV"].prefix(count)).enumerated().map { index, name in
                ExternalDisplay(id: "test-desk-\(index)", displayID: UInt32(51000+index), name: name,
                    vendorID: index == 0 ? 0x4c2d : 0x6318, productID: UInt32(index+1),
                    serialNumber: 0, edidUUID: "", ioLocation: "", isMain: index == 0, supportsStandby: false, deskShape: index == 0 ? .portraitMonitor : .television)
            }
        }
        func set(percentage: UInt16, on display: ExternalDisplay) throws { if display.shape == .television { throw CLIError.invalidValue("Software-only fixture") } }
        func readBrightness(of display: ExternalDisplay) throws -> DDCValue { throw CLIError.invalidValue("fixture") }
    }

    private final class CloseHandler: NSObject, NSWindowDelegate {
        func windowWillClose(_ note: Notification) { NSApp.stop(nil) }
    }

    static func render(_ args: CLIArguments) throws {
        guard let path = args.positional(at: 0) else { throw CLIError.missingValue("output PNG") }
        let interactive = args.values.contains("--window")
        _ = NSApplication.shared
        if interactive { NSApp.setActivationPolicy(.regular) }
        let name: NSAppearance.Name = args.values.contains("--dark") ? .darkAqua : .aqua
        NSApp.appearance = NSAppearance(named: name)
        let suite = "dev.pranav.relay.preview." + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: temp) }
        let desk = Desk(count: args.values.contains("--empty") ? 0 : 2, temp: temp)
        for (i,d) in desk.panels.enumerated() {
            let key = "dev.pranav.brightness-relay.display." + d.id + "."
            prefs.set(i == 0 ? 68 : 48, forKey: key + "lastBrightness")
            prefs.set(i == 0 ? "hardwareDDC" : "softwareDimming", forKey: key + "controlMethod")
            if i == 1 {
                var curve = LearnedCurve(); curve.learn(0.62, 48)
                prefs.set(try JSONEncoder().encode(curve), forKey: key + "calibrationV2")
            }
        }
        let coordinator = DisplayCoordinator(hardware: desk,
            connection: desk, defaults: prefs)
        let fit = try BrightnessCurve()
        _ = try? coordinator.applyAutomatic(target: fit.map(normalized: 0.62), deadband: 1,
            sourceBrightness: 0.62, measuredAt: Date(), baseCurve: fit)
        if args.values.contains("--offline") { coordinator.setConnected(false, displayID: "test-desk-1") }
        let server = try RelayHTTPServer(port: 0, authenticator: .init(token: Data(repeating: 4, count: 32)),
            displayCoordinator: coordinator, curve: .init(), loopbackOnly: true)
        let model = BrightnessMenuModel(server: server,fixture:true)
        model.windows.loadFixture()
        let time = Date().timeIntervalSince1970
        var presence = SourcePresence()
        presence.receive(mode: .live, state: .awake, time: time, brightness: 0.62)
        model.setPresence(presence, solar: args.values.contains("--solar"))
        model.updateAmbient(AmbientSample(lux: 40, kelvin: 5413, sampledAt: time), source: "Fixture Air", receivedAt: Date())
        model.setVisible(true); model.keyboardStatusChanged(.ready)
        let states = coordinator.snapshot()
        model.updateDisplays(states)
        if args.values.contains("--details"), let id = states.first?.id { model.toggleDetails(id) }
        if args.values.contains("--tools") { model.toolsOpen = true }
        let size = CGSize(width: DeskLayout.width, height: DeskLayout.height(for: nil))
        let host = NSHostingView(rootView: BrightnessPopoverView(model: model)
            .environment(\.controlActiveState, .key)
            .frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: interactive ? [.titled, .closable] : .borderless, backing: .buffered, defer: false)
        window.appearance = NSApp.appearance; window.contentView = host
        window.setContentSize(size); host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CLIError.invalidValue("bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CLIError.invalidValue("PNG") }
        try png.write(to: URL(fileURLWithPath: path), options: .atomic)
        if interactive {
            coordinator.setOnChanged { [weak model] value in DispatchQueue.main.async { model?.updateDisplays(value) } }
            window.title = "Light desk – isolated test displays"
            window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            let close = CloseHandler(); window.delegate = close
            withExtendedLifetime(close) { NSApp.run() }
        }
        model.setVisible(false)
        print("Rendered production view: \(path)")
    }
}
#endif
