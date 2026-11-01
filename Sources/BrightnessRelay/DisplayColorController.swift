import AppKit
import BrightnessCore
import BrightnessHardware
import Foundation

enum DisplayColorMode: String, Codable, CaseIterable {
    case off, adaptive, manual
    var label: String { rawValue.capitalized }
}

struct DisplayColorSettings: Codable {
    var mode: DisplayColorMode = .off
    var strength: Double = 0.65
    var trim: Double = 0
    var manualKelvin: Double = 6500
}

struct DisplayColorState {
    var settings = DisplayColorSettings()
    var detail = "Original colours"
    var targetKelvin: Double?
    var profile = "sRGB estimate"
    var error: String?
}

// Per-display baseline ownership/interference checks follow MonitorControl.
// White-point maths and EDID modelling are adapted from TrueTone. See NOTICE.
@MainActor
final class DisplayColorController {
    private struct Ramp {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
        func isClose(to other: Ramp, tolerance: Float = 0.008) -> Bool {
            guard red.count == other.red.count else { return false }
            return zip(red + green + blue, other.red + other.green + other.blue)
                .allSatisfy { abs($0 - $1) <= tolerance }
        }
        func scaled(_ gains: (r: Double, g: Double, b: Double)) -> Ramp {
            Ramp(red: red.map { $0 * Float(gains.r) },
                 green: green.map { $0 * Float(gains.g) },
                 blue: blue.map { $0 * Float(gains.b) })
        }
    }

    private let hardware = ExternalDDCController()
    private let defaults = UserDefaults.standard
    private var displays: [String: ExternalDisplay] = [:]
    private var profiles: [String: PanelColorProfile] = [:]
    private var baselines: [String: Ramp] = [:]
    private var written: [String: Ramp] = [:]
    private var models: [String: AdaptiveWhitePoint] = [:]
    private var suspended: Set<String> = []
    private var sample: AmbientSample?
    private var lastTick = Date()
    private(set) var states: [String: DisplayColorState] = [:]
    var onChanged: (([String: DisplayColorState]) -> Void)?

    func updateDisplays(_ values: [ManagedDisplayState]) {
        let live = Dictionary(uniqueKeysWithValues: values.filter {
            $0.connectionState.isConnected
        }.map { ($0.id, $0.display) })
        for (id, old) in displays where live[id]?.displayID != old.displayID {
            restore(id)
            baselines[id] = nil
            written[id] = nil
            profiles[id] = nil
            models[id] = nil
        }
        displays = live
        for state in values {
            if states[state.id] == nil {
                var settings = defaults.data(forKey: preferenceKey(state.id))
                    .flatMap { try? JSONDecoder().decode(DisplayColorSettings.self, from: $0) }
                    ?? DisplayColorSettings()
                settings.strength = min(max(settings.strength, 0), 1)
                settings.trim = min(max(settings.trim, -1000), 1000)
                settings.manualKelvin = min(max(settings.manualKelvin, 3500), 7500)
                states[state.id] = DisplayColorState(settings: settings)
            }
            if !state.connectionState.isConnected { states[state.id]?.detail = "Screen disconnected" }
        }
        tick()
    }

    func accept(_ sample: AmbientSample?) {
        self.sample = sample
        tick()
    }

    func setMode(_ mode: DisplayColorMode, id: String) {
        guard states[id] != nil else { return }
        if suspended.contains(id) {
            // Another app now owns the table. A deliberate retry starts from
            // its current baseline rather than restoring over its adjustment.
            baselines[id] = nil
            written[id] = nil
        }
        suspended.remove(id)
        states[id]?.error = nil
        states[id]?.settings.mode = mode
        models[id] = nil
        persist(id)
        tick()
    }

    func setValue(_ value: Double, kind: String, id: String) {
        guard value.isFinite, states[id] != nil else { return }
        switch kind {
        case "strength": states[id]?.settings.strength = min(max(value, 0), 1)
        case "trim": states[id]?.settings.trim = min(max(value, -1000), 1000)
        case "kelvin":
            states[id]?.settings.manualKelvin = min(max(value, 3500), 7500)
            states[id]?.settings.mode = .manual
        default: return
        }
        persist(id)
        tick()
    }

    func reset(id: String) {
        restore(id)
        states[id] = DisplayColorState()
        models[id] = nil
        suspended.remove(id)
        persist(id)
        tick()
    }

    func restoreAll() {
        for id in displays.keys { restore(id) }
    }

    func configurationChanged() {
        // If macOS retained our tint, keep its original baseline. Otherwise
        // the OS/profile changed and the new table becomes the next baseline.
        for (id, display) in displays {
            if let expected = written[id], let current = try? read(display.displayID),
               expected.isClose(to: current) { continue }
            baselines[id] = nil
            written[id] = nil
            profiles[id] = nil
            models[id] = nil
            suspended.remove(id)
        }
    }

