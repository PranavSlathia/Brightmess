import Foundation
import Testing
@testable import BrightnessCore

@Test func sourceButtonsNeedAQualifiedRoundTrip() {
    var p = MonitorSourceProfile()
    #expect(!p.canActivate(.displayPort, location: "port"))
    p.observeReturn(15, location: "port")
    #expect(p.canActivate(.displayPort, location: "port"))
    #expect(!p.canActivate(.hdmi1, location: "port"))
    let rejected = p.qualify(.hdmi1, proof: .init(targetCode: 17, returnCode: 18, ioLocation: "port"))
    #expect(!rejected)
    let accepted = p.qualify(.hdmi1, proof: .init(targetCode: 17, returnCode: 15, ioLocation: "port"))
    #expect(accepted)
    #expect(p.canActivate(.hdmi1, location: "port"))
    #expect(!p.canActivate(.hdmi1, location: "other-port"))
    #expect(!p.canActivate(.hdmi2, location: "port"))
}

@Test func changingMappingsInvalidatesProofButRenamingDoesNot() {
    var p = MonitorSourceProfile()
    p.observeReturn(15, location: "port")
    let qualified = p.qualify(.hdmi1, proof: .init(targetCode: 17, returnCode: 15, ioLocation: "port"))
    #expect(qualified)
    let renamed = p.configure(.hdmi1, name: "MacBook Air", code: 17)
    #expect(renamed)
    #expect(p.canActivate(.hdmi1, location: "port"))
    let remapped = p.configure(.hdmi1, name: "MacBook Air", code: 5)
    #expect(remapped)
    #expect(!p.canActivate(.hdmi1, location: "port"))
    let duplicate = p.configure(.hdmi2, name: "Duplicate", code: 5)
    let empty = p.configure(.hdmi2, name: "", code: 18)
    let control = p.configure(.hdmi2, name: "Control\nname", code: 18)
    let outsideRange = p.configure(.hdmi2, name: "Outside range", code: 300)
    #expect(!duplicate && !empty && !control && !outsideRange)
}

@Test func hardwareFreshnessRequiresAValidReadingAfterTheLatestWrite() {
    let t = Date(timeIntervalSince1970: 100)
    #expect(HardwareReadbackPolicy.isFresh(readAt: t, lastWriteAt: nil, now: t.addingTimeInterval(5)))
    #expect(!HardwareReadbackPolicy.isFresh(readAt: t, lastWriteAt: t.addingTimeInterval(1), now: t.addingTimeInterval(5)))
    #expect(!HardwareReadbackPolicy.isFresh(readAt: t, lastWriteAt: nil, now: t.addingTimeInterval(16)))
    #expect(!HardwareReadbackPolicy.isFresh(readAt: nil, lastWriteAt: nil, now: t))
    #expect(!HardwareReadbackPolicy.isFresh(readAt: t.addingTimeInterval(100), lastWriteAt: nil, now: t))
}
