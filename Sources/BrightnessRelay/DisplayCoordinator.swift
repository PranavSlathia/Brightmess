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
    var calibration = LearnedCurve()
    var mappedTarget: UInt16?
    var learningNote: String?
    var extraDim: UInt16 = 0

    var id: String { display.id }
}

struct DisplayApplySummary: Sendable {
    let target: UInt16
    let changedDisplays: Int
}

struct DisplayShadeRequest: Sendable {
    let display: ExternalDisplay
    let brightness: UInt16
    let isConnected: Bool
    let usesSoftwareDimming: Bool
    let extraDim: UInt16
}

protocol DisplayDriver {
    func displays() -> [ExternalDisplay]
    func set(percentage: UInt16, on display: ExternalDisplay) throws
    func readBrightness(of display: ExternalDisplay) throws -> DDCValue
}
extension ExternalDDCController: DisplayDriver {}

final class DisplayCoordinator: @unchecked Sendable {
    typealias StateHandler = @Sendable ([ManagedDisplayState]) -> Void
    typealias ShadeHandler = @Sendable (DisplayShadeRequest) -> Void

    private let hardware: any DisplayDriver
    private let connection: DisplayConnectionController
    private let queue = DispatchQueue(label: "dev.pranav.brightness-relay.displays")
    private let defaults: UserDefaults
    private var states: [ManagedDisplayState] = []
    private var onChanged: StateHandler?
    private var onShade: ShadeHandler?
    private var latestAutomaticTarget: UInt16?
    private var latestSourceBrightness: Double?
    private var latestSourceAt: Date?
    private var hardwareWrites = 0, softwareWrites = 0
    var writeCounts: (hardware: Int, software: Int) { queue.sync { (hardwareWrites, softwareWrites) } }
    private var baseCurve = try! BrightnessCurve()
    private var ramps: [String: LevelTransition] = [:]
    private var ticks: [String: DispatchWorkItem] = [:]
    private var lastHardware: [String: Double] = [:]
    private struct Gesture { let bin: Int?; var stable: Bool; var level: UInt16 }
    private var gestures: [String: Gesture] = [:]
    private var keyEnds: [String: DispatchWorkItem] = [:]
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private var freshBin: Int? {
        guard let b = latestSourceBrightness, let at = latestSourceAt,
              Date().timeIntervalSince(at) < 90 else { return nil }
        return Int((b * 100).rounded())
    }

