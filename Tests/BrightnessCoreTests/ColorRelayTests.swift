import Foundation
import Testing
@testable import BrightnessCore

@Test func oldAirPacketsRemainCompatible() throws {
    let data = Data(#"{"version":1,"brightness":0.7,"sentAt":1000,"nonce":"old","source":"Air"}"#.utf8)
    let packet = try JSONDecoder().decode(BrightnessEnvelope.self, from: data)
    #expect(packet.brightness == 0.7)
    #expect(packet.ambient == nil)
}

@Test func colourReadingsExpireAndRejectInvalidSensors() {
    let sample = AmbientSample(lux: 40, kelvin: 5420, sampledAt: 1000)
    #expect(sample.unavailableReason(now: 1001) == nil)
    #expect(sample.unavailableReason(now: 3701) != nil)
    #expect(sample.unavailableReason(now: 900) != nil)
    #expect(AmbientSample(lux: .infinity, kelvin: 5420, sampledAt: 1000)
        .unavailableReason(now: 1001) != nil)
    #expect(AmbientSample(lux: 40, kelvin: 5420, sampledAt: 1000, lidClosed: true)
        .unavailableReason(now: 1001) != nil)
}

@Test func roomColourIsIndependentOfLightIntensity() {
    var warm = AdaptiveWhitePoint()
    var cool = AdaptiveWhitePoint()
    warm.update(lux: 300, ambientCCT: 3200, dt: 1)
    cool.update(lux: 300, ambientCCT: 8000, dt: 1)
    #expect(warm.displayCCT < 6500)
    #expect(cool.displayCCT > 6500)
    #expect(!warm.isReadingUsable(lux: .infinity, ambientCCT: 4200))
    warm.intensity = 0
    warm.update(lux: 300, ambientCCT: 3200, dt: 1)
    #expect(abs(warm.displayCCT - 6500) < 0.01)
}

@Test func differentScreensKeepDifferentCalibration() throws {
    var samsung = BrightnessCalibration()
    var tv = BrightnessCalibration()
    samsung.record(builtin: 0.4, luminance: 30)
    tv.record(builtin: 0.4, luminance: 55)
    #expect(samsung.luminance(forBuiltin: 0.4) == 30)
    #expect(tv.luminance(forBuiltin: 0.4) == 55)
    let data = try JSONEncoder().encode(samsung)
    #expect(try JSONDecoder().decode(BrightnessCalibration.self, from: data) == samsung)
    samsung.record(builtin: .nan, luminance: 20)
    #expect(samsung.luminance(forBuiltin: 0.4) == 30)
}

@Test func dimRoomCorrectionEasesFullyWithoutFollowingSensorNoise() {
    var model = AdaptiveWhitePoint()
    model.nativeCCT = 6462.190704536224
    model.intensity = 0.65
    var target = model
    target.update(lux: 40, ambientCCT: 5419, dt: 1)
    model.resetToNative()
    model.update(lux: 40, ambientCCT: 5419, dt: 1)
    #expect(model.displayCCT < model.nativeCCT)
    #expect(model.displayCCT > target.displayCCT)
    for _ in 0..<60 { model.update(lux: 40, ambientCCT: 5419, dt: 1) }
    #expect(abs(model.displayCCT - target.displayCCT) < 0.01)
    #expect(model.rgbGains().b < 0.999)
    for _ in 0..<60 { model.update(lux: 40, ambientCCT: 5420, dt: 1) }
    #expect(abs(model.displayCCT - target.displayCCT) < 0.01)
    model.intensity = 0
    model.update(lux: 40, ambientCCT: 5419, dt: 1)
    #expect(abs(model.displayCCT - model.nativeCCT) < 0.01)
}

@Test func ambientStatusUsesReplayProtection() throws {
    let packet = AmbientEnvelope(source: "Air", ambient: AmbientSample(lux: nil, kelvin: nil))
    var replay = ReplayGuard()
    try replay.validate(packet)
    #expect(throws: RelayProtocolError.replayedEnvelope) { try replay.validate(packet) }
}
