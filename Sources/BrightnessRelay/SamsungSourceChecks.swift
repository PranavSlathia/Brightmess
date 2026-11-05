#if DEBUG
import BrightnessCore
import BrightnessHardware
import Foundation

@MainActor enum SamsungSourceChecks {
    private struct Failure: Error { let message: String }
    private final class Desk: DisplayDriver, DisplayConnections, @unchecked Sendable {
        let samsung = ExternalDisplay(id: "source-samsung", displayID: 60001, name: "LU28R55",
            vendorID: 0x4c2d, productID: 0x1016, serialNumber: 1, edidUUID: "fixture-edid",
            ioLocation: "fixture-dp", isMain: true, supportsStandby: true)
        let tv = ExternalDisplay(id: "source-tv", displayID: 60002, name: "TV", vendorID: 2,
            productID: 2, serialNumber: 2, edidUUID: "fixture-tv", ioLocation: "fixture-hdmi", isMain: false, supportsStandby: false)
        let ledger: DisplayRecoveryLedger
        let isAvailable = true
        private let lock = NSLock()
        var offline = false, ignoreInput = false, failReturn = false, throwAfterAway = false
        private var input: UInt16 = 15
        private var commands: [UInt16] = []
        var sent: [UInt16] { lock.withLock { commands } }
        init(_ url: URL) { ledger = .init(fileURL: url) }
        func displays() -> [ExternalDisplay] { [samsung, tv] }
        func isOnline(_ display: ExternalDisplay) -> Bool { true }
        func disconnectedDisplays() -> [ExternalDisplay] { [] }
        func disconnect(_ display: ExternalDisplay) throws { throw Failure(message: "Sources must never disconnect") }
        func reconnect(_ display: ExternalDisplay) throws -> UInt32 { throw Failure(message: "Sources must never reconnect") }
        func recoverAll() throws -> [DisplayRecoveryOutcome] { [] }
        func set(percentage: UInt16, on display: ExternalDisplay) throws { throw Failure(message: "Sources must never change brightness") }
        func readBrightness(of display: ExternalDisplay) throws -> DDCValue { throw Failure(message: "No fixture brightness") }
        func readInput(of display: ExternalDisplay) throws -> UInt16 {
            try lock.withLock { if offline { throw Failure(message: "Offline") }; return input }
        }
        func setInput(_ value: UInt16, on display: ExternalDisplay) throws {
            try lock.withLock {
                guard display.id == samsung.id, !offline, !(failReturn && value == 15) else { throw Failure(message: "No verified channel") }
                commands.append(value); if !ignoreInput { input = value }
                if throwAfterAway && value != 15 { throw Failure(message: "Uncertain transport result after write") }
            }
        }
    }

    static func run() async throws {
        func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw Failure(message: message) }
        }
        func settle(_ sources: SamsungSources) async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            while sources.busy {
                if ContinuousClock.now > deadline { throw Failure(message: "Source fixture stalled") }
                await Task.yield()
            }
        }
        let suite = "dev.pranav.sources-test." + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: tmp) }
        let desk = Desk(tmp.appendingPathComponent("ledger"))
        let coordinator = DisplayCoordinator(hardware: desk, connection: desk, defaults: prefs)
        let sources = SamsungSources(coordinator: coordinator, defaults: prefs, delay: { _ in await Task.yield() })
        sources.updateDisplays(coordinator.snapshot())
        sources.activate(.hdmi1)
        try expect(desk.sent.isEmpty, "Unqualified source sent a command")
        sources.refresh(); try await settle(sources)
        try expect(sources.inputValue == 15 && sources.canActivate(.displayPort), "DP observation")
        sources.test(.hdmi1, sourceConnected: false, recoveryReady: true)
        try expect(desk.sent.isEmpty, "Test without HDMI source was accepted")
        sources.test(.hdmi1, sourceConnected: true, recoveryReady: true); try await settle(sources)
        try expect(desk.sent == [17,15] && !sources.canActivate(.hdmi1), "Round trip or physical confirmation gate")
        guard let pending = sources.pending else { throw Failure(message: "No pending physical proof") }
        sources.confirm(pending.token, sawBothPictures: true)
        try expect(sources.canActivate(.hdmi1) && !sources.canActivate(.hdmi2), "Proof affected wrong source")
        sources.activate(.hdmi1); try await settle(sources)
        sources.activate(.displayPort); try await settle(sources)
        try expect(desk.sent == [17,15,17,15], "Qualified source round trip")
        desk.offline = true
        let count = desk.sent.count
        sources.activate(.hdmi1); try await settle(sources)
        desk.offline = false
        sources.refresh(); try await settle(sources)
        try expect(desk.sent.count == count, "Offline source command replayed after recovery")
        sources.revoke(.hdmi1); desk.ignoreInput = true
        sources.test(.hdmi1, sourceConnected: true, recoveryReady: true); try await settle(sources)
        try expect(sources.pending == nil && !sources.canActivate(.hdmi1), "Ignored HDMI key offered physical qualification")
        desk.ignoreInput = false; desk.failReturn = true
        sources.test(.hdmi1, sourceConnected: true, recoveryReady: true); try await settle(sources)
        try expect(sources.pending == nil && !sources.canActivate(.hdmi1) && sources.notice.contains("JOG"), "Failed return enabled the source")

        desk.failReturn = false; try desk.setInput(15, on: desk.samsung)
        desk.throwAfterAway = true
        sources.test(.hdmi1, sourceConnected: true, recoveryReady: true); try await settle(sources)
        try expect(sources.pending == nil && !sources.canActivate(.hdmi1) && sources.notice.contains("unknown") && sources.notice.contains("JOG"),
            "An uncertain outbound write was falsely described as no source change")
        desk.throwAfterAway = false

        var gate: CheckedContinuation<Void, Never>?
        desk.failReturn = false
        try desk.setInput(15, on: desk.samsung) // Reset fake state only.
        let cancel = SamsungSources(coordinator: coordinator, defaults: prefs, delay: { _ in
            await withCheckedContinuation { gate = $0 }
        })
        cancel.updateDisplays(coordinator.snapshot()); cancel.refresh(); try await settle(cancel)
        cancel.test(.hdmi1, sourceConnected: true, recoveryReady: true)
        let deadline = ContinuousClock.now + .seconds(3)
        while gate == nil { if ContinuousClock.now > deadline { throw Failure(message: "Cancellation fixture stalled") }; await Task.yield() }
        let beforeStop = desk.sent.count
        cancel.stop(); gate?.resume(); gate = nil
        for _ in 0..<30 { await Task.yield() }
        try expect(desk.sent.count == beforeStop && cancel.pending == nil, "Cancelled source test replayed a command")
        print("Samsung source checks passed: qualification, physical gate, independent ports, offline no-replay, ignored commands, uncertain writes, failed return and cancellation.")
    }
}
#endif