    init(
        hardware: any DisplayDriver,
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

    func invalidateSource() {
        queue.sync { latestSourceAt = nil; latestSourceBrightness = nil; for id in gestures.keys { gestures[id]?.stable = false } }
    }

    func applyAutomatic(target: UInt16, deadband: UInt16,
                        sourceBrightness: Double? = nil, measuredAt: Date? = nil, baseCurve: BrightnessCurve) throws -> DisplayApplySummary {
        try queue.sync {
            guard states.contains(where: { $0.connectionState.isConnected }) else {
                throw BrightnessHardwareError.noExternalDDCDisplay
            }
            self.baseCurve = baseCurve
            latestAutomaticTarget = target
            latestSourceBrightness = sourceBrightness
            latestSourceAt = sourceBrightness == nil ? nil : measuredAt
            let bin = freshBin
            for id in gestures.keys where gestures[id]?.bin != bin { gestures[id]?.stable = false }
            var changed = 0
            for i in states.indices where states[i].connectionState.isConnected {
                let target = calibratedTarget(at: i, fallback: target)
                states[i].mappedTarget = target
                guard states[i].followsAutomatic, gestures[states[i].id] == nil else { continue }
                if let current = states[i].brightness, ramps[states[i].id] == nil,
                   abs(Int(current)-Int(target)) < Int(max(1, deadband)) { continue }
                if drive(target, at: i, fade: true) { changed += 1 }
            }
            publish()
            return DisplayApplySummary(target: target, changedDisplays: changed)
        }
    }

    private func saveCurve(_ i: Int) {
        if let data = try? JSONEncoder().encode(states[i].calibration) {
            defaults.set(data, forKey: preferenceKey(states[i].id, "calibrationV2"))
        }
    }

    func editCurve(displayID: String, reset: Bool) {
        queue.async {
            guard let i = self.states.firstIndex(where: { $0.id == displayID }) else { return }
            if reset { self.states[i].calibration.reset() } else { self.states[i].calibration.undo() }
            self.states[i].learningNote = reset ? "Calibration reset" : "Last match undone"
            self.saveCurve(i)
            if let target = self.latestAutomaticTarget {
                let level = self.calibratedTarget(at: i, fallback: target)
                self.states[i].mappedTarget = level
                if self.states[i].followsAutomatic && self.states[i].connectionState.isConnected {
                    _ = self.drive(level, at: i, fade: true)
                }
            }
            self.publish()
        }
    }

    func setExtraDim(_ amount: UInt16, displayID: String) {
        queue.async {
            guard let i = self.states.firstIndex(where: { $0.id == displayID }),
                  self.states[i].controlMethod == .hardwareDDC else { return }
            self.states[i].extraDim = min(60, amount)
            self.defaults.set(Int(self.states[i].extraDim), forKey: self.preferenceKey(displayID, "extraDim"))
            self.publishShade(for: self.states[i]); self.publish()
        }
    }

    private func beginOrUpdate(_ level: UInt16, index i: Int) {
        let id = states[i].id
        if gestures[id] == nil {
            gestures[id] = Gesture(bin: freshBin, stable: freshBin != nil, level: level)
        } else { gestures[id]?.level = level }
        _ = drive(level, at: i, fade: false)
    }

    private func finishGesture(_ id: String) {
        keyEnds.removeValue(forKey: id)?.cancel()
        guard let g = gestures.removeValue(forKey: id), let i = states.firstIndex(where: { $0.id == id }),
              states[i].connectionState.isConnected else { return }
        guard states[i].followsAutomatic else { states[i].learningNote = "Manual · not learning"; publish(); return }
        guard let x = freshBin, x == g.bin, g.stable else {
            states[i].learningNote = "Not learned: need a stable, fresh Air level"
            if freshBin != nil, let mapped = states[i].mappedTarget { _ = drive(mapped, at: i, fade: true) }
            publish(); return
        }
        states[i].calibration.learn(Double(x)/100, Int(g.level)); saveCurve(i)
        states[i].mappedTarget = g.level
        states[i].learningNote = "Learned: Air \(x)% → \(g.level)%"
        publish()
    }

    func beginSlider(_ id: String) {
        queue.async {
            guard let i = self.states.firstIndex(where: { $0.id == id }), self.states[i].connectionState.isConnected else { return }
            self.keyEnds.removeValue(forKey: id)?.cancel()
            self.cancelMotion(id)
            self.gestures[id] = Gesture(bin: self.freshBin, stable: self.freshBin != nil, level: self.states[i].brightness ?? 50)
        }
    }
    func cancelSlider(_ id: String) {
        queue.async {
            self.gestures[id] = nil
            if let i = self.states.firstIndex(where: { $0.id == id }), self.states[i].followsAutomatic,
               let goal = self.states[i].mappedTarget { _ = self.drive(goal, at: i, fade: true) }
        }
    }

    func setManualBrightness(_ target: UInt16, displayID: String, final: Bool = false) {
        queue.async {
            guard let i = self.states.firstIndex(where: { $0.id == displayID }), self.states[i].connectionState.isConnected else { return }
            self.beginOrUpdate(min(100,target), index: i)
            if final { self.finishGesture(displayID) }
            self.publish()
        }
    }

    func adjustManualBrightness(direction: BrightnessStepDirection, fine: Bool) {
        queue.async { [self] in
            for i in self.states.indices where self.states[i].connectionState.isConnected {
                let id = self.states[i].id
                // A user's just-released slider may be waiting for the DDC
                // rate limit. Step from that intent, not the previous backlight.
                let manualGoal = self.ramps[id].flatMap { $0.duration == 0 ? $0.goal : nil }
                let from = self.gestures[id]?.level ?? manualGoal ?? self.states[i].brightness ?? 50
                self.beginOrUpdate(BrightnessStepPolicy.next(from: from, direction: direction, fine: fine), index: i)
                self.keyEnds[id]?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.finishGesture(id) }
                self.keyEnds[id] = work; self.queue.asyncAfter(deadline: .now()+1, execute: work)
            }
            self.publish()
        }
    }

    private func cancelMotion(_ id: String) {
        ticks.removeValue(forKey: id)?.cancel(); ramps[id] = nil
    }

    @discardableResult private func drive(_ goal: UInt16, at i: Int, fade: Bool) -> Bool {
        guard states[i].connectionState.isConnected else { return false }
        let id = states[i].id
        if fade, ramps[id]?.goal == goal { return false }
        cancelMotion(id)
        if states[i].brightness == goal && states[i].controlMethod != .detecting { return false }
        ramps[id] = LevelTransition(start: states[i].brightness ?? goal, goal: goal,
                                    began: now, duration: fade ? 0.9 : 0)
        step(id); return true
    }

