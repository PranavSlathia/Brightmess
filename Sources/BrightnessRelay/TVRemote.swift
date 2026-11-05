import AppKit
import BrightnessCore
import Network
import Security

struct PairedTV: Codable {
    let service: String, display: String, pin: Data
    var ps5 = "", mini = ""
    var ps5Picker = false, miniPicker = false
    // Nil migrates the original 0.9–0.11 assignments without altering pairing.
    var ps5HDMI: Int?, miniHDMI: Int?
    var hdmiInputs: [String: String]?
    var lastHost: String?
    func hdmi(_ a: DeskAction) -> Int { a == .ps5 ? (ps5HDMI ?? 1) : (miniHDMI ?? 3) }
    var availableHDMIPorts: [Int] {
        let reported = hdmiInputs?.keys.compactMap(Int.init).filter { (1...4).contains($0) } ?? []
        return Array(Set((reported.isEmpty ? [1,2,3,4] : reported) + [hdmi(.ps5),hdmi(.mac)])).sorted()
    }
    func routeLabel(_ a: DeskAction) -> String {
        guard a == .ps5 || a == .mac else { return "Home" }
        if (a == .ps5 ? ps5Picker : miniPicker) { return "Input chooser" }
        return "HDMI \(hdmi(a))"
    }
    func settingInputs(ps5: String, mini: String, ps5HDMI: Int, miniHDMI: Int,
                       ps5Picker: Bool, miniPicker: Bool) throws -> PairedTV {
        guard (1...4).contains(ps5HDMI), (1...4).contains(miniHDMI), ps5HDMI != miniHDMI else {
            throw TVError("Choose a different HDMI port for PS5 and Mac mini.")
        }
        let ps5 = ps5.trimmingCharacters(in: .whitespacesAndNewlines)
        let mini = mini.trimmingCharacters(in: .whitespacesAndNewlines)
        for id in [ps5,mini] where !id.isEmpty { _ = try TVWire.link(id) }
        guard ps5.isEmpty || mini.isEmpty || ps5 != mini else { throw TVError("PS5 and Mac mini cannot use the same input ID.") }
        for (port,id) in [(ps5HDMI,ps5),(miniHDMI,mini)] {
            if !id.isEmpty, let known = hdmiInputs?[String(port)], id != known {
                throw TVError("The input ID does not match this TV's saved HDMI \(port) ID. Select the port again.")
            }
        }
        var next = self
        next.ps5 = ps5; next.mini = mini; next.ps5HDMI = ps5HDMI; next.miniHDMI = miniHDMI
        next.ps5Picker = ps5Picker; next.miniPicker = miniPicker
        return next
    }
    func route(_ a: DeskAction) -> (code: Int, link: String?, label: String)? {
        if a == .ps5 || a == .mac { guard (1...4).contains(hdmi(a)) else { return nil } }
        switch a {
        case .bringHere, .move, .samsungDP, .samsungHDMI1, .samsungHDMI2: return nil
        case .home: return (3,nil,"Smart TV")
        case .ps5 where ps5Picker, .mac where miniPicker: return (178,nil,"Open TV inputs")
        case .ps5: return (242 + hdmi(a),ps5.isEmpty ? nil : ps5,"PS5")
        case .mac: return (242 + hdmi(a),mini.isEmpty ? nil : mini,"Mac mini")
        }
    }
}

