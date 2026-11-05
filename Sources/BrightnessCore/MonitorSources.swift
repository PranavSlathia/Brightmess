import Foundation

public enum MonitorPort: String, Codable, CaseIterable, Sendable {
    case displayPort, hdmi1, hdmi2
    public var title: String {
        switch self { case .displayPort: return "DisplayPort"; case .hdmi1: return "HDMI 1"; case .hdmi2: return "HDMI 2" }
    }
    /// Candidates only. They do not qualify a monitor's source-switching support.
    public var candidateCode: UInt16 {
        switch self { case .displayPort: return 15; case .hdmi1: return 17; case .hdmi2: return 18 }
    }
}

public struct MonitorSourceProof: Codable, Equatable, Sendable {
    public let targetCode: UInt16
    public let returnCode: UInt16
    public let ioLocation: String
    public let confirmedAt: Date
    public init(targetCode: UInt16, returnCode: UInt16, ioLocation: String, confirmedAt: Date = Date()) {
        self.targetCode = targetCode; self.returnCode = returnCode
        self.ioLocation = ioLocation; self.confirmedAt = confirmedAt
    }
}

public struct MonitorSourceRoute: Codable, Equatable, Sendable {
    public var name: String
    public var code: UInt16
    public var proof: MonitorSourceProof?
    public init(_ port: MonitorPort) { name = port.title; code = port.candidateCode }
}

public struct MonitorSourceProfile: Codable, Equatable, Sendable {
    public let version: Int
    public private(set) var routes: [String: MonitorSourceRoute]
    public private(set) var observedReturnCode: UInt16?
    public private(set) var observedLocation: String?
    public init() { version = 1; routes = Dictionary(uniqueKeysWithValues: MonitorPort.allCases.map { ($0.rawValue, .init($0)) }) }
    public func route(_ port: MonitorPort) -> MonitorSourceRoute { routes[port.rawValue] ?? .init(port) }
    @discardableResult public mutating func configure(_ port: MonitorPort, name: String, code: UInt16) -> Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code > 0, code <= 255, !cleaned.isEmpty, cleaned.count <= 32,
              !cleaned.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !MonitorPort.allCases.contains(where: { $0 != port && route($0).code == code }) else { return false }
        var current = route(port)
        if current.code != code {
            current.proof = nil
            if port == .displayPort {
                observedReturnCode = nil; observedLocation = nil
                for p in MonitorPort.allCases { routes[p.rawValue]?.proof = nil }
            }
        }
        current.name = cleaned; current.code = code; routes[port.rawValue] = current
        return true
    }
    public mutating func observeReturn(_ code: UInt16, location: String) {
        guard code == route(.displayPort).code, !location.isEmpty else { return }
        observedReturnCode = code; observedLocation = location
    }
    public func canActivate(_ port: MonitorPort, location: String) -> Bool {
        guard version == 1, !location.isEmpty, observedLocation == location,
              observedReturnCode == route(.displayPort).code else { return false }
        if port == .displayPort { return true }
        guard let p = route(port).proof else { return false }
        return p.targetCode == route(port).code && p.returnCode == route(.displayPort).code && p.ioLocation == location
    }
    public mutating func qualify(_ port: MonitorPort, proof: MonitorSourceProof) -> Bool {
        guard version == 1, port != .displayPort, proof.targetCode == route(port).code,
              proof.returnCode == route(.displayPort).code, proof.ioLocation == observedLocation,
              observedReturnCode == proof.returnCode else { return false }
        routes[port.rawValue]?.proof = proof
        return true
    }
    public mutating func revoke(_ port: MonitorPort) { routes[port.rawValue]?.proof = nil }
}
