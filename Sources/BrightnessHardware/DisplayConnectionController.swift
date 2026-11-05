import CPrivateDisplay
import Foundation

public enum DisplayConnectionError: Error, CustomStringConvertible {
    case privateAPIUnavailable
    case lastActiveDisplay
    case displayNotFound(String)
    case ambiguousIdentity(String)
    case operationFailed(String, Int32)
    case postconditionFailed(String)
    case recoveryLedger(String)

    public var description: String {
        switch self {
        case .privateAPIUnavailable:
            return "Display disconnect is unavailable on this macOS version."
        case .lastActiveDisplay:
            return "At least one other screen must remain connected."
        case let .displayNotFound(name):
            return "\(name) is not present in the WindowServer display list."
        case let .ambiguousIdentity(name):
            return "\(name) matches more than one display, so reconnect was refused."
        case let .operationFailed(operation, code):
            if operation == "Reconnect", code == 1001 {
                return "macOS could not reattach this display. Check its input and cable; if needed, unplug the display's power for 20 seconds and reconnect. Your recovery record is kept."
            }
            return "\(operation) failed (display error \(code))."
        case let .postconditionFailed(message):
            return message
        case let .recoveryLedger(message):
            return "The recovery record could not be saved: \(message)"
        }
    }
}

public struct DisplayRecoveryRecord: Codable, Sendable {
    public let display: ExternalDisplay
    public let disconnectedAt: Date
}

public struct DisplayRecoveryOutcome: Sendable {
    public let display: ExternalDisplay
    public let error: String?

    public var succeeded: Bool { error == nil }
}

public final class DisplayRecoveryLedger: @unchecked Sendable {
    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/brightness-relay/display-recovery.json")

    public let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL = DisplayRecoveryLedger.defaultURL) {
        self.fileURL = fileURL
    }

    public func records() throws -> [DisplayRecoveryRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try readUnlocked()
    }

    public func record(_ display: ExternalDisplay) throws {
        lock.lock()
        defer { lock.unlock() }
        var current = try readUnlocked().filter { $0.display.id != display.id }
        current.append(DisplayRecoveryRecord(display: display, disconnectedAt: Date()))
        try writeUnlocked(current)
    }

    public func remove(displayID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let records = try readUnlocked()
        let current = records.filter { $0.display.id != displayID }
        guard records.count != current.count else { return }
        try writeUnlocked(current)
    }

    private func readUnlocked() throws -> [DisplayRecoveryRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            return try JSONDecoder().decode(
                [DisplayRecoveryRecord].self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            throw DisplayConnectionError.recoveryLedger(error.localizedDescription)
        }
    }

    private func writeUnlocked(_ records: [DisplayRecoveryRecord]) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch let error as DisplayConnectionError {
            throw error
        } catch {
            throw DisplayConnectionError.recoveryLedger(error.localizedDescription)
        }
    }
}

public final class DisplayConnectionController: @unchecked Sendable {
    public let ledger: DisplayRecoveryLedger
    private let backend: any DisplayConnectionBackend
    private let pause: (TimeInterval) -> Void

    public init(ledger: DisplayRecoveryLedger = DisplayRecoveryLedger()) {
        self.ledger = ledger
        self.backend = NativeDisplayConnectionBackend()
        self.pause = Thread.sleep(forTimeInterval:)
    }

    init(ledger: DisplayRecoveryLedger, backend: any DisplayConnectionBackend,
         pause: @escaping (TimeInterval) -> Void = { _ in }) {
        self.ledger = ledger
        self.backend = backend
        self.pause = pause
    }

    public var isAvailable: Bool {
        backend.isAvailable
    }

    public func isOnline(_ display: ExternalDisplay) -> Bool {
        guard let current = try? resolve(display) else { return false }
        return backend.isOnline(current)
    }

    public func disconnectedDisplays() -> [ExternalDisplay] {
        (try? ledger.records().map(\.display)) ?? []
    }

    public func disconnect(_ display: ExternalDisplay) throws {
        guard isAvailable else { throw DisplayConnectionError.privateAPIUnavailable }
        // Refuse an ambiguous target before changing anything or writing a
        // recovery record. A transient numeric ID alone is not an identity.
        let resolvedID = try resolve(display)
        try ledger.record(display)

        let result = backend.setEnabled(resolvedID, false)
        if result != 0 {
            if isOnline(display) {
                try? ledger.remove(displayID: display.id)
            }
            throw connectionError(code: result, display: display, operation: "Disconnect")
        }

        for _ in 0 ..< 20 {
            if !isOnline(display) { return }
            pause(0.025)
        }
        throw DisplayConnectionError.postconditionFailed(
            "macOS accepted the request, but \(display.name) remained connected. Its recovery record is kept."
        )
    }

    @discardableResult
    public func reconnect(_ display: ExternalDisplay) throws -> UInt32 {
        guard isAvailable else { throw DisplayConnectionError.privateAPIUnavailable }
        var lastError: Error?

        for attempt in 1 ... 3 {
            do {
                let resolvedID = try resolve(display)
                // A replug can already have restored it. Committing a no-op
                // transaction is rejected by WindowServer on some versions.
                if backend.isOnline(resolvedID) {
                    try ledger.remove(displayID: display.id)
                    return resolvedID
                }
                let result = backend.setEnabled(resolvedID, true)
                guard result == 0 else {
                    throw connectionError(
                        code: result,
                        display: display,
                        operation: "Reconnect"
                    )
                }
                for _ in 0 ..< 10 {
                    // Re-enabling can allocate a new slot; re-resolve stable
                    // identity rather than waiting only for the old number.
                    if let current = try? resolve(display), backend.isOnline(current) {
                        try ledger.remove(displayID: display.id)
                        return current
                    }
                    pause(0.04)
                }
                throw DisplayConnectionError.postconditionFailed(
                    "\(display.name) did not return to the macOS display layout."
                )
            } catch {
                lastError = error
                if attempt < 3 { pause(0.4) }
            }
        }
        throw lastError ?? DisplayConnectionError.displayNotFound(display.name)
    }

    public func recoverAll() throws -> [DisplayRecoveryOutcome] {
        let records = try ledger.records()
        return records.map { record in
            do {
                _ = try reconnect(record.display)
                return DisplayRecoveryOutcome(display: record.display, error: nil)
            } catch {
                return DisplayRecoveryOutcome(
                    display: record.display,
                    error: String(describing: error)
                )
            }
        }
    }

    private func resolve(_ display: ExternalDisplay) throws -> UInt32 {
        try DisplayIdentityResolver.resolve(display, among: backend.candidates())
    }

    /// Identity resolution only. Does not enable, disable or alter a display.
    public func currentDisplayID(for display: ExternalDisplay) throws -> UInt32 { try resolve(display) }

    private func connectionError(
        code: Int32,
        display: ExternalDisplay,
        operation: String
    ) -> DisplayConnectionError {
        switch code {
        case -100: return .privateAPIUnavailable
        case -101: return .lastActiveDisplay
        case -102: return .displayNotFound(display.name)
        case -103: return .ambiguousIdentity(display.name)
        default: return .operationFailed(operation, code)
        }
    }
}
