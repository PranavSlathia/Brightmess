import BrightnessCore
import Foundation
import CoreGraphics

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
        let checks = [checkCurveEndpoints, checkCurveGamma, checkAuthentication, checkBrightnessReplayProtection,
                      checkPullReplayProtection, checkSolarCurve, checkBrightnessKeySteps, checkSafeDisconnectPolicy,
                      checkAmbientValidity, checkBackwardCompatibleEnvelope, checkWhitePoint, checkDimRoomWhitePoint,
                      checkCalibration, checkMedian, checkAmbientReplay, checkLiveOrder, checkLearnedCurve,
                      checkPublisherClock, checkHoldPolicy, checkFade, checkMigration, checkWindowFit, checkTVFrames,
                      checkTVSession, checkWindowSelection, checkMonitorSources, checkReadbackFreshness]
        for check in checks { try check() }; print("\(checks.count) core checks passed.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SelfTestFailure.failed(message) }
    }

    private static func checkMonitorSources() throws {
        var p = MonitorSourceProfile()
        try require(!p.canActivate(.hdmi1, location: "port"), "Unverified HDMI source enabled")
        p.observeReturn(15, location: "port")
        try require(p.canActivate(.displayPort, location: "port"), "Observed DP return unavailable")
        try require(!p.qualify(.hdmi1, proof: .init(targetCode: 17, returnCode: 18, ioLocation: "port")), "Wrong return qualified")
        try require(p.qualify(.hdmi1, proof: .init(targetCode: 17, returnCode: 15, ioLocation: "port")), "Valid round trip rejected")
        try require(p.configure(.hdmi1, name: "Air", code: 17) && p.canActivate(.hdmi1, location: "port"), "Rename lost proof")
        try require(!p.canActivate(.hdmi1, location: "other"), "Port change kept qualification")
        try require(p.configure(.hdmi1, name: "Air", code: 5) && !p.canActivate(.hdmi1, location: "port"), "Mapping change kept qualification")
    }

    private static func checkReadbackFreshness() throws {
        let t = Date(timeIntervalSince1970: 100)
        try require(HardwareReadbackPolicy.isFresh(readAt: t, lastWriteAt: nil, now: t.addingTimeInterval(1)), "Valid reading stale")
        try require(!HardwareReadbackPolicy.isFresh(readAt: t, lastWriteAt: t.addingTimeInterval(1), now: t.addingTimeInterval(2)), "Old read verified new command")
        try require(!HardwareReadbackPolicy.isFresh(readAt: t, lastWriteAt: nil, now: t.addingTimeInterval(16)), "Expired reading live")
    }

    private static func checkWindowFit() throws {
        try require(WindowPlacement.otherDisplay(containing:11,connected:[22,11]) == 22 &&
                    WindowPlacement.otherDisplay(containing:22,connected:[22,11]) == 11,
                    "Window toggle must reverse with the window, regardless of screen order")
        try require(WindowPlacement.otherDisplay(containing:11,connected:[11]) == nil &&
                    WindowPlacement.otherDisplay(containing:99,connected:[11,22]) == nil, "Do not guess another screen")
        let wide = CGRect(x: 100, y: -30, width: 1920, height: 1080)
        let tall = CGRect(x: -900, y: 25, width: 900, height: 1530)
        try require(WindowPlacement.fit(wide, from: wide, to: tall) == tall, "maximized window must fill portrait destination")
        let normal = WindowPlacement.fit(CGRect(x: 250,y: 20,width: 500,height: 300), from: wide, to: tall)
        try require(tall.contains(normal) && normal.size == CGSize(width: 500,height: 300), "normal windows retain size")
    }

    private static func checkTVFrames() throws {
        var stream = TVFrames()
        let packet = Data(repeating: 0x23, count: 300)
        let wire = TVWire.frame(packet) + TVWire.frame(Data([1]))
        let first = try stream.push(Data(wire.prefix(1)))
        let rest = try stream.push(Data(wire.dropFirst()))
        try require(first.isEmpty && rest == [packet,Data([1])], "TCP boundaries changed TV commands")
    }

    private static func checkTVSession() throws {
        typealias W = TVWire
        var pair = TVHandshake(pairing:true)
        let proof = Data(repeating:0xb3,count:32)
        var fakeReplies = [W.pair(11,Data()),W.pair(20,Data()),W.pair(31,Data())]
        for reply in fakeReplies { _ = try pair.receive(reply) }
        try require(pair.step == .code,"pairing must wait for physical code")
        _ = try pair.prove(proof)
        var bad = pair
        do { _ = try bad.receive(W.pair(41,W.bytes(1,Data([1])))); throw SelfTestFailure.failed("wrong proof accepted") } catch is TVError {}
        _ = try pair.receive(W.pair(41,W.bytes(1,proof)))
        try require(pair.step == .verified,"valid TV rejected")
        let peer = Data("TV A".utf8), pin = TVTrust.fingerprint(peer)
        try require(!TVTrust.accepts(Data("TV B".utf8),pairing:false,pinned:pin) &&
            TVTrust.accepts(peer,pairing:false,pinned:pin) && !TVTrust.accepts(peer,pairing:false,pinned:nil),
            "TV identity must follow the public key across address changes, not the IP")
        var remote = TVHandshake(pairing:false)
        do { _ = try remote.command(code:243); throw SelfTestFailure.failed("offline command queued") } catch is TVError {}
        fakeReplies = [W.bytes(1,W.number(1,547)),W.bytes(2,Data()),W.bytes(40,W.number(1,1))]
        for reply in fakeReplies { _ = try remote.receive(reply) }
        let direct = try remote.command(code:245), chooser = try remote.command(code:178)
        try require(direct == Data([0x52,5,8,245,1,16,3]) && chooser == W.key(178),"wrong HDMI commands")
        let link = try remote.command(code:245,inputID:"com.fixture/.Pass/HW27")
        let fields = try W.Fields(link), url = try W.Fields(fields.b[90] ?? Data()).b[1]
        try require(url == Data("content://android.media.tv/passthrough/com.fixture%2F.Pass%2FHW27".utf8),"fallback must use verified ID")
        do { _ = try W.link("https://bad"); throw SelfTestFailure.failed("arbitrary URL accepted") } catch is TVError {}
    }

    private static func checkWindowSelection() throws {
        let r = CGRect(x:0,y:0,width:400,height:500), dest = CGRect(x:-900,y:10,width:900,height:1500)
        var selected: UInt32? = 1, writes = 0, full = false
        func move(trusted: Bool = true, online: Bool = true) throws {
            try WindowPlacement.move(original:1,destination:2,trusted:trusted,usable:{ _ in online ? dest : nil },
                read:{ selected.map { .init(screen:$0,rect:r,usable:r,fullScreen:full,movable:true) } },
                write:{ frame in writes += 1; selected = 2; return frame == dest })
        }
        // A second window can become focused without replacing the captured window.
        try move(); try require(writes == 1 && selected == 2,"selected window was not moved")
        for (original,permit,online,fs) in [(2 as UInt32?,true,true,false),(nil,true,true,false),
                (1,false,true,false),(1,true,false,false),(1,true,true,true),(3,true,true,false)] {
            selected = original; full = fs
            do { try move(trusted:permit,online:online); throw SelfTestFailure.failed("stale/unsafe window moved") } catch is TVError {}
        }
        try require(writes == 1,"unsafe case wrote to a window")
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

    private static func checkLearnedCurve() throws {
        var c = LearnedCurve()
        let base = try BrightnessCurve()
        for (x,y) in [(0.1, 20), (0.5, 45), (0.9, 80), (0.5, 90)] { c.learn(x, y) }
        try require(c.count == 3 && c.target(0.5, base: base) == 90, "newest match not preserved")
        let levels = (0...100).map { c.target(Double($0)/100, base: base) }
        try require(zip(levels, levels.dropFirst()).allSatisfy { $0 <= $1 }, "curve reversed")
        c.undo()
        try require(c.target(0.5, base: base) == 45, "undo lost replaced point")
    }

    private static func checkPublisherClock() throws {
        var queue = LatestPublisher<Int>()
        queue.offer(42)
        try require(queue.take(at: 0) == 42, "first event delayed")
        queue.offer(12); queue.offer(15)
        try require(queue.take(at: 1) == nil, "two sends in flight")
        queue.finish(42, success: true, now: 0.1)
        try require(queue.take(at: 0.24) == nil && queue.take(at: 0.25) == 15, "burst did not flush newest value")
        queue.finish(15, success: false, now: 1)
        queue.offer(17)
        try require(queue.take(at: 1.9) == nil && queue.take(at: 2) == 17, "offline retry lost newest")
        var clock = 2.0
        for power in 1...8 {
            queue.finish(17, success: false, now: clock)
            let delay = min(60.0, pow(2.0, Double(power)))
            try require(queue.delay(at: clock) == delay, "retry not capped")
            clock += delay
            try require(queue.take(at: clock) == 17, "retry missing")
        }
        queue.finish(17, success: true, now: clock)
        try require(queue.delay(at: clock+600) == nil, "idle publisher scheduled traffic")
    }

    private static func checkHoldPolicy() throws {
        var p = SourcePresence()
        p.receive(mode: .live, state: .awake, time: 100, brightness: 0.5)
        try require(p.label(now: 189, solar: false) == "Live" && p.label(now: 190, solar: false) == "No recent Air reading", "silence reported as sleep")
        try require(p.cutoff(started: 0) == 400, "lost contact hold incorrect")
        p.receive(mode: .live, state: .asleep, time: 135, brightness: nil)
        p.receive(mode: .live, state: .asleep, time: 195, brightness: nil)
        try require(p.cutoff(started: 0) == 435 && p.raw == 0.5, "repeated sleep extended hold")
        p.receive(mode: .scheduled, state: .awake, time: 500, brightness: 0.7)
        try require(p.cutoff(started: 0) == 3200 && p.label(now: 700, solar: false) == "Scheduled", "legacy freshness broken")
    }

    private static func checkFade() throws {
        let a = LevelTransition(start: 10, goal: 80, began: 5)
        try require(a.value(at: 4) == 10 && a.value(at: 6) == 80, "fade overshot")
        let b = LevelTransition(start: a.value(at: 5.5), goal: 20, began: 5.5)
        try require(b.value(at: 5.5) == 45 && b.value(at: 7) == 20, "fade retarget jumped")
    }

    private static func checkMigration() throws {
        var old = BrightnessCalibration()
        old.record(builtin: 0.2, luminance: 33); old.record(builtin: 0.8, luminance: 71)
        let c = LearnedCurve(legacy: old), base = try BrightnessCurve(minimum: 10, maximum: 90)
        try require(c.count == 2 && c.target(0.2, base: base) == 33 && c.target(0.8, base: base) == 71, "lost old matches")
        try require(c.target(1, base: base) == 87 && c.target(0, base: base) == 17, "base curve extension wrong")
        let restored = try JSONDecoder().decode(LearnedCurve.self, from: JSONEncoder().encode(c))
        try require(c == restored, "curve round trip")
    }

    private static func checkLiveOrder() throws {
        var admission = SourceOrder()
        let session = UUID()
        func meta(_ n: UInt64) -> SourceMetadata {
            SourceMetadata(session: session, sequence: n, measuredAt: 1000, state: .awake)
        }
        try admission.accept(meta(2), at: 1000)
        do {
            try admission.accept(meta(1), at: 1001)
            throw SelfTestFailure.failed("older live sample overwrote a newer one")
        } catch RelayProtocolError.replayedEnvelope {}
        try admission.accept(SourceMetadata(session: UUID(), sequence: 1, measuredAt: 1002, state: .awake), at: 1002)
        do {
            try admission.accept(meta(3), at: 1003)
            throw SelfTestFailure.failed("retired source session revived")
        } catch RelayProtocolError.replayedEnvelope {}
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
