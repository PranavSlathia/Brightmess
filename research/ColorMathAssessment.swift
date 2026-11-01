import Foundation

// Compiled directly alongside the unmodified upstream pure model files.
// Does not construct an app, sensor, display controller, or network server.
@main
struct ColorMathAssessment {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }
        print("PASS: \(message)")
    }

    static func main() {
        let neutral = WhitePointModel.gains(fromCCT: 6504, nativeCCT: 6504)
        check(abs(neutral.r - 1) < 0.001 && abs(neutral.g - 1) < 0.001 &&
              abs(neutral.b - 1) < 0.001, "neutral white returns neutral RGB gains")

        var warm = WhitePointModel()
        warm.update(lux: 500, ambientCCT: 3200, dt: 1)
        var cool = WhitePointModel()
        cool.update(lux: 500, ambientCCT: 8000, dt: 1)
        check(warm.displayCCT < 6500 && cool.displayCCT > 6500,
              "equal lux with different room colour produces different white points")

        let before = warm.displayCCT
        warm.intensity = 0
        warm.update(lux: 500, ambientCCT: 3200, dt: 0.5)
        check(before < 6500 && abs(warm.displayCCT - 6500) < 0.001,
              "turning adaptation strength to zero restores neutral immediately")

        var dark = WhitePointModel()
        dark.update(lux: 1, ambientCCT: 200, dt: 1)
        check(abs(dark.displayCCT - 6500) < 0.001,
              "unreliable very-dark-room colour is rejected")

        let wide = PanelProfile(rx: 0.6729, ry: 0.3223, gx: 0.2568, gy: 0.6748,
                                bx: 0.1484, by: 0.0537, wx: 0.3125, wy: 0.3291)!
        let sRGBGain = WhitePointModel.gains(fromCCT: 4500, nativeCCT: 6504)
        let wideGain = WhitePointModel.gains(fromCCT: 4500, nativeCCT: wide.nativeCCT,
                                            panel: wide)
        check(abs(sRGBGain.b - wideGain.b) > 0.01,
              "different panel primaries require different corrections")

        var map = BrightnessMap()
        map.record(builtin: 0.2, luminance: 15)
        map.record(builtin: 0.8, luminance: 80)
        check(map.luminance(forBuiltin: 0.2) == 15 &&
              map.luminance(forBuiltin: 0.8) == 80,
              "two-point brightness calibration preserves anchors")

        let nodes = [
            CalibrationNode(lux: 0, brightness: 0.1),
            CalibrationNode(lux: 100, brightness: 0.4),
            CalibrationNode(lux: 1000, brightness: 0.9),
        ]
        let samples = (0...2000).map {
            CurveEngine.brightness(forLux: Double($0), nodes: nodes)!
        }
        check(samples.allSatisfy { (0.1...0.9).contains($0) } &&
              zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 },
              "LuxCurve interpolation is bounded and monotonic across 2001 samples")

        check(CurveEngine.brightness(forLux: 100, nodes: []) == nil,
              "LuxCurve leaves uncalibrated brightness unspecified")
        var median = MedianWindow(capacity: 3)
        [100.0, 10000, 105].forEach { median.push($0) }
        check(median.median == 105, "LuxCurve median rejects one brief bright spike")

        check(WhitePointModel().isReadingUsable(lux: .infinity, ambientCCT: 4000),
              "characterization: TrueTone currently accepts infinite lux")
        print("9 functional checks passed; 1 missing-validation behavior reproduced.")
    }
}
