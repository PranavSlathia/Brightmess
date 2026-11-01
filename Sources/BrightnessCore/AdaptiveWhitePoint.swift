// Adapted from SaintD1smas/TrueTone (MIT). See NOTICE.
import Foundation

/// Turns an ambient reading into per-channel RGB gains for the display, the way
/// True Tone does: a *partial* shift of the display white point from its native
/// D65 toward the colour of the room, stronger in bright light, gentle and
/// time-smoothed so the screen never visibly jumps.
public struct AdaptiveWhitePoint: Sendable {
    public init() {}

    // Tunables. Apple's True Tone is subtle: it moves the white point only a
    // fraction of the way toward the ambient colour, and reaches full strength
    // only in bright (outdoor-ish) light. These defaults mirror that; "Strength"
    // scales it further down.
    public var nativeCCT: Double = 6500          // display native white (D65)
    public var maxAdapt: Double = 0.45          // at most ~45 % of the way toward ambient
    public var intensity: Double = 1.0          // 0…1 from the menu slider
    public var baseFrac: Double = 0.10          // minimal pull in dim light
    public var floorCCT: Double = 4300          // clamp target — never go orange
    public var ceilCCT: Double = 6900
    public var luxLow: Double = 5                // below this: only baseFrac
    public var luxHigh: Double = 800             // full lux term only in bright light
    public var tau: Double = 6.0                 // smoothing time constant, seconds
    public var deadbandMired: Double = 1.5       // ignore changes to an accepted target
    public var trimK: Double = 0                 // manual bias on the final target (Kelvin)

    /// Smoothed state, in mired (10^6 / Kelvin). nil until first update.
    public private(set) var currentMired: Double?
    private var acceptedTargetMired: Double?
    public var isSettling: Bool {
        guard let currentMired, let acceptedTargetMired else { return false }
        return abs(currentMired - acceptedTargetMired) > 0.002
    }

    /// The CCT the screen is currently being driven to (for the readout).
    public var displayCCT: Double { currentMired.map { 1_000_000 / $0 } ?? nativeCCT }

    // MARK: update

    /// Advance the model by `dt` seconds toward the target implied by the reading.
    public mutating func update(lux: Double, ambientCCT: Double, dt: Double) {
        let desired = targetMired(lux: lux, ambientCCT: ambientCCT)
        let native = 1_000_000 / nativeCCT
        // Explicit neutral/invalid input must always remove our tint.
        if abs(desired - native) < 1e-9 {
            currentMired = native
            acceptedTargetMired = nil
            return
        }
        // Filter sensor-target wobble, not distance remaining in the fade.
        // The first valid target is always accepted, including a dim-room
        // correction smaller than the deadband. Once accepted, converge fully.
        if acceptedTargetMired == nil || abs(desired - acceptedTargetMired!) >= deadbandMired {
            acceptedTargetMired = desired
        }
        let target = acceptedTargetMired ?? desired
        guard let cur = currentMired else { currentMired = target; return }
        let safeDT = dt.isFinite ? min(max(dt, 0), 10) : 0
        let alpha = 1 - exp(-safeDT / max(tau, 0.1))
        currentMired = cur + alpha * (target - cur)
    }

    /// Jump straight to native (used when the feature is switched off).
    public mutating func resetToNative() {
        currentMired = 1_000_000 / nativeCCT
        acceptedTargetMired = nil
    }

    /// The panel we're driving. Its real primaries matter: computing gains with a
    /// hardcoded sRGB matrix on a wide-gamut display overshoots the warm shift.
    public var panel: PanelColorProfile = .sRGB

    /// Per-channel gains (each ≤ 1.0) to apply on top of an identity gamma ramp.
    public func rgbGains() -> (r: Double, g: Double, b: Double) {
        Self.gains(fromCCT: displayCCT, nativeCCT: nativeCCT, panel: panel)
    }

    // MARK: adaptation curve

