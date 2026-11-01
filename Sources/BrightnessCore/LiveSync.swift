import Foundation

public enum SourceMode: String, Codable, Sendable { case live, scheduled }
public enum AirState: String, Codable, Sendable { case awake, lidClosed, asleep, unavailable }

public struct SourceMetadata: Codable, Equatable, Sendable {
    public let mode: SourceMode
    public let session: UUID
    public let sequence: UInt64
    public let measuredAt: TimeInterval
    public let state: AirState
    public init(mode: SourceMode = .live, session: UUID, sequence: UInt64, measuredAt: Double, state: AirState) {
        self.mode = mode; self.session = session; self.sequence = sequence
        self.measuredAt = measuredAt; self.state = state
    }
}

/// Shared across brightness and health endpoints; invoked only after HMAC + nonce checking.
public struct SourceOrder {
    private var last: SourceMetadata?
    private var retired: [UUID: Double] = [:]
    public init() {}
    public mutating func accept(_ m: SourceMetadata?, at now: Double) throws {
        guard let m else {
            if let last, last.mode == .live, now - last.measuredAt < 90 { throw RelayProtocolError.staleEnvelope }
            return
        }
        guard m.measuredAt.isFinite, abs(m.measuredAt - now) <= 30, m.sequence > 0 else { throw RelayProtocolError.staleEnvelope }
        retired = retired.filter { $0.value >= now }
        guard retired[m.session] == nil else { throw RelayProtocolError.replayedEnvelope }
        if let last {
            if m.session == last.session {
                guard m.sequence > last.sequence, m.measuredAt >= last.measuredAt else { throw RelayProtocolError.replayedEnvelope }
            } else {
                guard m.measuredAt >= last.measuredAt else { throw RelayProtocolError.staleEnvelope }
                retired[last.session] = now + 61
            }
        }
        last = m
    }
}

public struct SourcePresence: Sendable {
    public private(set) var mode: SourceMode?
    public private(set) var state: AirState?
    public private(set) var measurement: Double?
    public private(set) var raw: Double?
    public private(set) var lostAt: Double?
    public init() {}
    public mutating func receive(mode: SourceMode, state: AirState, time: Double, brightness: Double?) {
        self.mode = mode; self.state = state
        if state == .awake, let brightness {
            raw = brightness; measurement = time; lostAt = nil
        } else if lostAt == nil { lostAt = time }
    }
    public func cutoff(started: Double, scheduledGrace: Double = 2700) -> Double {
        if let lostAt { return lostAt + 300 }
        return (measurement ?? started) + (mode == .scheduled ? scheduledGrace : 300)
    }
    public func label(now: Double, solar: Bool) -> String {
        if solar { return "Solar fallback" }
        switch state {
        case .asleep: return "Air asleep"
        case .lidClosed: return "Lid closed"
        case .unavailable: return "Air brightness unavailable"
        default: break
        }
        guard let measurement else { return "Waiting for Air" }
        if mode == .scheduled { return "Scheduled" }
        return now - measurement >= 90 ? "No recent Air reading" : "Live"
    }
}

/// Single-slot, monotonic-time send scheduler. One in flight, latest pending wins.
public struct LatestPublisher<Value: Sendable>: Sendable {
    private var pending: Value?
    private var inFlight = false
    private var lastStart = -Double.infinity
    private var retryAt = -Double.infinity
    private var backoff: Double = 1
    public init() {}
    public mutating func offer(_ value: Value) { pending = value }
    public func delay(at now: Double) -> Double? {
        !inFlight && pending != nil ? max(0, max(lastStart + 0.25, retryAt) - now) : nil
    }
    public mutating func take(at now: Double) -> Value? {
        guard delay(at: now) == 0, let next = pending else { return nil }
        pending = nil; inFlight = true; lastStart = now; return next
    }
    public mutating func finish(_ sent: Value, success: Bool, now: Double) {
        inFlight = false
        if success { backoff = 1; retryAt = -.infinity }
        else {
            if pending == nil { pending = sent }
            retryAt = now + backoff; backoff = min(60, backoff * 2)
        }
    }
}
