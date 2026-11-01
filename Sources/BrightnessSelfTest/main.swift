import BrightnessCore
import Foundation

enum SelfTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): return message
        }
    }
}

@main
struct BrightnessSelfTest {
    static func main() throws {
        try checkCurveEndpoints()
        try checkCurveGamma()
        try checkAuthentication()
        try checkBrightnessReplayProtection()
        try checkPullReplayProtection()
        try checkSolarCurve()
        try checkBrightnessKeySteps()
        try checkSafeDisconnectPolicy()
        try checkAmbientValidity()
        try checkBackwardCompatibleEnvelope()
        try checkWhitePoint()
        try checkDimRoomWhitePoint()
        try checkCalibration()
        try checkMedian()
        try checkAmbientReplay()
        print("15 core checks passed.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SelfTestFailure.failed(message) }
    }

    private static func checkCurveEndpoints() throws {
        let curve = try BrightnessCurve(minimum: 20, maximum: 90, gamma: 1)
        try require(curve.map(normalized: -1) == 20, "curve lower clamp failed")
        try require(curve.map(normalized: 0.5) == 55, "curve midpoint failed")
        try require(curve.map(normalized: 2) == 90, "curve upper clamp failed")
    }

    private static func checkCurveGamma() throws {
        let curve = try BrightnessCurve(minimum: 0, maximum: 100, gamma: 2)
        try require(curve.map(normalized: 0.5) == 25, "curve gamma failed")
    }

    private static func checkAuthentication() throws {
        let authenticator = try RelayAuthenticator(token: Data(repeating: 0xA5, count: 32))
        let body = Data("payload".utf8)
        let signature = authenticator.signature(for: body)
        try require(authenticator.verify(signature: signature, body: body), "valid HMAC rejected")
        try require(
            !authenticator.verify(signature: signature, body: Data("tampered".utf8)),
            "tampered HMAC accepted"
        )
    }

    private static func checkBrightnessReplayProtection() throws {
        let envelope = try BrightnessEnvelope(
            brightness: 0.5,
            sentAt: 1_000,
            nonce: "brightness-nonce",
            source: "air"
        )
        var guardrail = ReplayGuard(maximumClockSkew: 30)
        try guardrail.validate(envelope, now: 1_000)
        do {
            try guardrail.validate(envelope, now: 1_001)
            throw SelfTestFailure.failed("brightness replay accepted")
        } catch RelayProtocolError.replayedEnvelope {
            // Expected.
        }
    }

    private static func checkPullReplayProtection() throws {
        let envelope = try PullWaitEnvelope(
            sentAt: 2_000,
            nonce: "pull-nonce",
            source: "air"
        )
        var guardrail = ReplayGuard(maximumClockSkew: 30)
        try guardrail.validate(envelope, now: 2_000)
        do {
            try guardrail.validate(envelope, now: 2_001)
            throw SelfTestFailure.failed("pull replay accepted")
        } catch RelayProtocolError.replayedEnvelope {
            // Expected.
        }
    }

    private static func checkSolarCurve() throws {
        let curve = SolarBrightnessCurve()
        let samples = stride(from: -20.0, through: 80, by: 1).map {
            curve.normalizedBrightness(solarAltitude: $0)
        }
        try require(samples.allSatisfy { (0 ... 1).contains($0) }, "solar curve escaped bounds")
        try require(
            zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 },
            "solar curve is not monotonic"
        )
    }

    private static func checkBrightnessKeySteps() throws {
        try require(
            BrightnessStepPolicy.next(from: 50, direction: .up) == 56,
            "standard brightness-up step failed"
        )
        try require(
            BrightnessStepPolicy.next(from: 50, direction: .down, fine: true) == 49,
            "fine brightness-down step failed"
        )
        try require(
            BrightnessStepPolicy.next(from: 98, direction: .up) == 100,
            "brightness step upper clamp failed"
        )
    }

    private static func checkSafeDisconnectPolicy() throws {
        try require(
            DisplayConnectionPolicy.canDisconnect(connectedDisplayCount: 2),
            "two-display disconnect was rejected"
        )
        try require(
            !DisplayConnectionPolicy.canDisconnect(connectedDisplayCount: 1),
            "last display disconnect was allowed"
        )
    }

    private static func checkAmbientValidity() throws {
        let good = AmbientSample(lux: 300, kelvin: 4200, sampledAt: 1000)
        try require(good.unavailableReason(now: 1001) == nil, "valid ambient sample rejected")
        try require(good.unavailableReason(now: 3701) != nil, "expired colour accepted")
        try require(good.unavailableReason(now: 900) != nil, "future colour accepted")
        try require(AmbientSample(lux: 300, kelvin: 4200, sampledAt: 1000, lidClosed: true)
            .unavailableReason(now: 1001) != nil, "closed lid accepted")
        try require(AmbientSample(lux: .infinity, kelvin: 4200, sampledAt: 1000)
            .unavailableReason(now: 1001) != nil, "infinite lux accepted")
        try require(AmbientSample(lux: 1, kelvin: 200, sampledAt: 1000)
            .unavailableReason(now: 1001) != nil, "dark sensor colour accepted")
    }

