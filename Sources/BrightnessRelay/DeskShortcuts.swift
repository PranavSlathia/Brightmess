import AppKit
import Carbon
import BrightnessCore

/// Stable preference keys, independent of device order and keyboard layout.
enum DeskAction: String, CaseIterable, Identifiable {
    case move, ps5, mac, home
    var id: Self { self }
    var name: String {
        switch self { case .move: return "Move window"; case .ps5: return "PS5"
        case .mac: return "Mac mini"; case .home: return "Smart TV" }
    }
    var symbol: String {
        switch self { case .move: return "rectangle.2.swap"; case .ps5: return "gamecontroller"
        case .mac: return "desktopcomputer"; case .home: return "house" }
    }
    var suggested: DeskChord? {
        let key: (Int,String)
        switch self { case .move: key = (kVK_ANSI_M,"M"); case .ps5: key = (kVK_ANSI_1,"1")
        case .mac: key = (kVK_ANSI_2,"2"); case .home: return nil }
        return DeskChord(code:UInt32(key.0),mods:UInt32(controlKey|optionKey|cmdKey),label:"⌃⌥⌘"+key.1)
    }
    static let symbols = [
        ("rectangle.2.swap","Swap windows"),("macwindow","Window"),("arrow.left.arrow.right","Arrows"),
        ("display","Monitor"),("gamecontroller","Controller"),("gamecontroller.fill","Solid controller"),
        ("play.circle","Play"),("desktopcomputer","Desktop"),("macmini","Mac mini"),("laptopcomputer","Laptop"),
        ("tv","Television"),("tv.fill","Solid television"),("house","Home"),("house.fill","Solid home"),
        ("star","Star"),("bolt","Bolt")
    ]
}

struct DeskChord: Codable, Equatable {
    let code: UInt32, mods: UInt32, label: String
    func sameKeys(as other: Self) -> Bool { code == other.code && mods == other.mods }
    var isValid: Bool {
        let supported = UInt32(controlKey|optionKey|cmdKey|shiftKey)
        return code < 128 && !label.isEmpty && mods & UInt32(controlKey|optionKey|cmdKey) != 0 && mods & ~supported == 0
    }
}

@MainActor final class DeskShortcuts: ObservableObject {
    struct Settings: Codable {
        var bindings: [String:DeskChord] = [:]
        var icons: [String:String] = [:]
    }
    private struct Registration { let id: UInt32, ref: EventHotKeyRef }
    private let pref = "Brightmess.DeskActions.v2"
    private let defaults: UserDefaults
    private let reserve: (DeskChord,UInt32) -> EventHotKeyRef?
    private let release: (EventHotKeyRef) -> Void
    private var registrations: [DeskAction:Registration] = [:]
    private var held = Set<UInt32>(), nextID: UInt32 = 1
    private var presses: [DeskAction:Int] = [:]
    private var handler: EventHandlerRef?, monitor: Any?
    @Published private(set) var settings: Settings
    @Published private(set) var unavailable = Set<DeskAction>()
    @Published private(set) var recording: DeskAction?
    @Published var notice = ""
    var perform: ((DeskAction) -> Void)?
    var tvNeeded: ((Bool) -> Void)?

