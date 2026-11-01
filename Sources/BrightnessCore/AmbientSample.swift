import Foundation

public struct AmbientSample: Codable, Equatable, Sendable {
    public let lux: Double?
    public let kelvin: Double?
    public let sampledAt: TimeInterval
    public let lidClosed: Bool

    public init(lux: Double?, kelvin: Double?, sampledAt: TimeInterval = Date().timeIntervalSince1970,
                lidClosed: Bool = false) {
        self.lux = lux.flatMap { $0.isFinite && (0...200_000).contains($0) ? $0 : nil }
        self.kelvin = kelvin.flatMap { $0.isFinite && (1500...20_000).contains($0) ? $0 : nil }
        self.sampledAt = sampledAt
        self.lidClosed = lidClosed
    }

    public func unavailableReason(now: TimeInterval = Date().timeIntervalSince1970,
                                  maximumAge: TimeInterval = 2700) -> String? {
        guard sampledAt.isFinite, now.isFinite,
              now - sampledAt >= -30, now - sampledAt <= maximumAge else {
            return "Air colour reading expired"
        }
        guard !lidClosed else { return "Air lid is closed" }
        guard let lux, lux.isFinite, (0...200_000).contains(lux),
              let kelvin, kelvin.isFinite, (1500...20_000).contains(kelvin) else {
            return "Air colour sensor unavailable"
        }
        guard lux >= 4, kelvin >= 2500 else { return "Too dark for reliable colour" }
        return nil
    }
}
