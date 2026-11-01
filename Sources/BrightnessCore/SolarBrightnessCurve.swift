import Foundation

/// Maps solar altitude to a comfortable display-brightness signal.
///
/// This is intentionally conservative: a clock cannot see clouds, curtains,
/// or room lights. It is a fallback for machines without a local light sensor.
public struct SolarBrightnessCurve: Sendable {
    public let nightBrightness: Double
    public let lowSunBrightness: Double
    public let dayBrightness: Double

    public init(
        nightBrightness: Double = 0.18,
        lowSunBrightness: Double = 0.42,
        dayBrightness: Double = 0.78
    ) {
        self.nightBrightness = nightBrightness
        self.lowSunBrightness = lowSunBrightness
        self.dayBrightness = dayBrightness
    }

    public func normalizedBrightness(solarAltitude: Double) -> Double {
        guard solarAltitude.isFinite else { return nightBrightness }
        if solarAltitude <= -6 { return nightBrightness }
        if solarAltitude < 10 {
            return interpolate(
                from: nightBrightness,
                to: lowSunBrightness,
                progress: (solarAltitude + 6) / 16
            )
        }
        if solarAltitude < 45 {
            return interpolate(
                from: lowSunBrightness,
                to: dayBrightness,
                progress: (solarAltitude - 10) / 35
            )
        }
        return dayBrightness
    }

    private func interpolate(from: Double, to: Double, progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        let smooth = clamped * clamped * (3 - 2 * clamped)
        return from + (to - from) * smooth
    }
}