    init(defaults: UserDefaults = .standard,
         reserve: @escaping (DeskChord,UInt32) -> EventHotKeyRef? = DeskShortcuts.systemReserve,
         release: @escaping (EventHotKeyRef) -> Void = { UnregisterEventHotKey($0) }) {
        self.defaults = defaults; self.reserve = reserve; self.release = release
        if let bytes = defaults.data(forKey:pref), let saved = try? JSONDecoder().decode(Settings.self,from:bytes) {
            settings = saved
        } else {
            settings = Settings()
            if let old = defaults.dictionary(forKey:"Brightmess.WindowShortcut.v1"),
               let code = old["code"] as? UInt32, let mods = old["mods"] as? UInt32, let label = old["label"] as? String {
                let chord = DeskChord(code:code,mods:mods,label:label)
                if chord.isValid { settings.bindings[DeskAction.move.rawValue] = chord }
            }
        }
    }
    private nonisolated static func systemReserve(_ chord: DeskChord,_ id: UInt32) -> EventHotKeyRef? {
        var keys: Unmanaged<CFArray>?
        if CopySymbolicHotKeys(&keys) == noErr, let rows = keys?.takeRetainedValue() as? [[String:Any]],
           rows.contains(where:{ ($0["kHISymbolicHotKeyEnabled"] as? Bool) == true &&
               ($0["kHISymbolicHotKeyCode"] as? UInt32) == chord.code &&
               ($0["kHISymbolicHotKeyModifiers"] as? UInt32) == chord.mods }) { return nil }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(chord.code,chord.mods,EventHotKeyID(signature:0x42524d53,id:id),
                                         GetApplicationEventTarget(),OptionBits(kEventHotKeyExclusive),&ref)
        return status == noErr ? ref : nil
    }
    func start() {
        guard handler == nil else { return }
        var types = [EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyReleased))]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx in
            guard let event, let ctx else { return OSStatus(eventNotHandledErr) }
            var hot = EventHotKeyID()
            guard GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),
                  nil,MemoryLayout<EventHotKeyID>.size,nil,&hot) == noErr, hot.signature == 0x42524d53 else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<DeskShortcuts>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { owner.receive(hot.id,down:GetEventKind(event) == UInt32(kEventHotKeyPressed)) }
            return noErr
        },types.count,&types,Unmanaged.passUnretained(self).toOpaque(),&handler)
        guard status == noErr else { notice = "Could not start global shortcuts (\(status))."; return }
        restoreBindings()
    }
    private func restoreBindings() {
        for action in DeskAction.allCases {
            if let chord = binding(action), !bind(action,chord) { unavailable.insert(action) }
        }
        updateDemand()
    }
    private func updateDemand() { tvNeeded?(registrations[.ps5] != nil || registrations[.mac] != nil) }
    func binding(_ a: DeskAction) -> DeskChord? { settings.bindings[a.rawValue] }
    func symbol(_ a: DeskAction) -> String { settings.icons[a.rawValue] ?? a.symbol }
    func changeIcon(_ a: DeskAction,_ name: String) {
        guard DeskAction.symbols.contains(where:{$0.0 == name}) else { return }
        if name == a.symbol { settings.icons.removeValue(forKey:a.rawValue) } else { settings.icons[a.rawValue] = name }
        save()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data,forKey:pref) }
    }
    private func drop(_ action: DeskAction) {
        if let r = registrations.removeValue(forKey:action) { held.remove(r.id); release(r.ref) }
    }
    @discardableResult func bind(_ a: DeskAction,_ chord: DeskChord) -> Bool {
        guard a != .home, chord.isValid else { notice = "Include Control, Option or Command and a key."; return false }
        if let other = DeskAction.allCases.first(where:{ $0 != a && binding($0)?.sameKeys(as:chord) == true }) {
            notice = "Already used by \(other.name). Your previous shortcut was kept."; return false
        }
        if registrations[a] != nil && binding(a)?.sameKeys(as:chord) == true { return true }
        let id = nextID; nextID &+= 1
        guard let ref = reserve(chord,id) else { notice = "\(chord.label) is unavailable. Choose a different shortcut for \(a.name)."; return false }
        drop(a); registrations[a] = Registration(id:id,ref:ref); unavailable.remove(a)
        settings.bindings[a.rawValue] = chord; save(); updateDemand()
        notice = "\(a.name): \(chord.label)."; return true
    }
    func suggestions() {
        var failed: [String] = []
        for a in DeskAction.allCases where binding(a) == nil {
            if let chord = a.suggested, !bind(a,chord) { failed.append(a.name) }
        }
        notice = failed.isEmpty ? "Suggested keys applied to unassigned actions." : "Shortcut unavailable: "+failed.joined(separator:", ")+"."
    }
    func clear(_ a: DeskAction) {
        cancelRecording(); drop(a); settings.bindings.removeValue(forKey:a.rawValue); unavailable.remove(a)
        save(); updateDemand(); notice = "\(a.name) shortcut cleared."
    }
    private func receive(_ id: UInt32, down: Bool) {
        guard down else { held.remove(id); return }
        guard let a = registrations.first(where:{$0.value.id == id})?.key, held.insert(id).inserted else { return }
        if recording != nil { cancelRecording(); notice = "That shortcut is already assigned to \(a.name)."; return }
        presses[a, default:0] += 1
        perform?(a)
    }
    func record(_ action: DeskAction) {
        cancelRecording(); guard action != .home else { return }
        recording = action; notice = "Press the new shortcut for \(action.name), or Esc to cancel."
        monitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] e in
            guard let self else { return e }
            self.cancelRecording()
            if e.keyCode == UInt16(kVK_Escape) { self.notice = "Recording cancelled."; return nil }
            let modifiers: [(NSEvent.ModifierFlags,Int,String)] = [(.control,controlKey,"⌃"),(.option,optionKey,"⌥"),(.shift,shiftKey,"⇧"),(.command,cmdKey,"⌘")]
            let used = modifiers.filter { e.modifierFlags.contains($0.0) }
            let key = e.keyCode == UInt16(kVK_Space) ? "Space" : (e.charactersIgnoringModifiers?.uppercased() ?? "")
            guard !key.isEmpty else { self.notice = "Choose a visible letter, digit or key."; return nil }
            self.bind(action,DeskChord(code:UInt32(e.keyCode),mods:used.reduce(0){$0|UInt32($1.1)},label:used.map(\.2).joined()+key))
            return nil
        }
    }
    func cancelRecording() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = nil }
    func suspendInput() { held.removeAll(); cancelRecording() }
    func stop() {
        cancelRecording(); for a in DeskAction.allCases { drop(a) }; held.removeAll()
        if let handler { RemoveEventHandler(handler); self.handler = nil }; updateDemand()
    }
    var diagnostics: [String:Any] {
        Dictionary(uniqueKeysWithValues:DeskAction.allCases.map { a in
            (a.rawValue, ["shortcut":binding(a)?.label ?? "", "active":registrations[a] != nil,
                          "presses":presses[a] ?? 0, "icon":symbol(a)] as [String:Any])
        })
    }
    #if DEBUG
    static func fixture(defaults: UserDefaults) -> DeskShortcuts {
        DeskShortcuts(defaults:defaults,reserve:{ _,id in OpaquePointer(bitPattern:Int(id)) },release:{ _ in })
    }
    static func check(_ defaults: UserDefaults) throws {
        func require(_ b: Bool,_ msg: String) throws { if !b { throw TVError(msg) } }
        let legacy = DeskChord(code:12,mods:UInt32(cmdKey|optionKey),label:"⌥⌘Q")
        defaults.set(["code":legacy.code,"mods":legacy.mods,"label":legacy.label],forKey:"Brightmess.WindowShortcut.v1")
        var rejectedCode: UInt32?, released = 0, actions: [DeskAction] = [], wantsTV = false
        let fake = DeskShortcuts(defaults:defaults,reserve:{ chord,id in
            chord.code == rejectedCode ? nil : OpaquePointer(bitPattern:Int(id))
        },release:{ _ in released += 1 })
        fake.perform = { actions.append($0) }; fake.tvNeeded = { wantsTV = $0 }
        fake.restoreBindings(); fake.suggestions()
        try require(fake.binding(.move) == legacy && fake.binding(.home) == nil && wantsTV,"Legacy move binding, click-only Home, or background demand lost.")
        try require(fake.binding(.ps5) == DeskAction.ps5.suggested && fake.binding(.mac) == DeskAction.mac.suggested,"TV shortcut assignments incorrect.")
        let macID = fake.registrations[.mac]!.id
        fake.receive(macID,down:true); fake.receive(macID,down:true); fake.receive(macID,down:false); fake.receive(macID,down:true)
        try require(actions == [.mac,.mac],"A held key repeated a TV action.")
        try require(!fake.bind(.mac,legacy) && fake.registrations[.mac]?.id == macID,"An internal collision displaced a binding.")
        rejectedCode = 44
        try require(!fake.bind(.mac,.init(code:44,mods:UInt32(cmdKey),label:"⌘/")) && released == 0,"An OS collision displaced a binding.")
        fake.changeIcon(.mac,"star"); fake.changeIcon(.home,"tv.fill")
        let restored = fixture(defaults:defaults)
        try require(restored.symbol(.mac) == "star" && restored.symbol(.home) == "tv.fill" && restored.binding(.mac) == fake.binding(.mac),"Actions did not persist.")
        fake.clear(.ps5); try require(wantsTV,"Disabling one binding closed the other TV session.")
        fake.clear(.mac); try require(!wantsTV,"TV kept running after last TV shortcut was cleared.")
        fake.clear(.move); try require(fixture(defaults:defaults).binding(.move) == nil,"Cleared legacy shortcut reappeared.")
        fake.stop()
    }
    #endif
}
