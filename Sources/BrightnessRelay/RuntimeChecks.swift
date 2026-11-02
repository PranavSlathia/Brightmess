#if DEBUG
import BrightnessCore
import BrightnessHardware
import Foundation

/// Full loopback exercise of both real relay processes' logic without a physical
/// write, user defaults, pairing secret, or real network peer.
enum RuntimeChecks {
    enum Failed: Error { case check(String) }
    private final class Displays: DisplayDriver, @unchecked Sendable {
        let panels = ["Samsung", "TV"].enumerated().map { i, name in
            ExternalDisplay(id: name, displayID: UInt32(40000+i), name: name, vendorID: 1,
                productID: UInt32(i), serialNumber: 0, edidUUID: name, ioLocation: "", isMain: i == 0, supportsStandby: false)
        }
        let lock = NSLock()
        private var writes: [(Double,UInt16)] = []
        var record: [(Double,UInt16)] { lock.withLock { writes } }
        func displays() -> [ExternalDisplay] { panels }
        func readBrightness(of display: ExternalDisplay) throws -> DDCValue { throw Failed.check("no readback") }
        func set(percentage: UInt16, on display: ExternalDisplay) throws {
            if display.id == "TV" { throw Failed.check("software-only fixture") }
            lock.withLock { writes.append((ProcessInfo.processInfo.systemUptime, percentage)) }
        }
    }

    @MainActor private final class Sensors: AirSensors {
        var callback: (@convention(c) () -> Void)?
        var level = 0.5, lux = 40.0, cct = 5400.0, closed = false, reads = 0
        func observe(_ cb: @convention(c) () -> Void) -> Bool { callback = cb; return true }
        func stop() { callback = nil }
        func ambient() -> AmbientSample { reads += 1; return AmbientSample(lux: lux, kelvin: cct, lidClosed: closed) }
        func brightness() throws -> Double { level }
    }

