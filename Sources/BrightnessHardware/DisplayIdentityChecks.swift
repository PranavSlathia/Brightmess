#if DEBUG
import Foundation

/// Also runnable on CLT installations without the Swift Testing module.
public enum DisplayIdentityChecks {
    private final class ReadOnlyBackend: DisplayConnectionBackend {
        let native = NativeDisplayConnectionBackend()
        var attemptedWrites = 0
        var isAvailable: Bool { native.isAvailable }
        func candidates() throws -> [DisplayConnectionCandidate] { try native.candidates() }
        func isOnline(_ id: UInt32) -> Bool { native.isOnline(id) }
        func setEnabled(_ id: UInt32, _ enabled: Bool) -> Int32 { attemptedWrites += 1; return -999 }
    }

    /// Explicit read-only check of the C snapshot adapter against public live
    /// enumeration. Never called by the fake-display tests.
    public static func verifyNativeSnapshot() throws {
        struct Failed: Error { let message: String }
        let backend = ReadOnlyBackend()
        let slots = try backend.candidates()
        let online = ExternalDDCController().displays()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("br-readonly-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let ledger = DisplayRecoveryLedger(fileURL: tmp.appendingPathComponent("ledger.json"))
        let controller = DisplayConnectionController(ledger: ledger, backend: backend)
        for display in online {
            let resolved = try DisplayIdentityResolver.resolve(display, among: slots)
            guard resolved == display.displayID else { throw Failed(message: "Wrong native slot for " + display.name) }
            try ledger.record(display)
            guard try controller.reconnect(display) == display.displayID, backend.attemptedWrites == 0 else {
                throw Failed(message: "Already-online recovery tried a configuration transaction")
            }
        }
        print("Read-only native identity check passed: \(online.count) online display(s), \(slots.filter { !$0.online && !$0.hasLiveIdentity }.count) cached offline slot(s). No display writes.")
    }

    public static func run() throws {
        struct Failed: Error { let message: String }
        let known = ExternalDisplay(id: "samsung", displayID: 2, name: "LU28R55",
            vendorID: 19501, productID: 4118, serialNumber: 1129853751,
            edidUUID: "edid", ioLocation: "port-a", isMain: true, supportsStandby: true)
        func slot(_ id: UInt32, _ port: String, online: Bool = false, live: Bool = false, edid: String = "") -> DisplayConnectionCandidate {
            .init(displayID: id, vendorID: known.vendorID, productID: known.productID,
                  serialNumber: known.serialNumber, edidUUID: edid, ioLocation: port,
                  online: online, hasLiveIdentity: live)
        }
        func expect(_ slots: [DisplayConnectionCandidate], _ expected: UInt32?, _ message: String) throws {
            do {
                let actual = try DisplayIdentityResolver.resolve(known, among: slots)
                if actual != expected { throw Failed(message: message) }
            } catch is DisplayConnectionError {
                if expected != nil { throw Failed(message: message) }
            }
        }
        let ghost = slot(1, "old-port"), live = slot(2, "port-a", live: true, edid: "edid")
        try expect([ghost, live], 2, "stale offline slot falsely makes Samsung ambiguous")
        try expect([slot(2,"port-a"), slot(7,"new-port",online:true,live:true,edid:"edid")], 7, "hotplug changed numeric ID")
        try expect([slot(2,"old-port"),slot(8,"port-a")], 8, "disabled display must resolve by port, not old ID")
        try expect([live,slot(9,"port-b",live:true,edid:"edid")], 2, "cloned serial with known port")
        try expect([slot(9,"port-b",live:true,edid:"edid"),slot(10,"port-c",live:true,edid:"edid")], nil, "true ambiguity must fail closed")
        try expect([slot(2,"port-a",online:true,live:true,edid:"other")], nil, "reused slot identity mismatch")
        try expect([live,live], 2, "repeated row is not another monitor")
        try expect([slot(2,"old-port"),slot(4,"other-port")], nil, "never guess by numeric ID")
        print("8 display identity checks passed: ghosts, port changes, disabled slots, cloned serials, EDID mismatch, duplicate rows and ambiguity.")
    }
}
#endif
