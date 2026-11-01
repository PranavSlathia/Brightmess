import Foundation

public struct ReplayGuard: Sendable {
    private var expirationByNonce: [String: TimeInterval] = [:]
    private let maximumClockSkew: TimeInterval

    public init(maximumClockSkew: TimeInterval = 30) {
        self.maximumClockSkew = maximumClockSkew
    }

    public mutating func validate(
        _ envelope: BrightnessEnvelope,
        now: TimeInterval = Date().timeIntervalSince1970
    ) throws {
        try validate(
            version: envelope.version,
            sentAt: envelope.sentAt,
            nonce: envelope.nonce,
            now: now
        )
    }

    public mutating func validate(
        _ envelope: PullWaitEnvelope,
        now: TimeInterval = Date().timeIntervalSince1970
    ) throws {
        try validate(
            version: envelope.version,
            sentAt: envelope.sentAt,
            nonce: envelope.nonce,
            now: now
        )
    }

    public mutating func validate(
        _ envelope: AmbientEnvelope,
        now: TimeInterval = Date().timeIntervalSince1970
    ) throws {
        try validate(version: envelope.version, sentAt: envelope.sentAt,
                     nonce: envelope.nonce, now: now)
    }

    private mutating func validate(
        version: Int,
        sentAt: TimeInterval,
        nonce: String,
        now: TimeInterval
    ) throws {
        guard version == 1 else {
            throw RelayProtocolError.unsupportedVersion
        }
        guard sentAt.isFinite, now.isFinite, !nonce.isEmpty,
              abs(now - sentAt) <= maximumClockSkew else {
            throw RelayProtocolError.staleEnvelope
        }

        expirationByNonce = expirationByNonce.filter { $0.value >= now }
        guard expirationByNonce[nonce] == nil else {
            throw RelayProtocolError.replayedEnvelope
        }
        expirationByNonce[nonce] = sentAt + maximumClockSkew
    }
}
