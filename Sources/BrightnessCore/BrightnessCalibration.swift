// Adapted from SaintD1smas/TrueTone (MIT). See NOTICE.
import Foundation

/// Maps the MacBook's brightness onto the external display's backlight.
///
/// A straight 1:1 (built-in 63 % → luminance 63) matches the numbers but not the
/// eye: the panels differ in peak brightness, and macOS's slider is perceptual
/// while DDC luminance is a raw backlight scale. So the mapping is defined by up
/// to two calibration anchors the user records by eye — two points give both the
/// offset (things line up) and the slope (the useful range), which is why there
/// are no separate min/max knobs.
public struct BrightnessCalibration: Equatable, Codable, Sendable {
    public init() {}
    /// MacBook brightness 0…1 ↔ external display luminance 0…100, at the dim and bright ends.
    public var loBuiltin: Double?
    public var loLum: Int?
    public var hiBuiltin: Double?
    public var hiLum: Int?

    public static let hardMin = 0
    public static let hardMax = 100
    /// Anchors closer together than this can't define a trustworthy slope.
    public static let minSpread = 0.15

    public var isCalibrated: Bool { anchors.count > 0 }

    private var anchors: [(b: Double, lum: Int)] {
        var out: [(Double, Int)] = []
        if let b = loBuiltin, b.isFinite, (0...1).contains(b),
           let l = loLum, (0...100).contains(l) { out.append((b, l)) }
        if let b = hiBuiltin, b.isFinite, (0...1).contains(b),
           let l = hiLum, (0...100).contains(l) { out.append((b, l)) }
        return out.sorted { $0.0 < $1.0 }
    }

    public func luminance(forBuiltin builtin: Double) -> Int {
        let x = builtin.isFinite ? min(max(builtin, 0), 1) : 0.5
        let a = anchors
        let raw: Double

        if a.count == 2, a[1].b - a[0].b >= Self.minSpread {
            // Two usable points: a line through both, extrapolated past the ends.
            let t = (x - a[0].b) / (a[1].b - a[0].b)
            raw = Double(a[0].lum) + t * Double(a[1].lum - a[0].lum)
        } else if let only = a.first {
            // One point: keep the default 1:1 slope, slide it through the anchor.
            raw = Double(only.lum) + (x - only.b) * 100
        } else {
            raw = x * 100
        }
        return Int(min(max(raw.rounded(), Double(Self.hardMin)), Double(Self.hardMax)))
    }

    /// Remember "these two look the same". Keeps the two most widely separated
    /// anchors, so re-recording near an existing one refines it instead of
    /// collapsing the calibration onto a single brightness.
    public mutating func record(builtin: Double, luminance: Int) {
        guard builtin.isFinite, (0...1).contains(builtin) else { return }
        // An anchor outside the range we can actually drive is not a match the
        // user saw: the manual slider reaches 0, and "at 62 % I wanted 0" got
        // stored as gospel.
        let lum = min(max(luminance, Self.hardMin), Self.hardMax)
        var pts = anchors.filter { abs($0.b - builtin) > Self.minSpread / 2 }
        pts.append((builtin, lum))
        pts.sort { $0.b < $1.b }
        if pts.count > 2 { pts = [pts.first!, pts.last!] }
        // Brightness cannot run backwards, and a flat pair leaves the panel
        // parked. Either way the pair pinned the external display whatever the keys did, so
        // keep what was just recorded and drop the point that contradicts it.
        if pts.count == 2, pts[1].lum <= pts[0].lum { pts = [(builtin, lum)] }

        loBuiltin = pts.first?.b;  loLum = pts.first?.lum
        if pts.count > 1 {
            hiBuiltin = pts.last?.b; hiLum = pts.last?.lum
        } else {
            hiBuiltin = nil; hiLum = nil
        }
    }

    public mutating func reset() {
        loBuiltin = nil; loLum = nil; hiBuiltin = nil; hiLum = nil
    }

    /// Short description for the menu.
    public var summary: String {
        let a = anchors
        switch a.count {
        case 0: return "not calibrated"
        case 1: return String(format: "1 point: %.0f %% → %d", a[0].b * 100, a[0].lum)
        default: return String(format: "%.0f %% → %d  ·  %.0f %% → %d",
                               a[0].b * 100, a[0].lum, a[1].b * 100, a[1].lum)
        }
    }
}
