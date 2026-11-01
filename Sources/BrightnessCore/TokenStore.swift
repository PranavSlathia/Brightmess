import Foundation

public enum TokenStore {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/brightness-relay/token", isDirectory: false)
    }

    @discardableResult
    public static func create(at url: URL = defaultURL) throws -> Data {
        let token = Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max) })
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = Data(token.base64EncodedString().utf8)
        try encoded.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return token
    }

    public static func load(from url: URL = defaultURL) throws -> Data {
        let raw = try Data(contentsOf: url)
        guard let text = String(data: raw, encoding: .utf8),
              let token = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              token.count >= 32
        else {
            throw TokenError.malformed
        }
        return token
    }
}
