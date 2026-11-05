import BrightnessCore
import CPrivateDisplay
import Foundation
import CoreGraphics

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

public enum DeskDisplayShape: String, Codable, Sendable {
    case portraitMonitor, monitor, television
    public static func identify(name: String, portrait: Bool) -> Self {
        let words = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        if words.contains("tv") || words.contains("television") { return .television }
        return portrait ? .portraitMonitor : .monitor
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
    // Optional so recovery records created by earlier releases still decode.
    public let deskShape: DeskDisplayShape?
    /// Oriented macOS desktop points, not panel pixels or physical inches.
    /// Older recovery records have no geometry; do not invent a ratio for them.
    public let desktopWidth: Double?, desktopHeight: Double?, desktopX: Double?
    public var shape: DeskDisplayShape { deskShape ?? .identify(name: name, portrait: false) }

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
        supportsStandby: Bool, deskShape: DeskDisplayShape? = nil,
        desktopWidth: Double? = nil, desktopHeight: Double? = nil, desktopX: Double? = nil
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
        self.deskShape = deskShape
        self.desktopWidth = desktopWidth; self.desktopHeight = desktopHeight; self.desktopX = desktopX
    }
}

public struct DDCValue: Equatable, Sendable {
    public let current: UInt16
    public let maximum: UInt16
    public init(current: UInt16, maximum: UInt16) { self.current = current; self.maximum = maximum }

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
            let bounds = CGDisplayBounds(raw.displayID)
            return ExternalDisplay(
                id: Self.string(from: raw.stableID),
                displayID: raw.displayID,
                name: Self.string(from: raw.name),
                vendorID: raw.vendorID,
                productID: raw.productID,
                serialNumber: raw.serialNumber,
                edidUUID: Self.string(from: raw.edidUUID),
                ioLocation: Self.string(from: raw.ioLocation),
                isMain: raw.isMain != 0,
                supportsStandby: raw.supportsStandby != 0,
                deskShape: .identify(name: Self.string(from: raw.name),
                    portrait: bounds.height > bounds.width),
                desktopWidth: bounds.width, desktopHeight: bounds.height, desktopX: bounds.minX
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

    private func inputChannel(for display: ExternalDisplay) throws -> UInt32 {
        let id = try DisplayConnectionController().currentDisplayID(for: display)
        guard BRDDCValidateIdentity(id, display.vendorID, display.productID, display.serialNumber) == 0 else {
            throw BrightnessHardwareError.displayNotFound(display.name + " (no verified DDC channel)")
        }
        return id
    }

    public func readInput(of display: ExternalDisplay) throws -> UInt16 {
        let id = try inputChannel(for: display)
        var current: UInt16 = 0, maximum: UInt16 = 0
        let result = BRDDCReadVCP(id, 0x60, &current, &maximum)
        guard result == 0, current > 0, current <= 255 else {
            throw BrightnessHardwareError.ddcReadFailed(display.name + " input", result)
        }
        // Input-source maximum is often a count, not the largest allowed code.
        return current
    }

    public func setInput(_ value: UInt16, on display: ExternalDisplay) throws {
        guard value > 0, value <= 255 else { throw BrightnessHardwareError.ddcWriteFailed(display.name, -1) }
        let id = try DisplayConnectionController().currentDisplayID(for: display)
        let result = BRDDCWriteInputVerified(id, display.vendorID, display.productID, display.serialNumber, value)
        guard result == 0 else { throw BrightnessHardwareError.ddcWriteFailed(display.name + " input", result) }
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

    static func string<T>(from tuple: T) -> String {
        var copy = tuple
        return withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }
}
