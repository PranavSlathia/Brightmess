import AppKit
import BrightnessCore
import Network
import Security

struct PairedTV: Codable {
    let service: String, display: String, pin: Data
    var ps5 = "", mini = ""
    var ps5Picker = false, miniPicker = false
    func route(_ a: DeskAction) -> (code: Int, link: String?, label: String)? {
        switch a {
        case .move: return nil
        case .home: return (3,nil,"Smart TV")
        case .ps5 where ps5Picker, .mac where miniPicker: return (178,nil,"Open TV inputs")
        case .ps5: return (243,ps5.isEmpty ? nil : ps5,"PS5")
        case .mac: return (245,mini.isEmpty ? nil : mini,"Mac mini")
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
    private var browser: NetServiceBrowser?
    private var services = [String:NetService](), hosts = [String:String]()
    private var selected = "", display = "", isPairing = false
    private var panelOpen = false, backgroundKeys = false, asleep = false
    static func needsSession(panel: Bool, keys: Bool, paired: Bool, asleep: Bool) -> Bool {
        !asleep && (panel || (keys && paired))
    }
    private var wanted: Bool { Self.needsSession(panel:panelOpen,keys:backgroundKeys,paired:paired != nil,asleep:asleep) }
    private(set) var lastSent: String?
    private var socket: NWConnection?, identity: TVIdentity?, peerKey: Data?
    private var generation = UUID()
    private var conversation = TVHandshake(pairing:false), frames = TVFrames()
    private var deadline: DispatchWorkItem?
    private var retry: DispatchWorkItem?, retryDelay = 2.0
    let fixture: Bool
    init(fixture: Bool = false) {
        self.fixture = fixture
        if !fixture, let d = UserDefaults.standard.data(forKey:pref) { paired = try? JSONDecoder().decode(PairedTV.self,from:d) }
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
        guard browser == nil else {
            if socket == nil && retry == nil, let p = paired, hosts[p.service] != nil { reconnect() }
            return
        }
        let b = NetServiceBrowser(); browser = b; b.delegate = self
        b.searchForServices(ofType:"_androidtvremote2._tcp.",inDomain:"local.")
    }
    func shutdown() {
        browser?.delegate = nil; browser?.stop(); browser = nil
        for s in services.values { s.delegate = nil; s.stop() }; services = [:]; hosts = [:]; names = []
        stop(); notice = paired == nil ? "Pair your TCL to switch inputs." : "Looking for paired TV…"
    }
    func netServiceBrowser(_ browser: NetServiceBrowser,didFind service: NetService,moreComing: Bool) {
        guard browser === self.browser else { return }
        services[service.name] = service; service.delegate = self; service.resolve(withTimeout:4)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser,didRemove service: NetService,moreComing: Bool) {
        guard browser === self.browser else { return }
        hosts.removeValue(forKey:service.name); services.removeValue(forKey:service.name); names = hosts.keys.sorted()
        if selected == service.name { fail("TV offline. No commands will be queued.") }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser,didNotSearch errorDict: [String:NSNumber]) {
        guard browser === self.browser else { return }; notice = "Cannot discover TVs. Check Local Network access and Wi-Fi."
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard wanted, sender === services[sender.name], let host = sender.hostName else { return }
        hosts[sender.name] = host; names = hosts.keys.sorted()
        if paired?.service == sender.name && socket == nil && !busy { reconnect() }
    }
    func pair(_ name: String, display: String) { connect(name,display:display,pairing:true) }
    func reconnect() { if let p = paired { connect(p.service,display:p.display,pairing:false) } }
    private func stop() {
        generation = UUID()
        retry?.cancel(); retry = nil
        deadline?.cancel(); deadline = nil
        let c = socket; socket = nil; c?.stateUpdateHandler = nil; c?.cancel()
        ready = false; busy = false; wantsCode = false; identity = nil; peerKey = nil
    }
    private func fail(_ message: String, retryConnection: Bool = true) {
        let mayRetry = retryConnection && !isPairing && wanted && paired?.service == selected && hosts[selected] != nil
        stop(); notice = message
        guard mayRetry else { return }
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
    private func connect(_ name: String, display: String, pairing: Bool) {
        guard !fixture else { return }
        stop()
        guard let host = hosts[name], wanted else { notice = "TV unavailable on this network."; return }
        do {
            let client = try TVIdentity.load(); identity = client
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
                    complete(false); self.fail("TV identity changed. Confirm the device and pair again.",retryConnection:false); return
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
                        self.persist(p ?? PairedTV(service:self.selected,display:self.display,pin:pin))
                        self.reconnect(); return
                    case .ready:
                        if !self.ready { self.notice = "TV remote ready" }
                        self.deadline?.cancel(); self.ready = true; self.busy = false; self.retryDelay = 2
                    default: break
                    }
                }
                if end || error != nil { throw TVError("TV disconnected. Nothing will be retried.") }
                self.read(c)
            } catch { self.fail(error.localizedDescription) }
            }
        }
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
        UserDefaults.standard.set(bytes,forKey:pref); paired = p
    }
    func map(ps5: String,mini: String,ps5Picker: Bool,miniPicker: Bool) {
        guard var p = paired else { return }
        do {
            for id in [ps5,mini] where !id.isEmpty { _ = try TVWire.link(id) }
            p.ps5 = ps5; p.mini = mini; p.ps5Picker = ps5Picker; p.miniPicker = miniPicker
            persist(p); notice = "Input mapping saved."
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
    func inputMenu() { action(178,link:nil,label:"Open TV inputs") }
    /// All TV buttons and hotkeys use this same configured route.
    func activate(_ a: DeskAction) {
        guard paired != nil else { notice = "Pair your TV first. No command sent."; return }
        guard let route = paired?.route(a) else { return }
        action(route.code,link:route.link,label:route.label)
    }
}