    private func step(_ id: String) {
        guard let ramp = ramps[id], let i = states.firstIndex(where: { $0.id == id }),
              states[i].connectionState.isConnected else { cancelMotion(id); return }
        let hardware = states[i].controlMethod != .softwareDimming
        let remaining = hardware ? (lastHardware[id] ?? -.infinity) + 0.251 - now : 0
        if remaining <= 0 {
            let value = ramp.value(at: now)
            if states[i].brightness != value || states[i].controlMethod == .detecting {
                _ = apply(target: value, at: i, save: value == ramp.goal)
                if hardware { lastHardware[id] = now }
                publish()
            }
            if value == ramp.goal { persist(state: states[i]); cancelMotion(id); return }
        }
        let delay = remaining > 0 ? remaining : (hardware ? 0.251 : 0.05)
        let work = DispatchWorkItem { [weak self] in self?.step(id) }
        ticks[id] = work; queue.asyncAfter(deadline: .now()+delay, execute: work)
    }

    func setFollowsAutomatic(_ follows: Bool, displayID: String) {
        queue.async { [weak self] in
            guard let self,
                  let index = self.states.firstIndex(where: { $0.id == displayID })
            else { return }
            self.cancelMotion(displayID); self.keyEnds.removeValue(forKey: displayID)?.cancel(); self.gestures[displayID] = nil
            self.states[index].followsAutomatic = follows
            self.defaults.set(follows, forKey: self.preferenceKey(displayID, "followsAutomatic"))
            if follows,
               let target = self.latestAutomaticTarget,
               self.states[index].connectionState.isConnected
            {
                _ = self.drive(self.calibratedTarget(at: index, fallback: target), at: index, fade: true)
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
                if self.now - (self.lastHardware[self.states[index].id] ?? -.infinity) >= 1 {
                    self.readBrightness(at: index)
                }
                if self.states[index].controlMethod == .detecting, let brightness = self.states[index].brightness {
                    _ = self.drive(brightness, at: index, fade: false)
                }
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
        cancelMotion(display.id); keyEnds.removeValue(forKey: display.id)?.cancel(); gestures[display.id] = nil
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
                states[currentIndex].brightness = nil // IO route was rebuilt; cached output is not proof of restore.
                _ = drive(followsAutomatic ? calibratedTarget(at: currentIndex, fallback: target) : target, at: currentIndex, fade: true)
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
                    calibration: old.calibration, mappedTarget: old.mappedTarget, learningNote: old.learningNote, extraDim: old.extraDim
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
                        calibration: old.calibration, mappedTarget: old.mappedTarget, learningNote: old.learningNote, extraDim: old.extraDim
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
            calibration: initialCurve(display.id),
            extraDim: UInt16(clamping: min(60,max(0,defaults.integer(forKey: preferenceKey(display.id, "extraDim")))))
        )
    }

    private func initialCurve(_ id: String) -> LearnedCurve {
        let key = preferenceKey(id, "calibrationV2")
        let stored = defaults.data(forKey: key)
        if let stored, let curve = try? JSONDecoder().decode(LearnedCurve.self, from: stored) { return curve }
        let old = defaults.data(forKey: preferenceKey(id, "calibration"))
            .flatMap { try? JSONDecoder().decode(BrightnessCalibration.self, from: $0) }
        let migrated = LearnedCurve(legacy: old)
        if stored == nil, old != nil, let data = try? JSONEncoder().encode(migrated) { defaults.set(data, forKey: key) }
        return migrated
    }

    @discardableResult
    private func apply(target: UInt16, at index: Int, save: Bool = true) -> DisplayControlMethod? {
        guard states.indices.contains(index),
              states[index].connectionState.isConnected
        else { return nil }

        let boundedTarget = min(target, 100)
        let display = states[index].display

        if states[index].controlMethod != .softwareDimming {
            do {
                try hardware.set(percentage: boundedTarget, on: display)
                hardwareWrites += 1
                states[index].brightness = boundedTarget
                states[index].brightnessOrigin = .lastSet
                states[index].controlMethod = .hardwareDDC
                states[index].lastError = nil
                if save { persist(state: states[index]) }
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
        softwareWrites += 1
        if save { persist(state: states[index]) }
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
        return states[index].calibration.target(source, base: baseCurve)
    }

    private func publishShade(for state: ManagedDisplayState) {
        onShade?(
            DisplayShadeRequest(
                display: state.display,
                brightness: state.brightness ?? 100,
                isConnected: state.connectionState.isConnected,
                usesSoftwareDimming: state.controlMethod == .softwareDimming,
                extraDim: state.controlMethod == .hardwareDDC && state.brightness == 0 ? state.extraDim : 0
            )
        )
    }

    private func publish() {
        onChanged?(states)
    }
}
