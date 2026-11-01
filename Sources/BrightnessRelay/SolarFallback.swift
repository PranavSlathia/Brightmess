import BrightnessCore
import CoreLocation
import Foundation
import SunKit

struct SolarFallbackConfiguration: Sendable {
    let latitude: Double
    let longitude: Double
    let timeZone: TimeZone
    let staleAfter: TimeInterval
    let updateInterval: TimeInterval
    let curve: SolarBrightnessCurve

    init(
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone,
        staleAfter: TimeInterval = 2_700,
        updateInterval: TimeInterval = 300,
        curve: SolarBrightnessCurve = SolarBrightnessCurve()
    ) throws {
        guard latitude.isFinite, (-90 ... 90).contains(latitude),
              longitude.isFinite, (-180 ... 180).contains(longitude),
              staleAfter >= 60, updateInterval >= 60
        else {
            throw CLIError.invalidValue("solar fallback configuration")
        }
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
        self.staleAfter = staleAfter
        self.updateInterval = updateInterval
        self.curve = curve
    }

    func normalizedBrightness(at date: Date) -> Double {
        curve.normalizedBrightness(solarAltitude: solarAltitude(at: date))
    }

    func solarAltitude(at date: Date) -> Double {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        return Sun(location: location, timeZone: timeZone, date: date).altitude.degrees
    }
}
