import BrightnessCore
import CPrivateDisplay
import Foundation

public enum BrightnessHardwareError: Error, CustomStringConvertible {
    case builtInDisplayUnavailable(Int32)
    case noExternalDDCDisplay
    case displayNotFound(String)
    case ddcReadFailed(String, Int32)
    case ddcWriteFailed(String, Int32)
    case invalidDDCReply(String)

    public var description: String {
        switch self {
        case let .builtInDisplayUnavailable(code):
            return "No readable built-in display brightness was found (code \(code))."
        case .noExternalDDCDisplay:
            return "No external Apple Silicon display was found."
        case let .displayNotFound(name):
            return "\(name) is no longer connected."
        case let .ddcReadFailed(name, code):
            return "\(name) did not return a valid DDC brightness reading (code \(code))."
        case let .ddcWriteFailed(name, code):
            return "\(name) rejected the DDC brightness write (code \(code))."
        case let .invalidDDCReply(name):
            return "\(name) returned an invalid DDC brightness range."
        }
    }
}

public struct BuiltInBrightnessSource: Sendable {
    public init() {}

    public func sample() throws -> Double {
        var brightness = 0.0
        let result = BRDisplayGetBuiltInBrightness(&brightness)
        guard result == 0 else {
            throw BrightnessHardwareError.builtInDisplayUnavailable(result)
        }
        return min(max(brightness, 0), 1)
    }
}

public struct ExternalDisplay: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayID: UInt32
    public let name: String
    public let vendorID: UInt32
    public let productID: UInt32
    public let serialNumber: UInt32
    public let edidUUID: String
    public let ioLocation: String
    public let isMain: Bool
    public let supportsStandby: Bool

    public init(
        id: String,
        displayID: UInt32,
        name: String,
        vendorID: UInt32,
        productID: UInt32,
        serialNumber: UInt32,
        edidUUID: String,
        ioLocation: String,
        isMain: Bool,
        supportsStandby: Bool
    ) {
        self.id = id
        self.displayID = displayID
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.edidUUID = edidUUID
        self.ioLocation = ioLocation
        self.isMain = isMain
        self.supportsStandby = supportsStandby
    }
}

public struct DDCValue: Equatable, Sendable {
    public let current: UInt16
    public let maximum: UInt16

    public var percentage: UInt16 {
        guard maximum > 0 else { return 0 }
        return UInt16(min(max((Double(current) / Double(maximum) * 100).rounded(), 0), 100))
    }
}

public final class ExternalDDCController: @unchecked Sendable {
    private static let brightnessCode: UInt8 = 0x10
    private static let powerModeCode: UInt8 = 0xD6

    public init() {}

    public var displayCount: Int {
        max(Int(BRDDCGetExternalDisplayCount()), 0)
    }

    public func displays() -> [ExternalDisplay] {
        let count = BRDDCCopyExternalDisplays(nil, 0)
        guard count > 0 else { return [] }
        var rawDisplays = Array(repeating: BRExternalDisplayInfo(), count: Int(count))
        let copied = rawDisplays.withUnsafeMutableBufferPointer { buffer in
            BRDDCCopyExternalDisplays(buffer.baseAddress, UInt32(buffer.count))
        }
        guard copied > 0 else { return [] }

        return rawDisplays.prefix(min(Int(copied), rawDisplays.count)).map { raw in
            ExternalDisplay(
                id: Self.string(from: raw.stableID),
                displayID: raw.displayID,
                name: Self.string(from: raw.name),
                vendorID: raw.vendorID,
                productID: raw.productID,
                serialNumber: raw.serialNumber,
                edidUUID: Self.string(from: raw.edidUUID),
                ioLocation: Self.string(from: raw.ioLocation),
                isMain: raw.isMain != 0,
                supportsStandby: raw.supportsStandby != 0
            )
        }
    }

    public func readBrightness(of display: ExternalDisplay) throws -> DDCValue {
        var current: UInt16 = 0
        var maximum: UInt16 = 0
        let result = BRDDCReadVCP(
            display.displayID,
            Self.brightnessCode,
            &current,
            &maximum
        )
        guard result == 0 else {
            throw BrightnessHardwareError.ddcReadFailed(display.name, result)
        }
        guard maximum > 0, current <= maximum else {
            throw BrightnessHardwareError.invalidDDCReply(display.name)
        }
        return DDCValue(current: current, maximum: maximum)
    }

    public func set(percentage: UInt16, on display: ExternalDisplay) throws {
        guard percentage <= 100 else {
            throw BrightnessHardwareError.ddcWriteFailed(display.name, -1)
        }
        let result = BRDDCWriteVCP(display.displayID, Self.brightnessCode, percentage)
        guard result == 0 else {
            throw BrightnessHardwareError.ddcWriteFailed(display.name, result)
        }
    }

    /// Requests MCCS standby (2) or on (1). Some monitors stop accepting DDC
    /// after standby; the menu instead uses logical disconnect/reconnect.
    public func setPower(on: Bool, for display: ExternalDisplay) throws {
        let result = BRDDCWriteVCP(display.displayID, Self.powerModeCode, on ? 1 : 2)
        guard result == 0 else {
            throw BrightnessHardwareError.ddcWriteFailed(display.name, result)
        }
    }

    @discardableResult
    public func set(percentage: UInt16) throws -> Int {
        guard percentage <= 100 else {
            throw BrightnessHardwareError.ddcWriteFailed("External display", -1)
        }
        let connected = displays()
        guard !connected.isEmpty else {
            throw BrightnessHardwareError.noExternalDDCDisplay
        }
        var successes = 0
        for display in connected {
            if (try? set(percentage: percentage, on: display)) != nil {
                successes += 1
            }
        }
        guard successes > 0 else {
            throw BrightnessHardwareError.ddcWriteFailed("External displays", -3)
        }
        return successes
    }

    private static func string<T>(from tuple: T) -> String {
        var copy = tuple
        return withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }
}
