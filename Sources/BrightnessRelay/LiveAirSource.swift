import AppKit
import BrightnessCore
import BrightnessHardware

@MainActor protocol AirSensors {
    func observe(_ cb: @convention(c) () -> Void) -> Bool
    func stop()
    func ambient() -> AmbientSample
    func brightness() throws -> Double
}
@MainActor final class NativeAirSensors: AirSensors {
    private var reader = LiveAmbientReader()
    func observe(_ cb: @convention(c) () -> Void) -> Bool {
        reader = LiveAmbientReader()
        return BuiltInBrightnessEvents.start(cb)
    }
    func stop() { BuiltInBrightnessEvents.stop() }
    func ambient() -> AmbientSample { reader.read() }
    func brightness() throws -> Double { try BuiltInBrightnessSource().sample() }
}

/// Main-run-loop owned sensor/notification lifetime. Sampling, retry, heartbeat and
/// manual pull all feed a single latest-value mailbox, never independent send loops.
@MainActor
final class LiveAirSource {
    private struct Snapshot: Sendable {
        let brightness: Double?
        let ambient: AmbientSample
        let state: AirState
        let time: Double
        func differs(from old: Self) -> Bool {
            func bin(_ b: Double?) -> Int? { b.map { Int(($0 * 100).rounded()) } }
            if state != old.state || bin(brightness) != bin(old.brightness) { return true }
            func moved(_ a: Double?, _ b: Double?, _ tolerance: Double) -> Bool {
                guard let a, let b else { return (a == nil) != (b == nil) }
                return abs(a - b) >= tolerance
            }
            return moved(ambient.lux, old.ambient.lux, max(2, (old.ambient.lux ?? 0) * 0.1))
                || moved(ambient.kelvin, old.ambient.kelvin, 100)
                || (ambient.unavailableReason(now: time) == nil) != (old.ambient.unavailableReason(now: old.time) == nil)
        }
    }
    private static weak var current: LiveAirSource?
    private let client: RelayClient
    private let name: String
    private let session = UUID()
    private var sequence: UInt64 = 0
    private let sensors: any AirSensors
    private var ambient = AmbientSample(lux: nil, kelvin: nil)
    private var last: Snapshot?
    private var mailbox = LatestPublisher<Snapshot>()
    private var wakeup: DispatchWorkItem?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sleeping = false
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    init(client: RelayClient, name: String, sensors: (any AirSensors)? = nil) {
        self.client = client; self.name = name; self.sensors = sensors ?? NativeAirSensors()
    }

    func run() async {
        Self.current = self
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startObserving() }
        })
        startObserving()
        var retry: UInt64 = 1
        while !Task.isCancelled {
            do {
                if try await client.awaitPull(source: name) { sample(force: true, readAmbient: true) }
                retry = 1
            } catch {
                try? await Task.sleep(nanoseconds: retry * 1_000_000_000)
                retry = min(60, retry * 2)
            }
        }
        timer?.invalidate(); wakeup?.cancel(); sensors.stop()
        for o in observers { center.removeObserver(o) }
        Self.current = nil
    }

    func startObserving() {
        sleeping = false
        let hooked = sensors.observe {
            DispatchQueue.main.async { LiveAirSource.current?.sample(force: false, readAmbient: false) }
        }
        print("Live Air sync: \(hooked ? "brightness notifications + watchdog" : "two-second watchdog"); 60s heartbeat.")
        timer?.invalidate()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample(force: false, readAmbient: true) }
        }
        t.tolerance = 0.2; RunLoop.main.add(t, forMode: .common); timer = t
        sample(force: true, readAmbient: true)
    }

    func sleep() {
        sleeping = true; timer?.invalidate(); timer = nil; sensors.stop()
        sample(force: true, readAmbient: false)
    }

    private func sample(force: Bool, readAmbient: Bool) {
        let v = snapshot(readAmbient: readAmbient)
        if !force, let last, v.time - last.time < 60, !v.differs(from: last) { return }
        last = v; mailbox.offer(v); drain()
    }

    private func snapshot(readAmbient: Bool) -> Snapshot {
        if !sleeping && readAmbient { ambient = sensors.ambient() }
        let time = Date().timeIntervalSince1970
        let b = sleeping || ambient.lidClosed ? nil : try? sensors.brightness()
        let state: AirState = sleeping ? .asleep : ambient.lidClosed ? .lidClosed : b == nil ? .unavailable : .awake
        let colour = state == .awake ? ambient : AmbientSample(lux: nil, kelvin: nil, sampledAt: time, lidClosed: state == .lidClosed)
        return Snapshot(brightness: b, ambient: colour, state: state, time: time)
    }

    private func drain() {
        wakeup?.cancel(); wakeup = nil
        guard let delay = mailbox.delay(at: now) else { return }
        if delay > 0 {
            let task = DispatchWorkItem { [weak self] in self?.drain() }
            wakeup = task; DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task); return
        }
        guard var next = mailbox.take(at: now) else { return }
        if Date().timeIntervalSince1970 - next.time > 25 {
            next = snapshot(readAmbient: true); last = next
        }
        sequence += 1
        let meta = SourceMetadata(session: session, sequence: sequence, measuredAt: next.time, state: next.state)
        Task {
            do {
                if let b = next.brightness {
                    try await client.send(brightness: b, source: name, ambient: next.ambient, metadata: meta)
                } else {
                    try await client.sendAmbient(next.ambient, source: name, metadata: meta)
                }
                mailbox.finish(next, success: true, now: now)
                print("Live sample \(meta.sequence) accepted (\(next.state.rawValue)).")
            } catch {
                mailbox.finish(next, success: false, now: now)
                print("Live send deferred: \(error)")
            }
            drain()
        }
    }
}
