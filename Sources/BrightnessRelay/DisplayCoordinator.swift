import BrightnessCore
import BrightnessHardware
import Foundation

enum DisplayControlMethod: String, Sendable {
    case detecting
    case hardwareDDC
    case softwareDimming
}

enum DisplayBrightnessOrigin: String, Sendable {
    case unavailable
    case liveHardware
    case lastSet
    case liveSoftware
}

enum DisplayConnectionState: String, Sendable {
    case connected
    case disconnecting
    case disconnected
    case reconnecting

    var isConnected: Bool { self == .connected }
    var isTransitioning: Bool { self == .disconnecting || self == .reconnecting }
}

struct ManagedDisplayState: Identifiable, Sendable {
    let display: ExternalDisplay
    var brightness: UInt16?
    var brightnessOrigin: DisplayBrightnessOrigin
    var controlMethod: DisplayControlMethod
    var followsAutomatic: Bool
    var connectionState: DisplayConnectionState
    var lastReadAt: Date?
    var lastError: String?
    var calibration = BrightnessCalibration()

    var id: String { display.id }
}

struct DisplayApplySummary: Sendable {
    let target: UInt16
    let changedDisplays: Int
    let hardwareWrites: Int
    let softwareWrites: Int
}

struct DisplayShadeRequest: Sendable {
    let display: ExternalDisplay
    let brightness: UInt16
    let isConnected: Bool
    let usesSoftwareDimming: Bool
}

final class DisplayCoordinator: @unchecked Sendable {
    typealias StateHandler = @Sendable ([ManagedDisplayState]) -> Void
    typealias ShadeHandler = @Sendable (DisplayShadeRequest) -> Void

    private let hardware: ExternalDDCController
    private let connection: DisplayConnectionController
    private let queue = DispatchQueue(label: "dev.pranav.brightness-relay.displays")
    private let defaults: UserDefaults
    private var states: [ManagedDisplayState] = []
    private var onChanged: StateHandler?
    private var onShade: ShadeHandler?
    private var latestAutomaticTarget: UInt16?
    private var latestSourceBrightness: Double?
    private var latestSourceAt: Date?

    init(
        hardware: ExternalDDCController,
        connection: DisplayConnectionController = DisplayConnectionController(),
        defaults: UserDefaults = .standard
    ) {
        self.hardware = hardware
        self.connection = connection
        self.defaults = defaults

        do {
        for outcome in try connection.recoverAll() {
            if let error = outcome.error {
                RelayLog.write("Startup recovery for \(outcome.display.name) is still pending: \(error)")
            } else {
                RelayLog.write("Recovered \(outcome.display.name) after an interrupted disconnect")
            }
        }
        } catch {
            RelayLog.write("Display recovery ledger could not be read: \(error)")
        }
        states = enumerateDisplays(preserving: [])
    }

    var connectedDisplayCount: Int {
        queue.sync { states.filter(\.connectionState.isConnected).count }
    }

    var connectionControlAvailable: Bool {
        connection.isAvailable
    }

    func snapshot() -> [ManagedDisplayState] {
        queue.sync { states }
    }

    func setOnChanged(_ handler: @escaping StateHandler) {
        queue.async { [weak self] in
            guard let self else { return }
            self.onChanged = handler
            handler(self.states)
        }
    }

    func setShadeHandler(_ handler: @escaping ShadeHandler) {
        queue.async { [weak self] in
            guard let self else { return }
            self.onShade = handler
            for state in self.states {
                self.publishShade(for: state)
            }
        }
    }

    func refresh(readHardware: Bool = true) {
        queue.async { [weak self] in
            guard let self else { return }
            self.states = self.enumerateDisplays(preserving: self.states)
            if readHardware {
                for index in self.states.indices
                    where self.states[index].connectionState.isConnected
                {
                    self.readBrightness(at: index)
                }
            }
            self.publish()
        }
    }

    func applyAutomatic(target: UInt16, deadband: UInt16,
                        sourceBrightness: Double? = nil) throws -> DisplayApplySummary {
        try queue.sync {
            guard states.contains(where: { $0.connectionState.isConnected }) else {
                throw BrightnessHardwareError.noExternalDDCDisplay
            }
            latestAutomaticTarget = target
            if let sourceBrightness {
                latestSourceBrightness = sourceBrightness
                latestSourceAt = Date()
            }
            var changed = 0
            var hardwareWrites = 0
            var softwareWrites = 0

            for index in states.indices
                where states[index].followsAutomatic &&
                    states[index].connectionState.isConnected
            {
                let displayTarget = sourceBrightness.map {
                    states[index].calibration.isCalibrated
                        ? UInt16(states[index].calibration.luminance(forBuiltin: $0))
                        : target
                } ?? target
                if states[index].controlMethod != .detecting,
                   let current = states[index].brightness,
                   abs(Int(current) - Int(displayTarget)) < Int(deadband)
                {
                    continue
                }
                guard let method = apply(target: displayTarget, at: index) else { continue }
                changed += 1
                if method == .hardwareDDC {
                    hardwareWrites += 1
                } else {
                    softwareWrites += 1
                }
            }
            publish()
            return DisplayApplySummary(
                target: target,
                changedDisplays: changed,
                hardwareWrites: hardwareWrites,
                softwareWrites: softwareWrites
            )
        }
    }