    private static func checkBackwardCompatibleEnvelope() throws {
        let old = Data(#"{"version":1,"brightness":0.5,"sentAt":1000,"nonce":"legacy","source":"air"}"#.utf8)
        let decoded = try JSONDecoder().decode(BrightnessEnvelope.self, from: old)
        try require(decoded.ambient == nil && decoded.brightness == 0.5, "legacy Air helper rejected")
        let packet = try BrightnessEnvelope(brightness: 0.5, source: "air",
            ambient: AmbientSample(lux: 300, kelvin: 4200))
        let body = try JSONEncoder().encode(packet)
        let auth = try RelayAuthenticator(token: Data(repeating: 3, count: 32))
        let signature = auth.signature(for: body)
        let modified = Data(String(decoding: body, as: UTF8.self).replacingOccurrences(of: "4200", with: "6500").utf8)
        try require(!auth.verify(signature: signature, body: modified), "ambient data not covered by HMAC")
    }

    private static func checkWhitePoint() throws {
        var warm = AdaptiveWhitePoint()
        warm.update(lux: 500, ambientCCT: 3200, dt: 1)
        var cool = AdaptiveWhitePoint()
        cool.update(lux: 500, ambientCCT: 8000, dt: 1)
        try require(warm.displayCCT < 6500 && cool.displayCCT > 6500, "CCT ignored at equal lux")
        try require(!warm.isReadingUsable(lux: .infinity, ambientCCT: 4000), "infinite model input accepted")
        warm.intensity = 0
        warm.update(lux: 500, ambientCCT: 3200, dt: 1)
        try require(abs(warm.displayCCT - warm.nativeCCT) < 0.01, "neutral reset left tint")
        let native = AdaptiveWhitePoint.gains(fromCCT: 6504, nativeCCT: 6504)
        try require(abs(native.r - 1) < 0.001 && abs(native.b - 1) < 0.001, "neutral gains incorrect")
        let wide = PanelColorProfile(rx: 0.6729, ry: 0.3223, gx: 0.2568, gy: 0.6748,
                                    bx: 0.1484, by: 0.0537, wx: 0.3125, wy: 0.3291)!
        let a = AdaptiveWhitePoint.gains(fromCCT: 4500, nativeCCT: 6504)
        let b = AdaptiveWhitePoint.gains(fromCCT: 4500, nativeCCT: wide.nativeCCT, panel: wide)
        try require(abs(a.b - b.b) > 0.01, "per-panel primaries ignored")
    }

    private static func checkDimRoomWhitePoint() throws {
        var model = AdaptiveWhitePoint()
        model.nativeCCT = 6462.190704536224
        model.intensity = 0.65
        var target = model
        target.update(lux: 40, ambientCCT: 5419, dt: 1)
        model.resetToNative()
        model.update(lux: 40, ambientCCT: 5419, dt: 1)
        try require(model.displayCCT < model.nativeCCT && model.displayCCT > target.displayCCT,
                    "dim-room adaptation jumped instead of easing from native white")
        for _ in 0..<60 { model.update(lux: 40, ambientCCT: 5419, dt: 1) }
        try require(model.displayCCT < model.nativeCCT - 20,
                    "dim-room adaptation stayed at native white instead of applying Air colour")
        try require(model.rgbGains().b < 0.999, "dim-room adaptation did not change RGB gains")
        try require(abs(model.displayCCT - target.displayCCT) < 0.01,
                    "smoothing stopped short of its accepted target")
        for _ in 0..<60 { model.update(lux: 40, ambientCCT: 5420, dt: 1) }
        try require(abs(model.displayCCT - target.displayCCT) < 0.01,
                    "sensor noise changed the accepted white point")
        model.intensity = 0
        model.update(lux: 40, ambientCCT: 5419, dt: 1)
        try require(abs(model.displayCCT - model.nativeCCT) < 0.01, "zero strength failed to restore native white")
    }

    private static func checkCalibration() throws {
        var samsung = BrightnessCalibration()
        samsung.record(builtin: 0.2, luminance: 20)
        samsung.record(builtin: 0.8, luminance: 70)
        var tv = BrightnessCalibration()
        tv.record(builtin: 0.2, luminance: 40)
        tv.record(builtin: 0.8, luminance: 90)
        try require(samsung.luminance(forBuiltin: 0.5) != tv.luminance(forBuiltin: 0.5),
                    "display calibration shared incorrectly")
        let restored = try JSONDecoder().decode(BrightnessCalibration.self, from: JSONEncoder().encode(samsung))
        try require(restored == samsung, "calibration persistence failed")
        samsung.record(builtin: .nan, luminance: 10)
        try require(samsung == restored, "invalid calibration source accepted")
        samsung.reset()
        try require(!samsung.isCalibrated, "calibration reset failed")
    }

    private static func checkMedian() throws {
        var median = MedianWindow(capacity: 3)
        [100.0, .nan, 10000, 105].forEach { median.push($0) }
        try require(median.median == 105, "median did not reject spike/non-finite input")
    }

    private static func checkAmbientReplay() throws {
        let envelope = AmbientEnvelope(source: "air", ambient: AmbientSample(lux: nil, kelvin: nil))
        var guardrail = ReplayGuard()
        try guardrail.validate(envelope)
        do {
            try guardrail.validate(envelope)
            throw SelfTestFailure.failed("ambient replay accepted")
        } catch RelayProtocolError.replayedEnvelope {}
    }
}