    func tick() {
        let dt = min(max(Date().timeIntervalSince(lastTick), 0.01), 2)
        lastTick = Date()
        for (id, display) in displays {
            guard var state = states[id] else { continue }
            if state.settings.mode == .off {
                restore(id)
                state.detail = "Original colours"
                state.targetKelvin = nil
                states[id] = state
                continue
            }
            if suspended.contains(id) { continue }
            if let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
            }), screen.maximumExtendedDynamicRangeColorComponentValue > 1.01 {
                restore(id)
                state.detail = "Colour paused while HDR is active"
                state.targetKelvin = nil
                states[id] = state
                continue
            }
            if state.settings.mode == .adaptive {
                if let reason = sample?.unavailableReason() ?? (sample == nil ? "Waiting for Air colour helper" : nil) {
                    restore(id)
                    models[id] = nil
                    state.detail = reason
                    state.targetKelvin = nil
                    states[id] = state
                    continue
                }
            }
            do {
                if profiles[id] == nil {
                    let profile = hardware.colorProfile(of: display)
                    profiles[id] = profile ?? .sRGB
                    state.profile = profile == nil ? "sRGB estimate" : "Display EDID"
                }
                let profile = profiles[id] ?? .sRGB
                if baselines[id] == nil { baselines[id] = try read(display.displayID) }
                if let expected = written[id] {
                    let current = try read(display.displayID)
                    guard current.isClose(to: expected) else {
                        suspended.insert(id)
                        state.error = "Another app changed colours; select a mode to retry"
                        state.detail = "Colour control paused"
                        states[id] = state
                        RelayLog.write("Colour interference on \(display.name); suspended our writes")
                        continue
                    }
                }
                var model = models[id] ?? {
                    var value = AdaptiveWhitePoint()
                    value.nativeCCT = profile.nativeCCT
                    value.panel = profile
                    value.resetToNative()
                    return value
                }()
                let target: Double
                let gains: (r: Double, g: Double, b: Double)
                if state.settings.mode == .manual {
                    target = state.settings.manualKelvin
                    gains = AdaptiveWhitePoint.gains(fromCCT: target,
                        nativeCCT: profile.nativeCCT, panel: profile)
                } else {
                    guard let sample, let lux = sample.lux, let kelvin = sample.kelvin else { continue }
                    model.intensity = state.settings.strength
                    model.trimK = state.settings.trim
                    model.update(lux: lux, ambientCCT: kelvin, dt: dt)
                    models[id] = model
                    target = model.displayCCT
                    gains = model.rgbGains()
                }
                guard [gains.r, gains.g, gains.b].allSatisfy({
                    $0.isFinite && (0.05...1).contains($0)
                }), let baseline = baselines[id] else {
                    throw ColorError("Invalid colour calculation; no change applied")
                }
                let ramp = baseline.scaled(gains)
                if written[id]?.isClose(to: ramp, tolerance: 0.0005) != true {
                    try write(ramp, to: display.displayID)
                    let actual = try read(display.displayID)
                    guard actual.isClose(to: ramp) else { throw ColorError("macOS did not retain the colour adjustment") }
                    written[id] = ramp
                }
                state.targetKelvin = target
                state.detail = "\(Int(target.rounded())) K target · \(state.profile)"
                state.error = nil
                states[id] = state
            } catch {
                restore(id)
                suspended.insert(id)
                state.error = String(describing: error)
                state.detail = "Colour unavailable"
                states[id] = state
                RelayLog.write("\(display.name) colour failed: \(error)")
            }
        }
        onChanged?(states)
    }

    private func read(_ id: UInt32) throws -> Ramp {
        guard CGDisplayIsOnline(id) != 0 else { throw ColorError("Display is disconnected") }
        let capacity = CGDisplayGammaTableCapacity(id)
        guard (2...16384).contains(capacity) else { throw ColorError("No usable colour table") }
        var r = [CGGammaValue](repeating: 0, count: Int(capacity)), g = r, b = r
        var count: UInt32 = 0
        let error = CGGetDisplayTransferByTable(id, capacity, &r, &g, &b, &count)
        guard error == .success, count > 1, count <= capacity else { throw ColorError("Could not read the colour baseline") }
        let ramp = Ramp(red: Array(r.prefix(Int(count))), green: Array(g.prefix(Int(count))),
                        blue: Array(b.prefix(Int(count))))
        guard (ramp.red + ramp.green + ramp.blue).allSatisfy({
            $0.isFinite && (0...1).contains($0)
        }), max(ramp.red.max() ?? 0, ramp.green.max() ?? 0, ramp.blue.max() ?? 0) > 0.05 else {
            throw ColorError("Colour baseline is invalid")
        }
        return ramp
    }

    private func write(_ ramp: Ramp, to id: UInt32) throws {
        let result = CGSetDisplayTransferByTable(id, UInt32(ramp.red.count),
            ramp.red, ramp.green, ramp.blue)
        guard result == .success else { throw ColorError("macOS rejected colour control (\(result.rawValue))") }
    }

    private func restore(_ id: String) {
        guard let display = displays[id], let baseline = baselines[id],
              let expected = written[id] else { return }
        // Do not overwrite a different app's newer adjustment.
        if let current = try? read(display.displayID), current.isClose(to: expected) {
            do { try write(baseline, to: display.displayID) }
            catch { RelayLog.write("Could not restore \(display.name) colour: \(error)") }
        }
        baselines[id] = nil
        written[id] = nil
    }

    private func preferenceKey(_ id: String) -> String { "displayColor.\(id)" }
    private func persist(_ id: String) {
        guard let settings = states[id]?.settings, let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: preferenceKey(id))
    }
    private struct ColorError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