    func learnCalibration(displayID: String, reset: Bool = false) {
        queue.async { [weak self] in
            guard let self, let index = self.states.firstIndex(where: { $0.id == displayID }) else { return }
            if reset {
                self.states[index].calibration.reset()
            } else {
                guard let source = self.latestSourceBrightness,
                      let date = self.latestSourceAt, Date().timeIntervalSince(date) < 2700,
                      let brightness = self.states[index].brightness else {
                    self.states[index].lastError = "Sync the Air before saving a brightness match"
                    self.publish()
                    return
                }
                self.states[index].calibration.record(builtin: source, luminance: Int(brightness))
                self.states[index].followsAutomatic = true
                self.defaults.set(true, forKey: self.preferenceKey(displayID, "followsAutomatic"))
            }
            if let data = try? JSONEncoder().encode(self.states[index].calibration) {
                self.defaults.set(data, forKey: self.preferenceKey(displayID, "calibration"))
            }
            self.states[index].lastError = nil
            self.publish()
        }
    }

    func setManualBrightness(_ target: UInt16, displayID: String) {
        queue.async { [weak self] in
            guard let self,
                  let index = self.states.firstIndex(where: { $0.id == displayID }),
                  self.states[index].connectionState.isConnected
            else { return }
            self.states[index].followsAutomatic = false
            self.defaults.set(false, forKey: self.preferenceKey(displayID, "followsAutomatic"))
            _ = self.apply(target: min(target, 100), at: index)
            self.publish()
        }
    }