@MainActor final class TVRemote: NSObject, ObservableObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    @Published private(set) var names = [String]()
    @Published private(set) var paired: PairedTV?
    @Published private(set) var ready = false
    @Published private(set) var wantsCode = false
    @Published private(set) var busy = false
    @Published var notice = "Pair your TCL to switch inputs."
    private let pref = "Brightmess.TV.v1"
    private let defaults: UserDefaults
    private let browseBonjour: Bool
    private let searchLAN: (String, @escaping ([String]) -> Void) -> any TVDiscoveryCancellation
    private let connectionOverride: ((String, Bool) -> Void)?
    private let identityLoader: (Bool) throws -> any TVClientIdentity
    private let injectedIdentityLoader: Bool
    private let identityTimeout:TimeInterval
    private var cachedIdentity: (any TVClientIdentity)?
    private var identityLoad: Task<any TVClientIdentity, Error>?
    private var identityAttempt: Task<Void,Never>?
    private var lanProbe: (any TVDiscoveryCancellation)?
    private var attemptedHosts = Set<String>(), candidateHosts = [String]()
    private var currentHost: String?
    private(set) var lastConnectionError: String?
    private var browser: NetServiceBrowser?
    private var services = [String:NetService](), hosts = [String:String]()
    private var selected = "", display = "", isPairing = false
    private var panelOpen = false, backgroundKeys = false, asleep = false
    static func needsSession(panel: Bool, keys: Bool, paired: Bool, asleep: Bool) -> Bool {
        !asleep && (panel || (keys && paired))
    }
    private var wanted: Bool { Self.needsSession(panel:panelOpen,keys:backgroundKeys,paired:paired != nil,asleep:asleep) }
    private(set) var lastSent: String?
    private var socket: NWConnection?, identity: (any TVClientIdentity)?, peerKey: Data?
    private var generation = UUID()
    private var conversation = TVHandshake(pairing:false), frames = TVFrames()
    private var deadline: DispatchWorkItem?
    private var retry: DispatchWorkItem?, retryDelay = 2.0
    let fixture: Bool
    init(fixture: Bool = false, defaults: UserDefaults = .standard, browseBonjour: Bool = true,
         searchLAN: @escaping (String, @escaping ([String]) -> Void) -> any TVDiscoveryCancellation = TVLANDiscovery.search,
         connectionOverride: ((String, Bool) -> Void)? = nil, identityLoader: (() throws -> any TVClientIdentity)? = nil,
         identityTimeout:TimeInterval = 30) {
        self.fixture = fixture
        self.defaults = defaults; self.browseBonjour = browseBonjour
        self.searchLAN = searchLAN; self.connectionOverride = connectionOverride
        if let identityLoader {self.identityLoader={_ in try identityLoader()}}
        else {self.identityLoader={allowCreation in try TVIdentity.load(allowCreation:allowCreation)}}
        injectedIdentityLoader = identityLoader != nil
        self.identityTimeout=identityTimeout
        if !fixture, let d = defaults.data(forKey:pref) { paired = try? JSONDecoder().decode(PairedTV.self,from:d) }
        super.init()
        if fixture { ready = true; notice = "Fixture TCL · Remote ready" }
        else if paired != nil { notice = "Looking for paired TV…" }
    }
    func open() { panelOpen = true; reconcile() }
    func close() {
        panelOpen = false
        if isPairing && busy { stop(); isPairing = false }
        reconcile()
    }
    func keepForShortcuts(_ enabled: Bool) { backgroundKeys = enabled; reconcile() }
    func sleeping(_ value: Bool) { asleep = value; reconcile() }
    private func reconcile() {
        guard !fixture else { return }
        guard wanted else { shutdown(); return }
        if browser == nil && browseBonjour {
            let b = NetServiceBrowser(); browser = b; b.delegate = self
            b.searchForServices(ofType:"_androidtvremote2._tcp.",inDomain:"local.")
        }
        if !ready && !busy && socket == nil && retry == nil && paired != nil { reconnect() }
    }
    func shutdown() {
        browser?.delegate = nil; browser?.stop(); browser = nil
        for s in services.values { s.delegate = nil; s.stop() }; services = [:]; hosts = [:]; names = []
        stop(); attemptedHosts = []; candidateHosts = []
        notice = paired == nil ? "Pair your TCL to switch inputs." : "Looking for paired TV…"
    }
    func netServiceBrowser(_ browser: NetServiceBrowser,didFind service: NetService,moreComing: Bool) {
        guard browser === self.browser else { return }
        services[service.name] = service; service.delegate = self; service.resolve(withTimeout:4)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser,didRemove service: NetService,moreComing: Bool) {
        guard browser === self.browser else { return }
        hosts.removeValue(forKey:service.name); services.removeValue(forKey:service.name); names = hosts.keys.sorted()
        // Losing an advertisement is not proof that a healthy TLS session died.
        if selected == service.name && !ready && socket == nil && !busy { reconnect() }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser,didNotSearch errorDict: [String:NSNumber]) {
        guard browser === self.browser else { return }
        if paired != nil { automaticReconnectAfterDiscovery() }
        else if !isPairing { notice = "Cannot discover TVs. Check Local Network access and Wi-Fi." }
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard wanted, sender === services[sender.name], let host = sender.hostName else { return }
        hosts[sender.name] = host; names = hosts.keys.sorted()
        if paired?.service == sender.name { automaticReconnectAfterDiscovery() }
    }
    private func automaticReconnectAfterDiscovery() {
        guard !isPairing, !busy, paired != nil, socket == nil, !ready else { return }
        reconnect()
    }
    func pair(_ name: String, display: String) { connect(name,display:display,pairing:true) }
    var pairingInProgress: Bool { isPairing && busy }
    func pairWithCode(display: String, address: String = "") {
        guard !fixture, panelOpen else { return }
        let address = address.trimmingCharacters(in:.whitespacesAndNewlines)
        guard address.isEmpty || TCLDiscovery.isLocalIPv4(address) else {
            notice = "Enter the TV's local IPv4 address, without a port or URL."; return
        }
        let name = paired?.service ?? "Android TV"
        if let host = address.isEmpty ? (hosts[name] ?? paired?.lastHost ?? currentHost) : address {
            connect(name,display:display,pairing:true,host:host); return
        }
        stop(); isPairing = true; busy = true
        notice = "Finding your TV to show a pairing code…"
        let ticket = generation
        lanProbe = searchLAN(paired?.service ?? "") { [weak self] candidates in
            MainActor.assumeIsolated {
                guard let self, self.generation == ticket, self.panelOpen else { return }
                self.lanProbe = nil
                guard candidates.count == 1, let host = candidates.first else {
                    self.busy = false; self.isPairing = false
                    self.notice = candidates.isEmpty ? "TV not found. Enter its network address below to show a code." : "More than one TV found. Enter the intended TV's network address below."
                    return
                }
                self.connect(name,display:display,pairing:true,host:host)
            }
        }
    }
    func cancelPairing() { stop(); isPairing = false; reconcile() }
    func reconnect() {
        guard !fixture, wanted, let p = paired else { return }
        stop(); attemptedHosts = []; candidateHosts = []
        selected = p.service; display = p.display; isPairing = false
        if let host = hosts[p.service] ?? p.lastHost { connect(p.service,display:p.display,pairing:false,host:host) }
        else { recoverLAN() }
    }
    private func stop() {
        generation = UUID()
        retry?.cancel(); retry = nil
        lanProbe?.cancel(); lanProbe = nil
        deadline?.cancel(); deadline = nil
        let c = socket; socket = nil; c?.stateUpdateHandler = nil; c?.cancel()
        ready = false; busy = false; wantsCode = false; identity = nil; peerKey = nil
    }
    private func fail(_ message: String, retryConnection: Bool = true) {
        let mayRetry = retryConnection && !isPairing && wanted && paired?.service == selected
        stop(); notice = message
        lastConnectionError = message
        guard mayRetry else { return }
        if !candidateHosts.isEmpty, let p = paired {
            let host = candidateHosts.removeFirst()
            connect(p.service,display:p.display,pairing:false,host:host)
        } else { recoverLAN() }
    }
    private func recoverLAN() {
        guard wanted, !fixture, let p = paired else { return }
        if let cached = p.lastHost, !attemptedHosts.contains(cached) {
            connect(p.service,display:p.display,pairing:false,host:cached); return
        }
        lanProbe?.cancel(); busy = true
        notice = "Finding paired TV on your local network…"
        let ticket = generation
        lanProbe = searchLAN(p.service == "Android TV" ? "" : p.service) { [weak self] candidates in
            MainActor.assumeIsolated {
                guard let self, self.generation == ticket, self.wanted else { return }
                self.lanProbe = nil
                self.candidateHosts = Array(candidates.filter { !self.attemptedHosts.contains($0) }.prefix(8))
                if !self.candidateHosts.isEmpty {
                    let host = self.candidateHosts.removeFirst()
                    self.connect(p.service,display:p.display,pairing:false,host:host)
                } else {
                    self.busy = false
                    self.notice = "Paired TV not found. Check its network or try Reconnect. No commands queued."
                    self.scheduleRetry()
                }
            }
        }
    }
    private func scheduleRetry() {
        guard wanted, !isPairing, paired != nil else { return }
        // Only reconnect the paired session. An action is never replayed after reconnection.
        let ticket = generation
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.generation == ticket, self.wanted else { return }
            self.retry = nil; self.reconnect()
        }
        retry = task; DispatchQueue.main.asyncAfter(deadline:.now()+retryDelay,execute:task)
        retryDelay = min(60,retryDelay*2)
    }
    private func timeout(_ seconds: Double) {
        deadline?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fail("TV timed out. Reconnect to try again.") }
        deadline = work; DispatchQueue.main.asyncAfter(deadline:.now()+seconds,execute:work)
    }
    private func connect(_ name: String, display: String, pairing: Bool, host explicitHost: String? = nil) {
        guard !fixture else { return }
        stop()
        guard let host = explicitHost ?? hosts[name], wanted else { notice = "TV unavailable on this network."; return }
        selected = name; self.display = display; isPairing = pairing; currentHost = host
        attemptedHosts.insert(host); busy = true
        if let connectionOverride, !injectedIdentityLoader { connectionOverride(host,pairing); return }
        let ticket = generation
        notice = "Opening saved TV identity. Approve the macOS Keychain request if shown."
        let identityDeadline=DispatchWorkItem { [weak self] in
            guard let self,self.generation==ticket,self.socket==nil else{return}
            self.fail("Keychain did not finish opening the TV identity. Complete its macOS prompt, then choose Reconnect or Pair again. Saved pairing is unchanged.",retryConnection:false)
        }
        deadline=identityDeadline
        DispatchQueue.main.asyncAfter(deadline:.now()+identityTimeout,execute:identityDeadline)
        identityAttempt = Task { [weak self] in
            guard let self else { return }
            guard self.generation == ticket, self.wanted else { return }
            do {
                let client = try await self.clientIdentity(allowCreation:pairing)
                guard self.generation == ticket, self.wanted else { return }
                self.deadline?.cancel();self.deadline=nil
                if let override = self.connectionOverride { override(host,pairing); return }
                self.connectTLS(name,display:display,pairing:pairing,host:host,client:client)
            } catch {
                guard self.generation == ticket else { return }
                self.fail(error.localizedDescription,retryConnection:false)
            }
        }
    }
    private func clientIdentity(allowCreation:Bool) async throws -> any TVClientIdentity {
        if let cachedIdentity { return cachedIdentity }
        // Security may wait for user approval. Never block menu/receiver startup,
        // and share one load rather than opening duplicate Keychain dialogs.
        let loader = identityLoader
        let task = identityLoad ?? Task.detached(priority:.utility) { try loader(allowCreation) }
        identityLoad = task
        do {
            let client = try await task.value
            cachedIdentity = client; identityLoad = nil; return client
        } catch { identityLoad = nil; throw error }
    }
    private func connectTLS(_ name: String, display: String, pairing: Bool, host: String, client: any TVClientIdentity) {
        do {
            identity = client
            let tls = NWProtocolTLS.Options()
            guard let local = sec_identity_create(client.identity) else { throw TVError("Cannot use TV Keychain identity.") }
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions,local)
            let expected = pairing ? nil : paired?.pin
            guard pairing || expected != nil else { throw TVError("Pair the TV first.") }
            let ticket = generation
            // Only the explicit pairing socket admits an unknown peer. Its PIN proof
            // binds both RSA keys before we persist anything or send a TV action.
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions,{ [weak self] _,trust,complete in
                MainActor.assumeIsolated {
                guard let self, self.generation == ticket, let key = SecTrustCopyKey(sec_trust_copy_ref(trust).takeRetainedValue()),
                      let raw = SecKeyCopyExternalRepresentation(key,nil) as Data?,
                      (try? TVDER.rsaComponents(raw)) != nil else { complete(false); return }
                guard TVTrust.accepts(raw,pairing:pairing,pinned:expected) else {
                    complete(false); self.fail("Device identity did not match the paired TV. No commands sent."); return
                }
                self.peerKey = raw; complete(true)
                }
            },.main)
            let c = NWConnection(host:NWEndpoint.Host(host),port:pairing ? 6467 : 6466,
                                 using:NWParameters(tls:tls,tcp:NWProtocolTCP.Options()))
            selected = name; self.display = display; isPairing = pairing; busy = true
            conversation = TVHandshake(pairing:pairing); frames = TVFrames(); socket = c; timeout(8)
            notice = pairing ? "Contacting TV for a code…" : "Connecting to paired TV…"
            c.stateUpdateHandler = { [weak self,weak c] state in
                MainActor.assumeIsolated {
                guard let self, let c, self.socket === c else { return }
                switch state {
                case .ready:
                    if pairing { self.send(self.conversation.hello,on:c) }; self.read(c)
                case .failed,.waiting,.cancelled: self.fail("TV unavailable. Check Wi-Fi or pair again.")
                default: break
                }
                }
            }
            c.start(queue:.main)
        } catch { fail(error.localizedDescription,retryConnection:false) }
    }
    private func send(_ message: Data,on c: NWConnection, label: String? = nil) {
        c.send(content:TVWire.frame(message),completion:.contentProcessed { [weak self,weak c] err in
            MainActor.assumeIsolated {
            guard let self, let c, self.socket === c else { return }
            if err != nil { self.fail("Could not send to TV. Nothing will be retried.") }
            else if let label { self.lastSent = label; self.notice = "Command sent · "+label }
            }
        })
    }
    private func read(_ c: NWConnection) {
        c.receive(minimumIncompleteLength:1,maximumLength:16384) { [weak self,weak c] data,_,end,error in
            MainActor.assumeIsolated {
            guard let self, let c, self.socket === c else { return }
            do {
                for msg in try self.frames.push(data ?? Data()) {
                    if let reply = try self.conversation.receive(msg) { self.send(reply,on:c) }
                    switch self.conversation.step {
                    case .code where !self.wantsCode:
                        self.wantsCode = true; self.notice = "Enter the six-character code on your TV."; self.timeout(100)
                    case .verified:
                        guard let raw = self.peerKey else { throw TVError("Missing verified pairing key.") }
                        let pin = TVTrust.fingerprint(raw)
                        var p = self.paired?.pin == pin ? self.paired : nil
                        if p?.service != self.selected || p?.display != self.display { p = nil }
                        var verified = p ?? PairedTV(service:self.selected,display:self.display,pin:pin)
                        verified.lastHost = self.currentHost
                        self.persist(verified)
                        self.reconnect(); return
                    case .ready:
                        if !self.ready { self.sessionReady() }
                    default: break
                    }
                }
                if end || error != nil { throw TVError("TV disconnected. Nothing will be retried.") }
                self.read(c)
            } catch { self.fail(error.localizedDescription) }
            }
        }
    }
    private func sessionReady() {
        guard let raw = peerKey, let p = paired, TVTrust.accepts(raw,pairing:false,pinned:p.pin) else {
            fail("Device identity did not match the paired TV. No commands sent."); return
        }
        var saved = p; saved.lastHost = currentHost
        persist(saved)
        deadline?.cancel(); ready = true; busy = false; retryDelay = 2; lastConnectionError = nil
        notice = "TV remote ready"
    }
    func verify(_ code: String) {
        guard wantsCode, let c = socket, let key = peerKey, let identity else { return }
        do {
            let proof = try conversation.prove(identity.secret(code,server:key))
            wantsCode = false; timeout(8); notice = "Verifying TV code…"; send(proof,on:c)
        } catch { notice = error.localizedDescription }
    }
    private func persist(_ p: PairedTV) {
        guard let bytes = try? JSONEncoder().encode(p) else { return }
        if !fixture { defaults.set(bytes,forKey:pref) }
        paired = p
    }
    func map(ps5: String,mini: String,ps5Picker: Bool,miniPicker: Bool,ps5HDMI: Int,miniHDMI: Int) {
        guard let p = paired else { return }
        do {
            persist(try p.settingInputs(ps5:ps5,mini:mini,ps5HDMI:ps5HDMI,miniHDMI:miniHDMI,ps5Picker:ps5Picker,miniPicker:miniPicker))
            notice = "Saved · Mac mini HDMI \(miniHDMI), PS5 HDMI \(ps5HDMI). No input command sent."
        } catch { notice = error.localizedDescription }
    }
    private func action(_ code: Int, link: String?, label: String) {
        guard !fixture, ready, let c = socket, paired != nil else { notice = "TV not connected. No command sent."; return }
        do { send(try conversation.command(code:code,inputID:link),on:c,label:label) }
        catch { notice = error.localizedDescription }
    }
    func usesPicker(_ a: DeskAction) -> Bool {
        paired?.route(a)?.code == 178
    }
    func routeLabel(_ a: DeskAction) -> String {
        paired?.routeLabel(a) ?? (a == .ps5 ? "HDMI 1" : a == .mac ? "HDMI 3" : "Home")
    }
    func inputMenu() { action(178,link:nil,label:"Open TV inputs") }
    #if DEBUG
    func loadFixtureMapping(_ value: PairedTV) { guard fixture else { return }; paired = value }
    func connectionFailedForTest() { guard connectionOverride != nil else { return }; fail("Fixture connection failed") }
    func connectionReadyForTest(key: Data) { guard connectionOverride != nil else { return }; peerKey = key; sessionReady() }
    var endpointForTest: String? { currentHost }
    var retryDelayForTest: Double { retryDelay }
    func waitForIdentityAttemptForTest() async { await identityAttempt?.value }
    func discoveredHostForTest(_ host: String) { guard connectionOverride != nil, let p = paired else { return }; hosts[p.service] = host; automaticReconnectAfterDiscovery() }
    func discoveryFailedForTest() { guard connectionOverride != nil else { return }; automaticReconnectAfterDiscovery() }
    func pairingFixture() { guard fixture else { return }; ready = false; wantsCode = true; busy = true; isPairing = true; notice = "Enter the six-character code shown on your TV." }
    func recoveryFixture() { guard fixture else { return }; ready = false; wantsCode = false; busy = false; isPairing = false; notice = "Paired TV not found. Check its network or try Reconnect. No commands queued." }
    #endif
    /// All TV buttons and hotkeys use this same configured route.
    func activate(_ a: DeskAction) {
        guard paired != nil else { notice = "Pair your TV first. No command sent."; return }
        guard let route = paired?.route(a) else { return }
        action(route.code,link:route.link,label:route.label)
    }
}