    @MainActor static func run() async throws {
        func expect(_ test: @autoclosure () -> Bool, _ message: String) throws {
            if !test() { throw Failed.check(message) }
        }
        func wait(_ condition: () -> Bool, _ message: String, timeout: Double = 4) async throws {
            let start = ProcessInfo.processInfo.systemUptime
            while !condition() {
                if ProcessInfo.processInfo.systemUptime - start > timeout { throw Failed.check(message) }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
        }
        let suite = "dev.pranav.relay.test." + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        try DeskWindows.checkShortcutConflict(prefs)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { prefs.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: tmp) }
        let driver = Displays()
        let coordinator = DisplayCoordinator(hardware: driver,
            connection: DisplayConnectionController(ledger: DisplayRecoveryLedger(fileURL: tmp.appendingPathComponent("ledger"))), defaults: prefs)
        let auth = try RelayAuthenticator(token: Data(repeating: 1, count: 32))
        let server = try RelayHTTPServer(port: 0, authenticator: auth, displayCoordinator: coordinator,
            curve: try BrightnessCurve(minimum: 0, maximum: 100), loopbackOnly: true)
        try await server.start()
        guard let port = server.boundPort else { throw Failed.check("listener") }
        let client = try RelayClient(host: "127.0.0.1", port: port, authenticator: auth)
        try await client.send(brightness: 0.4, source: "old Air")
        func status() async throws -> [String:Any] {
            try JSONSerialization.jsonObject(with: Data((try await client.status()).utf8)) as? [String:Any] ?? [:]
        }
        var st = try await status()
        try expect(st["sourceMode"] as? String == "scheduled", "legacy compatibility")
        let sensors = Sensors(), live = LiveAirSource(client: client, name: "fixture", sensors: sensors)
        let task = Task { await live.run() }
        defer { task.cancel() }
        func at(_ n: UInt16) -> Bool { coordinator.snapshot().allSatisfy { $0.brightness == n } }
        try await wait({at(50)}, "initial live sync")
        let burstStart = ProcessInfo.processInfo.systemUptime
        let preBurstWrites = driver.record.count
        sensors.level = 0.1; sensors.callback?()
        sensors.level = 0.25; sensors.callback?()
        sensors.level = 0.36; sensors.callback?()
        try await wait({driver.record.count > preBurstWrites}, "first adjustment exceeded 1s", timeout: 1)
        let firstWrite = driver.record[preBurstWrites].0 - burstStart
        try expect(firstWrite < 1, "first adjustment late")
        print(String(format: "First simulated hardware adjustment: %.0f ms", firstWrite*1000))
        try await wait({at(36)}, "burst lost final target")
        sensors.level = 0.76 // no callback: exercise the real two-second watchdog
        try await wait({at(76)}, "missed callback not recovered", timeout: 5)
        coordinator.beginSlider("Samsung")
        coordinator.setManualBrightness(43, displayID: "Samsung", final: true)
        try await wait({coordinator.snapshot().first{$0.id=="Samsung"}?.calibration.count == 1}, "slider did not learn")
        try expect(coordinator.snapshot().allSatisfy(\.followsAutomatic), "slider disabled Auto")
        try expect(coordinator.snapshot().first{$0.id=="TV"}?.calibration.count == 0, "learned wrong panel")
        coordinator.adjustManualBrightness(direction: .down, fine: true)
        try await wait({coordinator.snapshot().allSatisfy{$0.calibration.count == 1}}, "key learning")
        try expect(coordinator.snapshot().first{$0.id=="Samsung"}?.brightness == 42,
                   "key immediately after slider stepped from the old hardware value")
        coordinator.editCurve(displayID: "TV", reset: false)
        try expect(coordinator.snapshot().first{$0.id=="TV"}?.calibration.count == 0, "undo")
        let frozen = driver.record.count
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let settled = driver.record.count
        try await Task.sleep(nanoseconds: 2_200_000_000)
        try expect(driver.record.count == settled && settled >= frozen, "idle DDC writes")
        let records = driver.record
        try expect(zip(records, records.dropFirst()).allSatisfy { $1.0-$0.0 >= 0.249 }, "DDC rate exceeded")
        live.sleep()
        try await Task.sleep(nanoseconds: 500_000_000)
        st = try await status()
        try expect(st["sourceState"] as? String == "Air asleep", "explicit sleep not reported")
        let reads = sensors.reads
        try await Task.sleep(nanoseconds: 2_100_000_000)
        try expect(sensors.reads == reads, "sensor accessed while asleep")
        sensors.closed = true; live.startObserving()
        try await Task.sleep(nanoseconds: 500_000_000)
        st = try await status()
        try expect(st["sourceState"] as? String == "Lid closed", "closed lid not reported")
        sensors.closed = false; sensors.level = 0.5; sensors.cct = 4100
        try await client.sendControl(.syncNow)
        try await wait({coordinator.snapshot().first{$0.id=="TV"}?.brightness == 50}, "wake/pull recovery")
        st = try await status()
        try expect(st["sourceState"] as? String == "Live" && st["airBrightnessPercent"] as? Int == 50, "source not live")
        // A later HTTP request carrying an earlier sequence must not mutate state.
        guard let rawSession = st["sourceSession"] as? String, let id = UUID(uuidString: rawSession) else { throw Failed.check("session missing") }
        do {
            try await client.send(brightness: 1, source: "fixture",
                metadata: SourceMetadata(session: id, sequence: 1, measuredAt: Date().timeIntervalSince1970, state: .awake))
            throw Failed.check("reordered HTTP sample accepted")
        } catch HTTPRelayError.rejected(409, _) {}
        st = try await status()
        try expect(st["airBrightnessPercent"] as? Int == 50, "reordered sample changed freshness/state")
        // Stop the actual loopback listener. The Air must keep only the newest
        // reading during connection refusal, even while its retries back off.
        server.stopSimulationListener()
        try await Task.sleep(nanoseconds: 300_000_000)
        sensors.level = 0.05; sensors.callback?()
        try await Task.sleep(nanoseconds: 450_000_000)
        sensors.level = 0.9; sensors.callback?()
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let restored = try RelayHTTPServer(port: port, authenticator: auth, displayCoordinator: coordinator,
            curve: try BrightnessCurve(minimum: 0, maximum: 100), loopbackOnly: true)
        let panel = BrightnessMenuModel(server: restored)
        restored.setOnPresence { [weak panel] value, solar in
            DispatchQueue.main.async { panel?.setPresence(value, solar: solar) }
        }
        try await restored.start()
        defer { restored.stopSimulationListener() }
        try await wait({coordinator.snapshot().first{$0.id=="TV"}?.brightness == 90}, "reconnect lost latest sample", timeout: 8)
        st = try await status()
        try expect(st["airBrightnessPercent"] as? Int == 90, "offline backlog replayed")
        let beforeEdit = coordinator.snapshot().first{$0.id=="TV"}!.calibration.count
        coordinator.beginSlider("TV")
        sensors.level = 0.7; sensors.callback?()
        try await wait({coordinator.snapshot().first{$0.id=="TV"}?.mappedTarget == 70}, "new Air target during gesture")
        coordinator.setManualBrightness(11, displayID: "TV", final: true)
        let tv = coordinator.snapshot().first{$0.id=="TV"}!
        try expect(tv.calibration.count == beforeEdit && tv.learningNote?.hasPrefix("Not learned") == true,
                   "moving Air became permanent preference")
        coordinator.setFollowsAutomatic(false, displayID: "TV")
        coordinator.setManualBrightness(23, displayID: "TV", final: true)
        try expect(coordinator.snapshot().first{$0.id=="TV"}?.followsAutomatic == false, "explicit manual changed to Auto")
        // Use the popover's real action routes; per-panel buttons must never
        // inherit the Magic Keyboard's group targeting.
        panel.requestAirSync()
        try await wait({panel.justSynced && !panel.isSyncing}, "Sync now did not acknowledge the fresh Air reading")
        let samsungBefore = coordinator.snapshot().first { $0.id == "Samsung" }!.brightness!
        panel.step(.up, id: "TV")
        try await wait({coordinator.snapshot().first { $0.id == "TV" }?.brightness == 29}, "TV plus button")
        try expect(coordinator.snapshot().first { $0.id == "Samsung" }?.brightness == samsungBefore, "TV button moved Samsung")
        panel.step(.down, id: "TV")
        try await wait({coordinator.snapshot().first { $0.id == "TV" }?.brightness == 23}, "TV minus button")
        panel.setFollowsAutomatic(true, displayID: "TV")
        try await wait({coordinator.snapshot().first { $0.id == "TV" }?.brightness == 70}, "Follow Air button")
        panel.toggleDetails("TV")
        try expect(panel.detailedDisplay == "TV", "Details did not expand")
        panel.toggleDetails("TV")
        try expect(panel.detailedDisplay == nil, "Details did not collapse")
        try expect(DeskDisplayShape.identify(name: "Beyond TV", portrait: false) == .television &&
                   DeskDisplayShape.identify(name: "LU28R55", portrait: true) == .portraitMonitor &&
                   DeskDisplayShape.identify(name: "Secondary LCD", portrait: false) == .monitor,
                   "secondary monitor mislabeled as television")
        print("Panel checks passed: per-display +/−, Follow Air, disclosure, device classification.")
        print("Loopback checks passed: scheduled/live, burst, watchdog, learn/undo, bounded fade, idle, sleep/lid, Sync Now, ordering, transport loss/recovery, unstable gesture, explicit manual.")
    }
}
#endif
