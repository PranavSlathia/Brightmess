import Foundation

public struct BrightnessCurve: Equatable, Sendable {
    public let minimum: Double
    public let maximum: Double
    public let gamma: Double

    public init(minimum: Double = 15, maximum: Double = 100, gamma: Double = 1) throws {
        guard (0 ... 100).contains(minimum),
              (0 ... 100).contains(maximum),
              minimum <= maximum,
              gamma > 0,
              gamma.isFinite
        else {
            throw BrightnessCurveError.invalidParameters
        }
        self.minimum = minimum
        self.maximum = maximum
        self.gamma = gamma
    }

    public func map(normalized input: Double) -> UInt16 {
        let clamped = min(max(input, 0), 1)
        let curved = pow(clamped, gamma)
        let percentage = minimum + curved * (maximum - minimum)
        return UInt16(percentage.rounded())
    }
}

public enum BrightnessCurveError: Error, Equatable {
    case invalidParameters
}
