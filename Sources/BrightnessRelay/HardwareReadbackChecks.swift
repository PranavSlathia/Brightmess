#if DEBUG
import BrightnessCore
import BrightnessHardware
import Foundation

enum HardwareReadbackChecks {
    private struct Failure: Error { let message: String }
    private final class Desk: DisplayDriver, DisplayConnections, @unchecked Sendable {
        let panel = ExternalDisplay(id: "readback-panel", displayID: 62001, name: "Fixture monitor", vendorID: 1,
            productID: 1, serialNumber: 1, edidUUID: "readback-edid", ioLocation: "fixture", isMain: true, supportsStandby: false)
        let ledger: DisplayRecoveryLedger
        let isAvailable = false
        private let lock = NSLock()
        private var value: UInt16 = 52
        private var reads = 0, writes = 0
        var failReads = false, ignoreWrites = false
        var counts: (Int,Int) { lock.withLock { (reads,writes) } }
        init(_ url: URL) { ledger = .init(fileURL: url) }
        func displays() -> [ExternalDisplay] { [panel] }
        func set(percentage: UInt16, on display: ExternalDisplay) throws {
            lock.withLock { writes += 1; if !ignoreWrites { value = percentage } }
        }
        func readBrightness(of display: ExternalDisplay) throws -> DDCValue {
            try lock.withLock { reads += 1; if failReads { throw Failure(message: "Null reply") }; return DDCValue(current: value, maximum: 100) }
        }
        func isOnline(_ display: ExternalDisplay) -> Bool { true }
        func disconnectedDisplays() -> [ExternalDisplay] { [] }
        func disconnect(_ display: ExternalDisplay) throws { throw Failure(message: "No real operations") }
        func reconnect(_ display: ExternalDisplay) throws -> UInt32 { throw Failure(message: "No real operations") }
        func recoverAll() throws -> [DisplayRecoveryOutcome] { [] }
    }
    static func run() async throws {
        func expect(_ b: @autoclosure () -> Bool, _ m: String) throws { if !b() { throw Failure(message: m) } }
        func wait(_ condition: () -> Bool) async throws {
            let limit = ContinuousClock.now + .seconds(3)
            while !condition() {
                if ContinuousClock.now > limit { throw Failure(message: "Readback fixture stalled") }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        let suite = "dev.pranav.readback-test." + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: tmp) }
        let desk = Desk(tmp.appendingPathComponent("ledger"))
        let prefix = "dev.pranav.brightness-relay.display." + desk.panel.id + "."
        prefs.set(100, forKey: prefix + "lastBrightness")
        prefs.set("hardwareDDC", forKey: prefix + "controlMethod")
        let coordinator = DisplayCoordinator(hardware: desk, connection: desk, defaults: prefs)
        coordinator.refresh()
        var state = coordinator.snapshot()[0]
        try expect(state.brightness == 52 && state.hardwareBrightness == 52 && state.hardwareReadingIsFresh(at: Date()),
            "Cached 100% was not replaced by measured 52%")
        coordinator.setFollowsAutomatic(false, displayID: desk.panel.id)
        coordinator.setManualBrightness(68, displayID: desk.panel.id, final: true)
        try await wait { coordinator.snapshot()[0].hardwareBrightness == 68 }
        state = coordinator.snapshot()[0]
        try expect(state.hardwareReadingIsFresh(at: Date()) && !state.followsAutomatic && state.calibration.count == 0,
            "Verification changed manual/learning state")
        let settled = desk.counts
        try await Task.sleep(nanoseconds: 350_000_000)
        try expect(desk.counts == settled, "Closed-menu steady output triggered reads or writes")
        desk.failReads = true
        coordinator.refresh(); state = coordinator.snapshot()[0]
        try expect(state.readingKind(at: Date()) == .staleHardware && !state.hardwareReadingIsFresh(at: Date()),
            "Failed read was presented as live")
        let afterFailure = desk.counts
        for _ in 0..<5 { coordinator.refreshReadbacksIfDue() }
        _ = coordinator.snapshot()
        try expect(desk.counts == afterFailure, "Failed reads did not back off")
        desk.failReads = false; desk.ignoreWrites = true
        coordinator.setManualBrightness(90, displayID: desk.panel.id, final: true)
        try await wait { coordinator.snapshot()[0].brightness == 68 && coordinator.snapshot()[0].brightnessOrigin == .liveHardware }
        try expect(coordinator.snapshot()[0].hardwareBrightness == 68, "Write acknowledgement became measured 90%")
        let ignored = desk.counts
        try await Task.sleep(nanoseconds: 350_000_000)
        try expect(desk.counts == ignored, "Verification created a write/read retry loop")
        print("Hardware readback checks passed: cache correction, settled verification, freshness, failed-read backoff, manual preservation and zero idle retry loops.")
    }
}
#endif
