#if DEBUG
import BrightnessCore
import Foundation
import Security

@MainActor enum TVReconnectChecks {
    private final class Search: TVDiscoveryCancellation {
        var cancelled = false
        func cancel() { cancelled = true }
    }
    private struct FakeIdentity: TVClientIdentity {
        var identity: SecIdentity { fatalError("Fake identity must never enter native TLS") }
        func secret(_ code: String, server: Data) throws -> Data { throw TVError("Fake identity") }
    }
    private final class IdentityGate: @unchecked Sendable {
        private let lock = NSLock(), release = DispatchSemaphore(value:0)
        private var active = false
        var started: Bool { lock.withLock { active } }
        func load() -> any TVClientIdentity {
            lock.withLock { active = true }
            _ = release.wait(timeout:.now()+2)
            return FakeIdentity()
        }
        func finish() { release.signal() }
    }
    static func run() async throws {
        func expect(_ b: @autoclosure () -> Bool, _ message: String) throws { if !b() { throw TVError(message) } }
        let suite = "dev.pranav.tv-reconnect-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let key = Data("fixture paired TV key".utf8)
        var paired = PairedTV(service:"Smart TV",display:"fixture-tv",pin:TVTrust.fingerprint(key),
            ps5:"fixture/.Input/HW2",mini:"fixture/.Input/HW1",ps5HDMI:2,miniHDMI:1)
        let pref = "Brightmess.TV.v1"
        defaults.set(try JSONEncoder().encode(paired),forKey:pref)
        var requests = [String](), attempts = [(String,Bool)]()
        var callbacks = [([String]) -> Void](), searches = [Search]()
        func remote() -> TVRemote {
            TVRemote(defaults:defaults,browseBonjour:false,searchLAN:{ name,complete in
                requests.append(name); callbacks.append(complete)
                let s = Search(); searches.append(s); return s
            },connectionOverride:{ host,pairing in attempts.append((host,pairing)) })
        }
        let r = remote(); r.keepForShortcuts(true)
        try expect(requests == ["Smart TV"] && r.busy && attempts.isEmpty,"Missing Bonjour did not start bounded LAN recovery")
        r.activate(.mac)
        callbacks.removeFirst()(["192.168.10.8"])
        try expect(attempts.last?.0 == "192.168.10.8" && attempts.last?.1 == false && !r.ready,"LAN candidate bypassed paired TLS path")
        r.connectionReadyForTest(key:Data("different TV".utf8))
        try expect(!r.ready && r.paired?.pin == paired.pin && r.paired?.lastHost == nil,"Wrong TV key replaced saved pairing")
        callbacks.removeFirst()(["192.168.10.8","192.168.10.9"])
        try expect(attempts.last?.0 == "192.168.10.9","Failed address was retried before another candidate")
        r.connectionReadyForTest(key:key)
        try expect(r.ready && r.paired?.lastHost == "192.168.10.9" && r.lastSent == nil && r.paired?.mini == paired.mini,
                   "Verified recovery lost settings or replayed an offline action")
        r.keepForShortcuts(false)

        paired.lastHost = "192.168.10.3"
        defaults.set(try JSONEncoder().encode(paired),forKey:pref)
        let changed = remote(); changed.keepForShortcuts(true)
        try expect(attempts.last?.0 == "192.168.10.3","Last verified host was ignored")
        changed.connectionFailedForTest(); callbacks.removeFirst()(["192.168.10.4"])
        changed.connectionReadyForTest(key:key)
        try expect(changed.ready && changed.paired?.lastHost == "192.168.10.4","Changed IP did not recover with the original pin")
        changed.open()
        changed.pairWithCode(display:"fixture-tv")
        try expect(attempts.last?.0 == "192.168.10.4" && attempts.last?.1 == true && changed.paired?.pin == paired.pin,
                   "Explicit code pairing was hidden or erased the old pairing prematurely")
        changed.cancelPairing(); changed.close(); changed.keepForShortcuts(false)

        let staleBonjour = remote()
        staleBonjour.discoveredHostForTest("192.168.10.99")
        staleBonjour.keepForShortcuts(true)
        let searchCount = requests.count
        try expect(attempts.last?.0 == "192.168.10.99","Stale Bonjour fixture did not reach real candidate selection")
        staleBonjour.connectionFailedForTest()
        try expect(attempts.last?.0 == "192.168.10.4" && requests.count == searchCount,
            "Stale Bonjour skipped the distinct cached authenticated address")
        staleBonjour.connectionReadyForTest(key:key); staleBonjour.keepForShortcuts(false)

        paired.lastHost = nil; defaults.set(try JSONEncoder().encode(paired),forKey:pref)
        callbacks.removeAll()
        let pairing = remote(); pairing.open()
        let oldDiscovery = callbacks.removeFirst()
        pairing.pairWithCode(display:"fixture-tv")
        let pairingToken = searches.last!, pairingCallback = callbacks.removeFirst()
        let calls = requests.count, oldAttempts = attempts.count
        oldDiscovery(["192.168.10.80"])
        pairing.discoveryFailedForTest(); pairing.discoveredHostForTest("192.168.10.81")
        try expect(pairing.pairingInProgress && !pairingToken.cancelled && requests.count == calls && attempts.count == oldAttempts,
            "Automatic discovery interrupted the explicit code-pairing search")
        pairingCallback(["192.168.10.82"])
        try expect(attempts.last?.0 == "192.168.10.82" && attempts.last?.1 == true && pairing.paired?.pin == paired.pin,
            "Code lookup did not retain pairing mode and the old saved identity")
        pairing.close()

        paired.lastHost = nil; defaults.set(try JSONEncoder().encode(paired),forKey:pref)
        callbacks.removeAll()
        let sleeping = remote(); sleeping.keepForShortcuts(true)
        let late = callbacks.removeFirst(), token = searches.last!
        let before = attempts.count
        sleeping.sleeping(true); late(["192.168.10.7"])
        try expect(token.cancelled && attempts.count == before && !sleeping.busy,"Sleep did not cancel discovery or reject a late callback")
        sleeping.sleeping(false)
        for _ in 0..<8 {
            callbacks.removeFirst()([])
            try expect(!sleeping.busy && sleeping.retryDelayForTest <= 60,"Empty discovery stayed busy or retry exceeded 60 seconds")
            sleeping.reconnect()
        }
        sleeping.keepForShortcuts(false)

        paired.lastHost = "192.168.10.5"; defaults.set(try JSONEncoder().encode(paired),forKey:pref)
        let gate = IdentityGate()
        var delayedAttempts = 0
        let waiting = TVRemote(defaults:defaults,browseBonjour:false,searchLAN:{ _,_ in Search() },
            connectionOverride:{ _,_ in delayedAttempts += 1 },identityLoader:{ gate.load() })
        let began = ContinuousClock.now
        waiting.keepForShortcuts(true)
        let deadline = ContinuousClock.now + .seconds(2)
        while !gate.started && ContinuousClock.now < deadline { await Task.yield() }
        try expect(gate.started && waiting.busy && delayedAttempts == 0 && ContinuousClock.now-began < .seconds(1),
            "Identity approval did not yield to the main actor")
        waiting.keepForShortcuts(false); gate.finish()
        await waiting.waitForIdentityAttemptForTest()
        try expect(delayedAttempts == 0 && !waiting.busy,"A late identity approval revived a cancelled connection")
        let instantGate = IdentityGate()
        let cancelled = TVRemote(defaults:defaults,browseBonjour:false,searchLAN:{ _,_ in Search() },
            connectionOverride:{ _,_ in delayedAttempts += 1 },identityLoader:{ instantGate.load() })
        cancelled.keepForShortcuts(true); cancelled.keepForShortcuts(false)
        await cancelled.waitForIdentityAttemptForTest()
        try expect(!instantGate.started && delayedAttempts == 0,
            "Cancelled-before-start connection still loaded Keychain identity")

        let timeoutGate=IdentityGate()
        defer {timeoutGate.finish()}
        let timed=TVRemote(defaults:defaults,browseBonjour:false,searchLAN:{_,_ in Search()},
            connectionOverride:{_,_ in delayedAttempts+=1},identityLoader:{timeoutGate.load()},identityTimeout:0.03)
        timed.keepForShortcuts(true)
        timed.discoveredHostForTest("192.168.10.6")
        try await Task.sleep(nanoseconds:100_000_000)
        try expect(!timed.busy && timed.lastConnectionError?.contains("Keychain") == true && timed.paired?.pin==paired.pin,
            "A pending identity kept reconnect/pairing busy forever instead of timing out safely")
        timeoutGate.finish();await timed.waitForIdentityAttemptForTest()
        try expect(delayedAttempts==0,"A timed-out identity silently resumed TLS")
        timed.reconnect();await timed.waitForIdentityAttemptForTest()
        try expect(delayedAttempts==1,"Manual reconnect could not use the completed cached identity")
        timed.keepForShortcuts(false)

        let message = Data("14:123:Smart TV:TV:3:Smart TV:capabilities\0".utf8)
        try expect(TCLDiscovery.candidate(message,expectedName:"Smart TV",host:"192.168.10.8") != nil &&
            TCLDiscovery.candidate(message,expectedName:"Other TV",host:"192.168.10.8") == nil &&
            TCLDiscovery.candidate(message,expectedName:"Smart TV",host:"8.8.8.8") == nil &&
            TCLDiscovery.candidate(Data("1:2:Smart TV:PHONE:3".utf8),expectedName:"Smart TV",host:"192.168.10.8") == nil,
            "Discovery admitted an unrelated name, public address or non-TV packet")
        print("TV reconnect checks passed: missing Bonjour, pinned-key refusal, changed IP, cached host, no replay, explicit code pairing, responsive identity wait, cancellation and bounded retries.")
    }
}
#endif
