#if DEBUG
import BrightnessCore
import BrightnessHardware
import Foundation

/// Replays the Samsung failure with fake displays only. No real display APIs,
/// user preferences, network peers, TV commands or Accessibility operations.
enum DisplayRecoveryChecks {
    private enum Failure: Error { case check(String) }
    private final class Desk: DisplayDriver, DisplayConnections, @unchecked Sendable {
        let samsung = ExternalDisplay(id: "Samsung", displayID: 2, name: "LU28R55",
            vendorID: 19501, productID: 4118, serialNumber: 1129853751,
            edidUUID: "samsung-edid", ioLocation: "port-a", isMain: true, supportsStandby: true)
        let tv = ExternalDisplay(id: "TV", displayID: 3, name: "Beyond TV",
            vendorID: 25368, productID: 10321, serialNumber: 65536,
            edidUUID: "tv-edid", ioLocation: "hdmi", isMain: false, supportsStandby: false)
        let ledger: DisplayRecoveryLedger
        let isAvailable = true
        private let lock = NSLock()
        private var attached = true
        private var writes: [(String, UInt16)] = []
        var samsungWrites: [UInt16] { lock.withLock { writes.filter { $0.0 == "Samsung" }.map(\.1) } }
        init(_ url: URL) { ledger = DisplayRecoveryLedger(fileURL: url) }
        func attach(_ value: Bool) { lock.withLock { attached = value } }
        func displays() -> [ExternalDisplay] { lock.withLock { attached ? [samsung, tv] : [tv] } }
        func set(percentage: UInt16, on display: ExternalDisplay) throws {
            lock.withLock { writes.append((display.id, percentage)) }
        }
        func readBrightness(of display: ExternalDisplay) throws -> DDCValue { throw Failure.check("No DDC readback") }
        func isOnline(_ display: ExternalDisplay) -> Bool { displays().contains { $0.id == display.id } }
        func disconnectedDisplays() -> [ExternalDisplay] { (try? ledger.records().map(\.display)) ?? [] }
        func disconnect(_ display: ExternalDisplay) throws { try ledger.record(display); attach(false) }
        func reconnect(_ display: ExternalDisplay) throws -> UInt32 { throw DisplayConnectionError.ambiguousIdentity(display.name) }
        func recoverAll() throws -> [DisplayRecoveryOutcome] { [] }
    }

    static func run() throws {
        func expect(_ b: @autoclosure () throws -> Bool, _ message: String) throws {
            if try !b() { throw Failure.check(message) }
        }
        let suite = "dev.pranav.recovery-test." + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: tmp) }
        let desk = Desk(tmp.appendingPathComponent("ledger.json"))
        let coordinator = DisplayCoordinator(hardware: desk, connection: desk, defaults: prefs)
        let curve = try BrightnessCurve(minimum: 0, maximum: 100)
        _ = try coordinator.applyAutomatic(target: 40, deadband: 2,
            sourceBrightness: 0.4, measuredAt: Date(), baseCurve: curve)
        coordinator.setConnected(false, displayID: "Samsung")
        try expect(coordinator.snapshot().first { $0.id == "Samsung" }?.connectionState == .disconnected, "Fixture did not disconnect")
        coordinator.setConnected(true, displayID: "Samsung")
        try expect(coordinator.snapshot().first { $0.id == "Samsung" }?.lastError?.contains("more than one") == true,
            "Fixture did not reproduce the actual reconnect error")
        let before = desk.samsungWrites.count
        desk.attach(true) // The user power-cycles and reconnects the cable.
        coordinator.refresh(readHardware: false)
        var recovered = coordinator.snapshot().first { $0.id == "Samsung" }
        try expect(recovered?.connectionState == .connected, "Replug did not restore connected status")
        try expect(recovered?.lastError == nil, "Replug retained the stale ambiguous reconnect error")
        let deadline = Date().addingTimeInterval(2)
        while desk.samsungWrites.count == before && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        recovered = coordinator.snapshot().first { $0.id == "Samsung" }
        try expect(desk.samsungWrites.count == before + 1 && desk.samsungWrites.last == 40,
            "Replug reused the old brightness cache instead of restoring the new IO route")
        try expect(recovered?.followsAutomatic == true, "Recovery disabled Follow Air")
        try expect(try desk.ledger.records().isEmpty, "Recovery record was not cleared")
        coordinator.refresh(readHardware: false)
        _ = coordinator.snapshot()
        try expect(desk.samsungWrites.count == before + 1, "A settled refresh rewrote hardware")
        coordinator.setFollowsAutomatic(false, displayID: "Samsung")
        coordinator.setManualBrightness(66, displayID: "Samsung", final: true)
        _ = coordinator.snapshot()
        let manualDeadline = Date().addingTimeInterval(2)
        while desk.samsungWrites.last != 66 && Date() < manualDeadline { Thread.sleep(forTimeInterval: 0.02) }
        try expect(desk.samsungWrites.last == 66, "Manual fixture did not settle")
        desk.attach(false) // An unexpected cable loss must not remove its card.
        coordinator.refresh(readHardware: false)
        try expect(coordinator.snapshot().first { $0.id == "Samsung" }?.connectionState == .disconnected,
            "A physical unplug made the known display card disappear")
        try expect(coordinator.snapshot().first { $0.id == "TV" }?.connectionState == .connected, "Recovery disturbed the TV")
        let manualWrites = desk.samsungWrites.count
        desk.attach(true)
        coordinator.refresh(readHardware: false)
        _ = coordinator.snapshot()
        let restoreDeadline = Date().addingTimeInterval(2)
        while desk.samsungWrites.count == manualWrites && Date() < restoreDeadline { Thread.sleep(forTimeInterval: 0.02) }
        let manual = coordinator.snapshot().first { $0.id == "Samsung" }
        try expect(manual?.followsAutomatic == false && manual?.brightness == 66 && desk.samsungWrites.count == manualWrites + 1,
            "Recovery overwrote the explicit manual level or enabled Follow Air")
        try expect(manual?.calibration.count == 0, "Replug learned a calibration match")
        print("Display recovery checks passed: stale error, rebuilt output, Follow/manual preservation, ledger, physical loss, independent TV, no accidental learning and zero idle writes.")
    }
}
#endif
