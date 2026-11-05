#if DEBUG
import Foundation

public enum DisplayConnectionChecks {
    private struct Failed: Error { let message: String }
    private final class Backend: DisplayConnectionBackend {
        let isAvailable = true
        var slots: [DisplayConnectionCandidate] = []
        var writes: [(UInt32, Bool)] = []
        var result: Int32 = 0
        var replacementID: UInt32?
        func candidates() throws -> [DisplayConnectionCandidate] { slots }
        func isOnline(_ id: UInt32) -> Bool { slots.contains { $0.displayID == id && $0.online } }
        func setEnabled(_ id: UInt32, _ enabled: Bool) -> Int32 {
            writes.append((id, enabled))
            guard result == 0, let i = slots.firstIndex(where: { $0.displayID == id }) else { return result }
            let old = slots[i]
            slots[i] = .init(displayID: replacementID ?? id, vendorID: old.vendorID, productID: old.productID,
                serialNumber: old.serialNumber, edidUUID: old.edidUUID, ioLocation: old.ioLocation,
                online: enabled, hasLiveIdentity: true)
            return 0
        }
    }

    public static func run() throws {
        func expect(_ b: @autoclosure () throws -> Bool, _ message: String) throws {
            if try !b() { throw Failed(message: message) }
        }
        let known = ExternalDisplay(id: "samsung", displayID: 2, name: "LU28R55", vendorID: 1,
            productID: 2, serialNumber: 3, edidUUID: "edid", ioLocation: "port-a", isMain: true, supportsStandby: true)
        func slot(_ id: UInt32, port: String = "port-a", online: Bool = false) -> DisplayConnectionCandidate {
            .init(displayID: id, vendorID: 1, productID: 2, serialNumber: 3,
                edidUUID: "edid", ioLocation: port, online: online, hasLiveIdentity: true)
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("br-connection-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let ledger = DisplayRecoveryLedger(fileURL: tmp.appendingPathComponent("ledger.json"))
        let backend = Backend()
        let controller = DisplayConnectionController(ledger: ledger, backend: backend)
        backend.slots = [slot(7, online: true)]
        try ledger.record(known)
        try expect(try controller.reconnect(known) == 7, "Already-online replug did not resolve the new ID")
        try expect(backend.writes.isEmpty && ledger.records().isEmpty, "Already-online reconnect committed a no-op or kept its ledger")

        backend.slots = [slot(2)]
        backend.replacementID = 8
        try ledger.record(known)
        try expect(try controller.reconnect(known) == 8, "Re-enable allocated a new ID, but recovery waited only for the old one")
        try expect(backend.writes.count == 1 && backend.writes[0].0 == 2 && backend.writes[0].1,
            "Recovery enabled an unrelated slot")
        try expect(try ledger.records().isEmpty, "Successful recovery kept the ledger")

        backend.slots = [slot(9, port: "other-a"), slot(10, port: "other-b")]
        backend.writes = []
        try ledger.record(known)
        do { _ = try controller.reconnect(known); throw Failed(message: "True ambiguity was accepted") }
        catch DisplayConnectionError.ambiguousIdentity {}
        try expect(try backend.writes.isEmpty && ledger.records().count == 1, "Ambiguity changed hardware or lost recovery data")
        do { try controller.disconnect(known); throw Failed(message: "Ambiguous disconnect was accepted") }
        catch DisplayConnectionError.ambiguousIdentity {}
        try expect(backend.writes.isEmpty, "Ambiguous disconnect changed hardware")

        backend.slots = [slot(2)]
        backend.result = 1001
        do { _ = try controller.reconnect(known); throw Failed(message: "Failed commit was reported as connected") }
        catch DisplayConnectionError.operationFailed(_, let code) {
            try expect(code == 1001, "Commit failure lost its error code")
        }
        try expect(try ledger.records().count == 1 && backend.writes.count == 3,
            "Failed commit lost recovery or retried without a bound")
        print("Display controller checks passed: online no-op, new slot after enable, ambiguity refusal, failed commit and durable recovery.")
    }
}
#endif
