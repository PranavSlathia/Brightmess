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
        let current = try readUnlocked().filter { $0.display.id != displayID }
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

    public init(ledger: DisplayRecoveryLedger = DisplayRecoveryLedger()) {
        self.ledger = ledger
    }

    public var isAvailable: Bool {
        BRDisplayConnectionAvailable() != 0
    }

    public func isOnline(_ display: ExternalDisplay) -> Bool {
        BRDisplayIsOnline(display.displayID) != 0
    }

    public func disconnectedDisplays() -> [ExternalDisplay] {
        (try? ledger.records().map(\.display)) ?? []
    }

    public func disconnect(_ display: ExternalDisplay) throws {
        guard isAvailable else { throw DisplayConnectionError.privateAPIUnavailable }
        try ledger.record(display)

        let result = BRDisplaySetEnabled(display.displayID, 0)
        if result != 0 {
            if isOnline(display) {
                try? ledger.remove(displayID: display.id)
            }
            throw connectionError(code: result, display: display, operation: "Disconnect")
        }

        for _ in 0 ..< 20 {
            if !isOnline(display) { return }
            Thread.sleep(forTimeInterval: 0.025)
        }
        try? ledger.remove(displayID: display.id)
        throw DisplayConnectionError.postconditionFailed(
            "macOS accepted the request, but \(display.name) remained connected."
        )
    }

    @discardableResult
    public func reconnect(_ display: ExternalDisplay) throws -> UInt32 {
        guard isAvailable else { throw DisplayConnectionError.privateAPIUnavailable }
        var lastError: Error?

        for attempt in 1 ... 3 {
            do {
                let resolvedID = try resolve(display)
                let result = BRDisplaySetEnabled(resolvedID, 1)
                guard result == 0 else {
                    throw connectionError(
                        code: result,
                        display: display,
                        operation: "Reconnect"
                    )
                }
                for _ in 0 ..< 10 {
                    if BRDisplayIsOnline(resolvedID) != 0 {
                        try ledger.remove(displayID: display.id)
                        return resolvedID
                    }
                    Thread.sleep(forTimeInterval: 0.04)
                }
                throw DisplayConnectionError.postconditionFailed(
                    "\(display.name) did not return to the macOS display layout."
                )
            } catch {
                lastError = error
                if attempt < 3 { Thread.sleep(forTimeInterval: 0.4) }
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
        var resolvedID: UInt32 = 0
        let result = BRDisplayResolveKnownID(
            display.displayID,
            display.vendorID,
            display.productID,
            display.serialNumber,
            &resolvedID
        )
        guard result == 0 else {
            throw connectionError(code: result, display: display, operation: "Resolve")
        }
        return resolvedID
    }

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
