import Foundation
import Testing
@testable import BrightnessHardware

private let panel = ExternalDisplay(id: "samsung", displayID: 2, name: "LU28R55",
    vendorID: 19501, productID: 4118, serialNumber: 1129853751,
    edidUUID: "samsung-edid", ioLocation: "port-a", isMain: true, supportsStandby: true)

private func candidate(_ id: UInt32, port: String, online: Bool = false,
                       live: Bool = false, edid: String = "") -> DisplayConnectionCandidate {
    .init(displayID: id, vendorID: panel.vendorID, productID: panel.productID,
          serialNumber: panel.serialNumber, edidUUID: edid, ioLocation: port,
          online: online, hasLiveIdentity: live)
}

@Test func actualRecoveryControllerHandlesHotplugAndRefusesUnsafeTargets() throws {
    try DisplayConnectionChecks.run()
}

@Test func reconnectIgnoresStaleSlotAfterPortChange() throws {
    let ghost = candidate(1, port: "old-port")
    let current = candidate(2, port: "port-a", live: true, edid: "samsung-edid")
    #expect(try DisplayIdentityResolver.resolve(panel, among: [ghost, current]) == 2)
}

@Test func replugAlreadyOnlineIsNotAmbiguous() throws {
    let ghost = candidate(2, port: "port-a")
    let moved = candidate(7, port: "new-port", online: true, live: true, edid: "samsung-edid")
    #expect(try DisplayIdentityResolver.resolve(panel, among: [ghost, moved]) == 7)
}

@Test func disabledDisplayResolvesBySavedPortNotTransientID() throws {
    let ghost = candidate(2, port: "old-port")
    let disabled = candidate(8, port: "port-a")
    #expect(try DisplayIdentityResolver.resolve(panel, among: [ghost, disabled]) == 8)
}

@Test func clonedSerialsStillRequireAnUnambiguousPort() throws {
    let a = candidate(8, port: "port-a", live: true, edid: "samsung-edid")
    let b = candidate(9, port: "port-b", live: true, edid: "samsung-edid")
    #expect(try DisplayIdentityResolver.resolve(panel, among: [a, b]) == 8)
    #expect(throws: DisplayConnectionError.self) {
        try DisplayIdentityResolver.resolve(panel, among: [b, candidate(10, port: "port-c", live: true, edid: "samsung-edid")])
    }
}

@Test func reusedSlotWithDifferentLiveEDIDIsNeverSelected() {
    #expect(throws: DisplayConnectionError.self) {
        try DisplayIdentityResolver.resolve(panel, among: [candidate(2, port: "port-a", online: true, live: true, edid: "different-edid")])
    }
}

@Test func repeatedSlotIsOneCandidate() throws {
    let a = candidate(2, port: "port-a", live: true, edid: "samsung-edid")
    #expect(try DisplayIdentityResolver.resolve(panel, among: [a, a]) == 2)
}

@Test func unknownGhostSlotsNeverFallBackToTheOldNumericID() {
    #expect(throws: DisplayConnectionError.self) {
        try DisplayIdentityResolver.resolve(panel, among: [candidate(2, port: "old-port"), candidate(4, port: "other-port")])
    }
}