    func adjustManualBrightness(
        direction: BrightnessStepDirection,
        fine: Bool
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            var handled = false
            for index in self.states.indices
                where self.states[index].connectionState.isConnected
            {
                let current = self.states[index].brightness ??
                    self.latestAutomaticTarget ?? 50
                let target = BrightnessStepPolicy.next(
                    from: current,
                    direction: direction,
                    fine: fine
                )
                self.states[index].followsAutomatic = false
                self.defaults.set(
                    false,
                    forKey: self.preferenceKey(
                        self.states[index].id,
                        "followsAutomatic"
                    )
                )
                _ = self.apply(target: target, at: index)
                handled = true
            }
            if handled { self.publish() }
        }
    }

    func setFollowsAutomatic(_ follows: Bool, displayID: String) {
        queue.async { [weak self] in
            guard let self,
                  let index = self.states.firstIndex(where: { $0.id == displayID })
            else { return }
            self.states[index].followsAutomatic = follows
            self.defaults.set(follows, forKey: self.preferenceKey(displayID, "followsAutomatic"))
            if follows,
               let target = self.latestAutomaticTarget,
               self.states[index].connectionState.isConnected
            {
                _ = self.apply(target: self.calibratedTarget(at: index, fallback: target), at: index)
            }
            self.publish()
        }
    }

    func setConnected(_ enabled: Bool, displayID: String) {
        queue.async { [weak self] in
            guard let self,
                  let index = self.states.firstIndex(where: { $0.id == displayID })
            else { return }
            if enabled {
                self.reconnectDisplay(at: index)
            } else {
                self.disconnectDisplay(at: index)
            }
        }
    }

    func reconnectAll() {
        queue.async { [weak self] in
            guard let self else { return }
            let disconnectedIDs = self.states
                .filter { !$0.connectionState.isConnected }
                .map(\.id)
            for displayID in disconnectedIDs {
                guard let index = self.states.firstIndex(where: { $0.id == displayID }) else {
                    continue
                }
                self.reconnectDisplay(at: index)
            }
        }
    }

    func redetectHardware() {
        queue.async { [weak self] in
            guard let self else { return }
            for index in self.states.indices
                where self.states[index].connectionState.isConnected
            {
                self.states[index].controlMethod = .detecting
                self.defaults.removeObject(
                    forKey: self.preferenceKey(
                        self.states[index].id,
                        "controlMethod"
                    )
                )
                if let brightness = self.states[index].brightness {
                    _ = self.apply(target: brightness, at: index)
                }
                self.readBrightness(at: index)
            }
            self.publish()
        }
    }

    private func disconnectDisplay(at index: Int) {
        guard states.indices.contains(index),
              states[index].connectionState == .connected
        else { return }

        guard DisplayConnectionPolicy.canDisconnect(
            connectedDisplayCount: states.filter(\.connectionState.isConnected).count
        ) else {
            states[index].lastError = String(describing: DisplayConnectionError.lastActiveDisplay)
            publish()
            return
        }

        let display = states[index].display
        states[index].connectionState = .disconnecting
        states[index].lastError = nil
        publish()

        do {
            try connection.disconnect(display)
            guard let currentIndex = states.firstIndex(where: { $0.id == display.id }) else {
                return
            }
            states[currentIndex].connectionState = .disconnected
            states[currentIndex].lastError = nil
            publishShade(for: states[currentIndex])
            RelayLog.write("Disconnected \(display.name) from the macOS display layout")
        } catch {
            guard let currentIndex = states.firstIndex(where: { $0.id == display.id }) else {
                return
            }
            states[currentIndex].connectionState = connection.isOnline(display)
                ? .connected
                : .disconnected
            states[currentIndex].lastError = String(describing: error)
            RelayLog.write("Could not disconnect \(display.name): \(error)")
        }
        publish()
    }

    private func reconnectDisplay(at index: Int) {
        guard states.indices.contains(index),
              !states[index].connectionState.isConnected,
              !states[index].connectionState.isTransitioning
        else { return }

        let stableID = states[index].id
        let display = states[index].display
        let savedBrightness = states[index].brightness
        let followsAutomatic = states[index].followsAutomatic
        states[index].connectionState = .reconnecting
        states[index].lastError = nil
        publish()

        do {
            _ = try connection.reconnect(display)
            Thread.sleep(forTimeInterval: 0.25)
            states = enumerateDisplays(preserving: states)
            guard let currentIndex = states.firstIndex(where: { $0.id == stableID }) else {
                throw DisplayConnectionError.postconditionFailed(
                    "\(display.name) reconnected but was not enumerated."
                )
            }
            states[currentIndex].connectionState = .connected
            states[currentIndex].lastError = nil
            let target = followsAutomatic ? (latestAutomaticTarget ?? savedBrightness) : savedBrightness
            if let target {
                _ = apply(target: followsAutomatic ? calibratedTarget(at: currentIndex, fallback: target) : target,
                          at: currentIndex)
            } else {
                readBrightness(at: currentIndex)
            }
            RelayLog.write("Reconnected \(display.name) to the macOS display layout")
        } catch {
            guard let currentIndex = states.firstIndex(where: { $0.id == stableID }) else {
                return
            }
            states[currentIndex].connectionState = .disconnected
            states[currentIndex].lastError = String(describing: error)
            RelayLog.write("Could not reconnect \(display.name): \(error)")
        }
        publish()
    }

    private func enumerateDisplays(
        preserving oldStates: [ManagedDisplayState]
    ) -> [ManagedDisplayState] {
        let oldByID = Dictionary(uniqueKeysWithValues: oldStates.map { ($0.id, $0) })
        let liveDisplays = hardware.displays()
        let liveIDs = Set(liveDisplays.map(\.id))
        var result: [ManagedDisplayState] = liveDisplays.map { display in
            try? connection.ledger.remove(displayID: display.id)
            if let old = oldByID[display.id] {
                return ManagedDisplayState(
                    display: display,
                    brightness: old.brightness,
                    brightnessOrigin: old.brightnessOrigin,
                    controlMethod: old.controlMethod,
                    followsAutomatic: old.followsAutomatic,
                    connectionState: .connected,
                    lastReadAt: old.lastReadAt,
                    lastError: liveDisplays.count > 1 &&
                        old.lastError == String(describing: DisplayConnectionError.lastActiveDisplay)
                        ? nil : old.lastError,
                    calibration: old.calibration
                )
            }
            return makeInitialState(display: display, connectionState: .connected)
        }

        var offlineByID: [String: ExternalDisplay] = [:]
        for display in connection.disconnectedDisplays() where !liveIDs.contains(display.id) {
            offlineByID[display.id] = display
        }
        for state in oldStates
            where !state.connectionState.isConnected && !liveIDs.contains(state.id)
        {
            offlineByID[state.id] = state.display
        }

        for display in offlineByID.values {
            if let old = oldByID[display.id] {
                result.append(
                    ManagedDisplayState(
                        display: display,
                        brightness: old.brightness,
                        brightnessOrigin: old.brightnessOrigin,
                        controlMethod: old.controlMethod,
                        followsAutomatic: old.followsAutomatic,
                        connectionState: .disconnected,
                        lastReadAt: old.lastReadAt,
                        lastError: old.lastError,
                        calibration: old.calibration
                    )
                )
            } else {
                result.append(
                    makeInitialState(display: display, connectionState: .disconnected)
                )
            }
        }

        return result.sorted { left, right in
            if left.connectionState.isConnected != right.connectionState.isConnected {
                return left.connectionState.isConnected
            }
            if left.display.isMain != right.display.isMain {
                return left.display.isMain
            }
            return left.display.name.localizedCaseInsensitiveCompare(
                right.display.name
            ) == .orderedAscending
        }
    }

    private func makeInitialState(
        display: ExternalDisplay,
        connectionState: DisplayConnectionState
    ) -> ManagedDisplayState {
        let followsKey = preferenceKey(display.id, "followsAutomatic")
        let follows = defaults.object(forKey: followsKey) == nil
            ? true
            : defaults.bool(forKey: followsKey)
        let method = defaults.string(forKey: preferenceKey(display.id, "controlMethod"))
            .flatMap(DisplayControlMethod.init(rawValue:)) ?? .detecting
        let lastBrightnessObject = defaults.object(
            forKey: preferenceKey(display.id, "lastBrightness")
        ) as? NSNumber
        let lastBrightness = lastBrightnessObject.map {
            UInt16(min(max($0.intValue, 0), 100))
        }

        return ManagedDisplayState(
            display: display,
            brightness: lastBrightness,
            brightnessOrigin: method == .softwareDimming && lastBrightness != nil
                ? .liveSoftware
                : (lastBrightness == nil ? .unavailable : .lastSet),
            controlMethod: method,
            followsAutomatic: follows,
            connectionState: connectionState,
            lastReadAt: nil,
            lastError: nil,
            calibration: defaults.data(forKey: preferenceKey(display.id, "calibration"))
                .flatMap { try? JSONDecoder().decode(BrightnessCalibration.self, from: $0) }
                ?? BrightnessCalibration()
        )
    }

    @discardableResult
    private func apply(target: UInt16, at index: Int) -> DisplayControlMethod? {
        guard states.indices.contains(index),
              states[index].connectionState.isConnected
        else { return nil }

        let boundedTarget = min(target, 100)
        let display = states[index].display

        if states[index].controlMethod != .softwareDimming {
            do {
                try hardware.set(percentage: boundedTarget, on: display)
                states[index].brightness = boundedTarget
                states[index].brightnessOrigin = .lastSet
                states[index].controlMethod = .hardwareDDC
                states[index].lastError = nil
                persist(state: states[index])
                publishShade(for: states[index])
                RelayLog.write("Applied \(boundedTarget)% to \(display.name) through DDC")
                return .hardwareDDC
            } catch {
                states[index].controlMethod = .softwareDimming
                states[index].lastError = "DDC unavailable — using software dimming"
                RelayLog.write("\(display.name) DDC unavailable; using software dimming: \(error)")
            }
        }

        states[index].brightness = boundedTarget
        states[index].brightnessOrigin = .liveSoftware
        persist(state: states[index])
        publishShade(for: states[index])
        return .softwareDimming
    }

    private func readBrightness(at index: Int) {
        guard states.indices.contains(index),
              states[index].connectionState.isConnected
        else { return }
        do {
            let reading = try hardware.readBrightness(of: states[index].display)
            states[index].brightness = reading.percentage
            states[index].brightnessOrigin = .liveHardware
            states[index].controlMethod = .hardwareDDC
            states[index].lastReadAt = Date()
            states[index].lastError = nil
            persist(state: states[index])
        } catch {
            if states[index].brightness == nil {
                states[index].brightnessOrigin = .unavailable
            } else if states[index].controlMethod == .softwareDimming {
                states[index].brightnessOrigin = .liveSoftware
            } else {
                states[index].brightnessOrigin = .lastSet
            }
            if states[index].lastError == nil {
                states[index].lastError = "Live DDC readback unavailable"
            }
        }
    }

    private func persist(state: ManagedDisplayState) {
        defaults.set(
            state.controlMethod.rawValue,
            forKey: preferenceKey(state.id, "controlMethod")
        )
        if let brightness = state.brightness {
            defaults.set(Int(brightness), forKey: preferenceKey(state.id, "lastBrightness"))
        }
    }

    private func preferenceKey(_ displayID: String, _ setting: String) -> String {
        "dev.pranav.brightness-relay.display.\(displayID).\(setting)"
    }

    private func calibratedTarget(at index: Int, fallback: UInt16) -> UInt16 {
        guard let source = latestSourceBrightness,
              let date = latestSourceAt, Date().timeIntervalSince(date) < 2700,
              states[index].calibration.isCalibrated else { return fallback }
        return UInt16(states[index].calibration.luminance(forBuiltin: source))
    }

    private func publishShade(for state: ManagedDisplayState) {
        onShade?(
            DisplayShadeRequest(
                display: state.display,
                brightness: state.brightness ?? 100,
                isConnected: state.connectionState.isConnected,
                usesSoftwareDimming: state.controlMethod == .softwareDimming
            )
        )
    }

    private func publish() {
        onChanged?(states)
    }
}
