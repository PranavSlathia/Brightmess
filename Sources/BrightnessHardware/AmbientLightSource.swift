import BrightnessCore
import CPrivateDisplay
import Foundation

public struct AmbientLightSource: Sendable {
    public init() {}
    public func sample() -> AmbientSample {
        var luxMedian = MedianWindow(capacity: 3)
        var colorMedian = MedianWindow(capacity: 3)
        for index in 0..<3 {
            var lux = Double.nan
            var kelvin = Double.nan
            var closed: UInt8 = 0
            _ = BRReadAmbientLight(&lux, &kelvin, &closed)
            if closed != 0 { return AmbientSample(lux: nil, kelvin: nil, lidClosed: true) }
            luxMedian.push(lux)
            colorMedian.push(kelvin)
            if index < 2 { Thread.sleep(forTimeInterval: 0.05) }
        }
        return AmbientSample(lux: luxMedian.median, kelvin: colorMedian.median)
    }
}

extension ExternalDDCController {
    public func colorProfile(of display: ExternalDisplay) -> PanelColorProfile? {
        var xy = [Double](repeating: 0, count: 8)
        guard BRDisplayGetChromaticities(display.displayID, &xy) == 0,
              xy.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        return PanelColorProfile(rx: xy[0], ry: xy[1], gx: xy[2], gy: xy[3],
                                 bx: xy[4], by: xy[5], wx: xy[6], wy: xy[7])
    }
}