    /// Below a few lux the sensor's colour reading is meaningless — it reports a
    /// few hundred Kelvin. Callers use this to avoid presenting that as fact.
    public func isReadingUsable(lux: Double, ambientCCT: Double) -> Bool {
        lux.isFinite && ambientCCT.isFinite && (4...200_000).contains(lux) && (2500...20_000).contains(ambientCCT)
    }

    private func targetMired(lux: Double, ambientCCT: Double) -> Double {
        // Nothing trustworthy to adapt to — sit at the native white point.
        if !isReadingUsable(lux: lux, ambientCCT: ambientCCT) { return 1_000_000 / nativeCCT }

        let ambient = min(max(ambientCCT, 3500), 10_000)
        let luxT = smoothstep(lux, luxLow, luxHigh)
        let frac = min(max(intensity, 0), 1) * (baseFrac + (1 - baseFrac) * luxT) * maxAdapt

        let mNative = 1_000_000 / nativeCCT
        let mAmbient = 1_000_000 / ambient
        let m = mNative + frac * (mAmbient - mNative)

        // auto clamp, then the manual trim (which may push a bit past it)
        var k = min(max(1_000_000 / m, floorCCT), ceilCCT)
        k = min(max(k + trimK, 3500), 7500)
        return 1_000_000 / k
    }

    private func smoothstep(_ x: Double, _ a: Double, _ b: Double) -> Double {
        guard b > a else { return x >= b ? 1 : 0 }
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: colour math  (CCT → xy → linear sRGB → normalised gains)

    public static func gains(fromCCT cct: Double, nativeCCT: Double,
                      panel: PanelColorProfile = .sRGB) -> (r: Double, g: Double, b: Double) {
        guard cct.isFinite, nativeCCT.isFinite, (1500...25000).contains(cct),
              (1500...25000).contains(nativeCCT) else { return (1, 1, 1) }
        let want = panelWhite(cct: cct, panel: panel)
        let have = panelWhite(cct: nativeCCT, panel: panel)
        // ratio that maps the native white onto the wanted white
        var r = want.0 / have.0
        var g = want.1 / have.1
        var b = want.2 / have.2
        let m = max(r, max(g, b))
        r /= m; g /= m; b /= m
        return (clamp01(r), clamp01(g), clamp01(b))
    }

    /// Linear RGB (in the panel's own primaries) of a black-body white at `cct`, Y = 1.
    private static func panelWhite(cct: Double, panel: PanelColorProfile) -> (Double, Double, Double) {
        let (x, y) = chromaticity(cct: cct)
        let xyz = [x / y, 1.0, (1 - x - y) / y]
        let m = panel.xyzToRGB
        let rgb = (0..<3).map { i in (0..<3).map { j in m[i][j] * xyz[j] }.reduce(0, +) }
        return (max(rgb[0], 0), max(rgb[1], 0), max(rgb[2], 0))
    }

    /// Kim et al. CCT → CIE 1931 xy (valid ~1667–25000 K).
    private static func chromaticity(cct: Double) -> (Double, Double) {
        let T = min(max(cct, 1667), 25_000)
        let t = 1000.0 / T, t2 = t * t, t3 = t2 * t
        let x: Double
        if T <= 4000 {
            x = -0.2661239 * t3 - 0.2343589 * t2 + 0.8776956 * t + 0.179910
        } else {
            x = -3.0258469 * t3 + 2.1070379 * t2 + 0.2226347 * t + 0.240390
        }
        let x2 = x * x, x3 = x2 * x
        let y: Double
        if T <= 2222 {
            y = -1.1063814 * x3 - 1.34811020 * x2 + 2.18555832 * x - 0.20219683
        } else if T <= 4000 {
            y = -0.9549476 * x3 - 1.37418593 * x2 + 2.09137015 * x - 0.16748867
        } else {
            y =  3.0817580 * x3 - 5.87338670 * x2 + 3.75112997 * x - 0.37001483
        }
        return (x, y)
    }

    private static func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }
}
