import BrightnessCore
import BrightnessHardware
import Foundation

/// All DDC calls run on the coordinator's existing serial hardware queue.
@MainActor final class SamsungSources: ObservableObject {
    private struct Saved: Codable { let target: ExternalDisplay; let profile: MonitorSourceProfile }
    struct PendingProof {
        let token: UUID, port: MonitorPort, code: UInt16, returnCode: UInt16
        let location: String, finishedAt: Date
        let targetReadback: UInt16?
    }
    private let coordinator: DisplayCoordinator
    private let defaults: UserDefaults
    private let key = "Brightmess.SamsungSources.v1"
    private let fixture: Bool
    private let delay: (UInt64) async throws -> Void
    private var work: Task<Void, Never>?
    @Published private(set) var target: ExternalDisplay?
    @Published private(set) var profile = MonitorSourceProfile()
    @Published private(set) var inputValue: UInt16?
    @Published private(set) var inputReadAt: Date?
    @Published private(set) var busy = false
    @Published private(set) var notice = "Read the current input to start setup."
    @Published private(set) var pending: PendingProof?
    private var operation = UUID()

    init(coordinator: DisplayCoordinator, defaults: UserDefaults, fixture: Bool = false,
         delay: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.coordinator = coordinator; self.defaults = defaults; self.fixture = fixture
        self.delay = delay
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Saved.self, from: data),
           Self.supports(saved.target), saved.profile.version == 1 { target = saved.target; profile = saved.profile }
    }
    static func supports(_ display: ExternalDisplay) -> Bool {
        display.vendorID == 0x4c2d && (display.productID == 0x1016 || display.name == "LU28R55")
    }
    func updateDisplays(_ displays: [ManagedDisplayState]) {
        let matches = displays.map(\.display).filter(Self.supports)
        let next = target.flatMap { old in matches.first { $0.id == old.id } } ?? (matches.count == 1 ? matches.first : nil)
        guard let next, next != target else { return }
        if let old = target, old.id != next.id { profile = MonitorSourceProfile() }
        if let old = target, old.id != next.id || old.ioLocation != next.ioLocation { stop() }
        target = next; save()
        if fixture {
            inputValue = 15; inputReadAt = Date(); profile.observeReturn(15, location: next.ioLocation)
            notice = "Fixture · HDMI sources need a verified round trip"
        }
    }
    private func save() {
        guard let target, let data = try? JSONEncoder().encode(Saved(target: target, profile: profile)) else { return }
        defaults.set(data, forKey: key)
    }
    func stop() {
        let interrupted = busy
        work?.cancel(); work = nil; operation = UUID(); busy = false
        pending = nil; inputValue = nil; inputReadAt = nil
        if interrupted { notice = "Source operation interrupted. Restore DisplayPort with the Samsung's JOG control if needed. Nothing will be replayed." }
    }
    private func current(_ token: UUID, _ display: ExternalDisplay) -> Bool {
        operation == token && !Task.isCancelled && target?.id == display.id && target?.ioLocation == display.ioLocation
    }
    func route(_ port: MonitorPort) -> MonitorSourceRoute { profile.route(port) }
    func canActivate(_ port: MonitorPort) -> Bool {
        guard let target else { return false }
        return !busy && profile.canActivate(port, location: target.ioLocation)
    }
    func label(for code: UInt16) -> String {
        MonitorPort.allCases.first { route($0).code == code }.map {
            route($0).name == $0.title ? $0.title : route($0).name + " · " + $0.title
        } ?? "Input code \(code)"
    }
    func readLabel(at now: Date) -> String {
        guard let inputValue, let at = inputReadAt else { return "Current input not measured" }
        let age = max(0, Int(now.timeIntervalSince(at)))
        let time = age < 1 ? "now" : age < 60 ? "\(age)s ago" : "\(age / 60)m ago"
        return "Read \(label(for: inputValue)) · \(time)"
    }
    @discardableResult func configure(_ port: MonitorPort, name: String, code: UInt16) -> Bool {
        guard !busy, profile.configure(port, name: name, code: code) else {
            notice = "Use a name up to 32 characters and a distinct DDC code from 1–255."; return false
        }
        pending = nil; save(); notice = "Saved. Changing a code requires a new physical round trip."
        return true
    }
    func revoke(_ port: MonitorPort) { guard !busy else { return }; profile.revoke(port); pending = nil; save() }
    func refresh() {
        guard !busy, let target, !fixture else { return }
        busy = true
        let token = UUID(); operation = token
        work = Task { [weak self] in
            guard let self else { return }
            defer { if operation == token { self.busy = false; self.work = nil } }
            do {
                let value = try await coordinator.readMonitorInput(target)
                guard current(token, target) else { return }
                inputValue = value; inputReadAt = Date()
                profile.observeReturn(value, location: target.ioLocation); save()
                notice = "Input readback received. No source change sent."
            } catch { if operation == token { inputValue = nil; inputReadAt = nil; notice = "Input unavailable. No command queued. " + String(describing: error) } }
        }
    }
    func activate(_ port: MonitorPort) {
        guard canActivate(port), let target else {
            notice = busy ? "A source operation is already running." : "Verify this source and the return to DisplayPort first. No command sent."
            return
        }
        guard !fixture else { notice = "Fixture action · no hardware command"; return }
        busy = true; pending = nil
        let token = UUID(); operation = token
        let code = route(port).code, name = route(port).name
        work = Task { [weak self] in
            guard let self else { return }
            defer { if operation == token { self.busy = false; self.work = nil } }
            do {
                guard current(token, target) else { return }
                try await coordinator.writeMonitorInput(code, on: target)
                guard current(token, target) else { return }
                inputValue = nil; inputReadAt = nil; notice = "Command sent · " + name
                try await delay(300_000_000)
                guard current(token, target) else { return }
                if let value = try? await coordinator.readMonitorInput(target) {
                    guard current(token, target) else { return }
                    inputValue = value; inputReadAt = Date()
                    notice = value == code ? "Command sent · input readback matches " + name : "Command sent; monitor reports " + label(for: value)
                }
            } catch { if operation == token { notice = "Source change failed; nothing queued. " + String(describing: error) } }
        }
    }

    /// The user starts this explicitly after confirming an awake HDMI source
    /// and a second usable screen/JOG recovery path. It returns to DP once,
    /// never replays a source request later after an offline failure.
    func test(_ port: MonitorPort, sourceConnected: Bool, recoveryReady: Bool) {
        guard !busy, port != .displayPort, sourceConnected, recoveryReady,
              coordinator.connectedDisplayCount > 1, let target,
              profile.canActivate(.displayPort, location: target.ioLocation), !fixture else {
            notice = "Read DisplayPort first, connect an awake HDMI device, and keep another Mac screen available."
            return
        }
        busy = true; pending = nil
        let token = UUID(); operation = token
        let code = route(port).code, back = route(.displayPort).code
        profile.revoke(port); save()
        work = Task { [weak self] in
            guard let self else { return }
            defer { if operation == token { self.busy = false; self.work = nil } }
            var attemptedAway = false
            do {
                let before = try await coordinator.readMonitorInput(target)
                guard current(token, target) else { return }
                guard before == back else { throw TVError("Start the test with the Samsung showing DisplayPort.") }
                notice = "Testing \(port.title) · returning to DisplayPort in 3 seconds…"
                attemptedAway = true
                try await coordinator.writeMonitorInput(code, on: target)
                guard current(token, target) else { return }
                inputValue = nil; inputReadAt = nil
                try await delay(800_000_000)
                guard current(token, target) else { return }
                let seen = try? await coordinator.readMonitorInput(target)
                try await delay(2_200_000_000)
                guard current(token, target) else { return }
                try await coordinator.writeMonitorInput(back, on: target)
                try await delay(500_000_000)
                let returned = try await coordinator.readMonitorInput(target)
                guard current(token, target),
                      returned == back else { throw TVError("Return to DisplayPort was not verified. Use the monitor's JOG control.") }
                inputValue = returned; inputReadAt = Date()
                if let seen, seen != code {
                    notice = "HDMI command was not confirmed; the monitor reported \(label(for: seen)). Source stays disabled. Check the mapping before retrying."
                    return
                }
                pending = PendingProof(token: token, port: port, code: code, returnCode: returned,
                    location: target.ioLocation, finishedAt: Date(), targetReadback: seen)
                notice = "DisplayPort readback confirmed. Check both physical pictures before enabling this source."
            } catch {
                guard operation == token else { return }
                inputValue = nil; inputReadAt = nil; pending = nil
                notice = (attemptedAway
                    ? "Test failed after an input write was attempted; the current picture is unknown. Restore DisplayPort with the Samsung's JOG control. Nothing will be replayed. "
                    : "Test stopped before any source write. ") + String(describing: error)
            }
        }
    }
    func confirm(_ token: UUID, sawBothPictures: Bool) {
        guard !busy, let p = pending, p.token == token else { return }
        defer { pending = nil }
        guard sawBothPictures, Date().timeIntervalSince(p.finishedAt) < 300,
              target?.ioLocation == p.location, (p.targetReadback == nil || p.targetReadback == p.code),
              profile.qualify(p.port, proof: .init(targetCode: p.code, returnCode: p.returnCode, ioLocation: p.location)) else {
            notice = "Source remains unverified. Check the cable and mapping before testing again."; return
        }
        save(); notice = "\(p.port.title) round trip physically confirmed. Source control enabled."
    }
    var diagnostics: [String: Any] {
        ["display": target?.id as Any? ?? NSNull(), "busy": busy, "notice": notice,
         "input": inputValue.map { Int($0) } as Any? ?? NSNull(),
         "readingAgeSeconds": inputReadAt.map { max(0, Date().timeIntervalSince($0)) } as Any? ?? NSNull(),
         "ports": Dictionary(uniqueKeysWithValues: MonitorPort.allCases.map { p in
             (p.rawValue, ["name": route(p).name, "code": Int(route(p).code),
                           "qualified": target.map { profile.canActivate(p, location: $0.ioLocation) } ?? false] as [String: Any])
         })]
    }
}
