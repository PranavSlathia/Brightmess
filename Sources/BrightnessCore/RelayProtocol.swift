import CryptoKit
import Foundation

public struct BrightnessEnvelope: Codable, Equatable, Sendable {
    public let version: Int
    public let brightness: Double
    public let sentAt: TimeInterval
    public let nonce: String
    public let source: String
    public let ambient: AmbientSample?
    public let metadata: SourceMetadata?

    public init(
        brightness: Double,
        sentAt: TimeInterval = Date().timeIntervalSince1970,
        nonce: String = UUID().uuidString,
        source: String,
        ambient: AmbientSample? = nil, metadata: SourceMetadata? = nil
    ) throws {
        guard brightness.isFinite, (0 ... 1).contains(brightness), !source.isEmpty else {
            throw RelayProtocolError.invalidEnvelope
        }
        self.version = 1
        self.brightness = brightness
        self.sentAt = sentAt
        self.nonce = nonce
        self.source = source
        self.metadata = metadata
        self.ambient = ambient
    }
}

public struct PullWaitEnvelope: Codable, Equatable, Sendable {
    public let version: Int
    public let sentAt: TimeInterval
    public let nonce: String
    public let source: String
    public let displayID: String?
    public let value: Double?

    public init(
        sentAt: TimeInterval = Date().timeIntervalSince1970,
        nonce: String = UUID().uuidString,
        source: String,
        displayID: String? = nil,
        value: Double? = nil
    ) throws {
        guard !source.isEmpty else {
            throw RelayProtocolError.invalidEnvelope
        }
        self.version = 1
        self.sentAt = sentAt
        self.nonce = nonce
        self.source = source
        self.displayID = displayID
        self.value = value
    }
}

public struct AmbientEnvelope: Codable, Sendable {
    public let version: Int
    public let sentAt: TimeInterval
    public let nonce: String
    public let source: String
    public let ambient: AmbientSample

    public let metadata: SourceMetadata?

    public init(source: String, ambient: AmbientSample, metadata: SourceMetadata? = nil) {
        self.metadata = metadata
        version = 1
        sentAt = Date().timeIntervalSince1970
        nonce = UUID().uuidString
        self.source = source
        self.ambient = ambient
    }
}

public enum RelayProtocolError: Error, Equatable {
    case invalidEnvelope
    case invalidSignature
    case staleEnvelope
    case unsupportedVersion
    case replayedEnvelope
}

public struct RelayAuthenticator: Sendable {
    private let key: SymmetricKey

    public init(token: Data) throws {
        guard token.count >= 32 else {
            throw TokenError.tooShort
        }
        self.key = SymmetricKey(data: token)
    }

    public func signature(for body: Data) -> String {
        let digest = HMAC<SHA256>.authenticationCode(for: body, using: key)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func verify(signature: String, body: Data) -> Bool {
        guard let signatureData = Data(hexadecimal: signature) else {
            return false
        }
        return HMAC<SHA256>.isValidAuthenticationCode(signatureData, authenticating: body, using: key)
    }
}

public enum TokenError: Error, Equatable {
    case tooShort
    case malformed
}

extension Data {
    init?(hexadecimal: String) {
        guard hexadecimal.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hexadecimal.count / 2)
        var index = hexadecimal.startIndex
        while index < hexadecimal.endIndex {
            let next = hexadecimal.index(index, offsetBy: 2)
            guard let byte = UInt8(hexadecimal[index ..< next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
