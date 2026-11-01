import Foundation
import Testing
@testable import BrightnessCore

@Test func curveClampsAndMapsEndpoints() throws {
    let curve = try BrightnessCurve(minimum: 20, maximum: 90, gamma: 1)
    #expect(curve.map(normalized: -1) == 20)
    #expect(curve.map(normalized: 0.5) == 55)
    #expect(curve.map(normalized: 2) == 90)
}

@Test func curveAppliesGamma() throws {
    let curve = try BrightnessCurve(minimum: 0, maximum: 100, gamma: 2)
    #expect(curve.map(normalized: 0.5) == 25)
}

@Test func signaturesRejectTampering() throws {
    let token = Data(repeating: 0xA5, count: 32)
    let authenticator = try RelayAuthenticator(token: token)
    let body = Data("payload".utf8)
    let signature = authenticator.signature(for: body)
    #expect(authenticator.verify(signature: signature, body: body))
    #expect(!authenticator.verify(signature: signature, body: Data("tampered".utf8)))
}

@Test func replayGuardRejectsOldAndRepeatedPackets() throws {
    let now = 1_000.0
    let valid = try BrightnessEnvelope(
        brightness: 0.5,
        sentAt: now,
        nonce: "nonce",
        source: "air"
    )
    var guardrail = ReplayGuard(maximumClockSkew: 30)
    try guardrail.validate(valid, now: now)
    #expect(throws: RelayProtocolError.replayedEnvelope) {
        try guardrail.validate(valid, now: now + 1)
    }

    let stale = try BrightnessEnvelope(
        brightness: 0.5,
        sentAt: now - 31,
        nonce: "other",
        source: "air"
    )
    #expect(throws: RelayProtocolError.staleEnvelope) {
        try guardrail.validate(stale, now: now)
    }
}

@Test func pullWaitEnvelopesUseTheSameReplayProtection() throws {
    let now = 2_000.0
    let envelope = try PullWaitEnvelope(sentAt: now, nonce: "pull-nonce", source: "air")
    var guardrail = ReplayGuard(maximumClockSkew: 30)
    try guardrail.validate(envelope, now: now)
    #expect(throws: RelayProtocolError.replayedEnvelope) {
        try guardrail.validate(envelope, now: now + 1)
    }
}

@Test func solarCurveIsSmoothAndBounded() {
    let curve = SolarBrightnessCurve()
    #expect(curve.normalizedBrightness(solarAltitude: -20) == 0.18)
    #expect(curve.normalizedBrightness(solarAltitude: -6) == 0.18)
    #expect(curve.normalizedBrightness(solarAltitude: 10) == 0.42)
    #expect(curve.normalizedBrightness(solarAltitude: 45) == 0.78)
    #expect(curve.normalizedBrightness(solarAltitude: 80) == 0.78)

    let samples = stride(from: -20.0, through: 80, by: 1).map {
        curve.normalizedBrightness(solarAltitude: $0)
    }
    #expect(samples.allSatisfy { (0 ... 1).contains($0) })
    #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
}

@Test func brightnessKeysUseNativeSizedAndFineSteps() {
    #expect(BrightnessStepPolicy.next(from: 50, direction: .up) == 56)
    #expect(BrightnessStepPolicy.next(from: 50, direction: .down) == 44)
    #expect(BrightnessStepPolicy.next(from: 50, direction: .up, fine: true) == 51)
    #expect(BrightnessStepPolicy.next(from: 50, direction: .down, fine: true) == 49)
    #expect(BrightnessStepPolicy.next(from: 98, direction: .up) == 100)
    #expect(BrightnessStepPolicy.next(from: 2, direction: .down) == 0)
}

@Test func disconnectPolicyNeverStrandsTheUser() {
    #expect(DisplayConnectionPolicy.canDisconnect(connectedDisplayCount: 2))
    #expect(!DisplayConnectionPolicy.canDisconnect(connectedDisplayCount: 1))
    #expect(!DisplayConnectionPolicy.canDisconnect(connectedDisplayCount: 0))
}
