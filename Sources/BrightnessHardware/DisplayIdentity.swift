import CPrivateDisplay
import Foundation

/// A WindowServer slot is not necessarily a currently attached monitor. The
/// server keeps old slots after cable/port changes, sometimes with identical
/// vendor/model/serial values and an all-zero system UUID.
struct DisplayConnectionCandidate: Equatable, Sendable {
    let displayID: UInt32
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32
    let edidUUID: String
    let ioLocation: String
    let online: Bool
    let hasLiveIdentity: Bool
}

enum DisplayIdentityResolver {
    static func resolve(_ display: ExternalDisplay, among candidates: [DisplayConnectionCandidate]) throws -> UInt32 {
        let matches = candidates.filter {
            $0.vendorID == display.vendorID && $0.productID == display.productID && $0.serialNumber == display.serialNumber &&
            (!($0.online || $0.hasLiveIdentity) || $0.edidUUID.isEmpty || display.edidUUID.isEmpty ||
             $0.edidUUID.caseInsensitiveCompare(display.edidUUID) == .orderedSame)
        }
        guard !matches.isEmpty else { throw DisplayConnectionError.displayNotFound(display.name) }
        // Merge repeated rows by ID, retaining the strongest current evidence.
        let unique = Dictionary(grouping: matches, by: \.displayID).values.compactMap { rows in
            rows.max { ($0.online ? 2 : ($0.hasLiveIdentity ? 1 : 0)) < ($1.online ? 2 : ($1.hasLiveIdentity ? 1 : 0)) }
        }
        let live = unique.filter { $0.online || $0.hasLiveIdentity }
        let eligible = live.isEmpty ? unique : live
        // A live endpoint outranks a cached location after a cable/port move.
        // When macOS has hidden EDID for a disabled screen, its recorded IO
        // location can still select the correct slot. Never trust an old ID.
        if !display.ioLocation.isEmpty {
            let samePort = eligible.filter { $0.ioLocation == display.ioLocation }
            if samePort.count == 1 { return samePort[0].displayID }
        }
        guard eligible.count == 1 else { throw DisplayConnectionError.ambiguousIdentity(display.name) }
        return eligible[0].displayID
    }
}

protocol DisplayConnectionBackend {
    var isAvailable: Bool { get }
    func candidates() throws -> [DisplayConnectionCandidate]
    func isOnline(_ displayID: UInt32) -> Bool
    func setEnabled(_ displayID: UInt32, _ enabled: Bool) -> Int32
}

struct NativeDisplayConnectionBackend: DisplayConnectionBackend {
    var isAvailable: Bool { BRDisplayConnectionAvailable() != 0 }
    func candidates() throws -> [DisplayConnectionCandidate] {
        var raw = [BRDisplayConnectionCandidate](repeating: BRDisplayConnectionCandidate(), count: 32)
        let count = raw.withUnsafeMutableBufferPointer { BRDisplayCopyConnectionCandidates($0.baseAddress, UInt32($0.count)) }
        guard count >= 0 else {
            if count == -100 { throw DisplayConnectionError.privateAPIUnavailable }
            throw DisplayConnectionError.operationFailed("Read display slots", count)
        }
        return raw.prefix(min(Int(count), raw.count)).map {
            .init(displayID: $0.display.displayID, vendorID: $0.display.vendorID,
                  productID: $0.display.productID, serialNumber: $0.display.serialNumber,
                  edidUUID: ExternalDDCController.string(from: $0.display.edidUUID),
                  ioLocation: ExternalDDCController.string(from: $0.display.ioLocation),
                  online: $0.online != 0, hasLiveIdentity: $0.hasLiveIdentity != 0)
        }
    }
    func isOnline(_ displayID: UInt32) -> Bool { BRDisplayIsOnline(displayID) != 0 }
    func setEnabled(_ displayID: UInt32, _ enabled: Bool) -> Int32 { BRDisplaySetEnabled(displayID, enabled ? 1 : 0) }
}
