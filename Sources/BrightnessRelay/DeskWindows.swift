import AppKit
import ApplicationServices
import BrightnessCore
import Carbon

private func axValue(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element,key as CFString,&value) == .success ? value : nil
}

struct DeskWindow: Identifiable {
    let id = UUID()
    let app: String, title: String, owner: pid_t, element: AXUIElement, original: CGDirectDisplayID
}

@MainActor final class DeskWindows: ObservableObject {
    @Published var focus: DeskWindow?
    @Published var choices = [DeskWindow]()
    @Published var notice = ""
    @Published var showing = false
    @Published var trusted = false
    @Published var shortcutLabel = "Not assigned"
    @Published var recording = false
    private var destination: CGDirectDisplayID?
    private var lastExternal: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var hotkey: EventHotKeyRef?, eventHandler: EventHandlerRef?, monitor: Any?
    private let pref = "Brightmess.WindowShortcut.v1"
    private let defaults: UserDefaults
    private let reserve: (UInt32,UInt32) -> EventHotKeyRef?
    private let release: (EventHotKeyRef) -> Void
    init(defaults: UserDefaults = .standard, reserve: @escaping (UInt32,UInt32) -> EventHotKeyRef? = { code,mods in
        var key: EventHotKeyRef?
        // A shared Carbon registration silently succeeds even if another process owns the chord.
        let result = RegisterEventHotKey(code,mods,EventHotKeyID(signature:0x42524d57,id:1),
            GetApplicationEventTarget(),OptionBits(kEventHotKeyExclusive),&key)
        return result == noErr ? key : nil
    }, release: @escaping (EventHotKeyRef) -> Void = { UnregisterEventHotKey($0) }) {
        self.defaults = defaults; self.reserve = reserve; self.release = release
    }
    var fixture = false
    var destinationName: String { screens.first { $0.id == destination }?.name ?? "this screen" }
    private struct Screen {
        let id: CGDirectDisplayID, name: String, frame: CGRect, usable: CGRect
    }
    private var screens: [Screen] {
        let top = CGDisplayBounds(CGMainDisplayID()).height
        func flip(_ r: NSRect) -> CGRect { CGRect(x:r.minX,y:top-r.maxY,width:r.width,height:r.height) }
        return NSScreen.screens.compactMap {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return Screen(id:number.uint32Value,name:$0.localizedName,frame:flip($0.frame),usable:flip($0.visibleFrame))
        }
    }
    private func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = axValue(el,kAXPositionAttribute), let s = axValue(el,kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue,.cgPoint,&pos), AXValueGetValue(s as! AXValue,.cgSize,&size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin:pos,size:size)
    }
    private func screen(_ rect: CGRect) -> Screen? {
        screens.compactMap { s -> (Screen,CGFloat)? in
            let i = s.frame.intersection(rect)
            return i.isNull || i.isEmpty ? nil : (s,i.width*i.height)
        }.max { $0.1 < $1.1 }?.0
    }
    private func entry(_ el: AXUIElement, _ app: NSRunningApplication) -> DeskWindow? {
        guard axValue(el,kAXRoleAttribute) as? String == kAXWindowRole,
              axValue(el,kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              (axValue(el,kAXMinimizedAttribute) as? Bool) != true,
              let r = frame(el), let screen = screen(r) else { return nil }
        return DeskWindow(app:app.localizedName ?? "Application",title:axValue(el,kAXTitleAttribute) as? String ?? "",
                          owner:app.processIdentifier,element:el,original:screen.id)
    }
    private func current(allowPrevious: Bool = false) -> DeskWindow? {
        let front = NSWorkspace.shared.frontmostApplication
        let app = front?.processIdentifier == getpid() && allowPrevious ? lastExternal : front
        guard let app, !app.isTerminated, app.processIdentifier != getpid() else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax,0.35)
        guard let el = axValue(ax,kAXFocusedWindowAttribute), CFGetTypeID(el) == AXUIElementGetTypeID() else { return nil }
        return entry(el as! AXUIElement,app)
    }
    func capture(screen: NSScreen?) {
        trusted = AXIsProcessTrusted()
        destination = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        focus = trusted ? current(allowPrevious:true) : nil; choices = []; showing = false
    }
    var canBring: Bool { focus != nil && focus?.original != destination }
    func list() {
        guard !fixture else { return }
        trusted = AXIsProcessTrusted()
        guard trusted else { notice = "Enable Accessibility to list windows."; return }
        if showing { showing = false; choices = []; return }
        showing = true
        choices = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isHidden
        }.flatMap { app in
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax,0.25)
            return (axValue(ax,kAXWindowsAttribute) as? [AXUIElement] ?? []).compactMap { entry($0,app) }
        }.filter { $0.original != destination }.sorted { ($0.app,$0.title) < ($1.app,$1.title) }
    }
    func label(_ window: DeskWindow) -> String {
        "\(window.app) · \(window.title.isEmpty ? "Untitled" : window.title) · \(screens.first { $0.id == window.original }?.name ?? "Unavailable")"
    }
    private func settable(_ el: AXUIElement, _ attr: String) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(el,attr as CFString,&result) == .success && result.boolValue
    }
    func bring(_ w: DeskWindow) { if !fixture { move(w,to:destination) } }
    private func move(_ w: DeskWindow,to id: CGDirectDisplayID?) {
        trusted = AXIsProcessTrusted()
        do {
            try WindowPlacement.move(original:w.original,destination:id,trusted:trusted,usable:{ id in
                self.screens.first { $0.id == id }?.usable
            },read:{
                var pid: pid_t = 0
                guard AXUIElementGetPid(w.element,&pid) == .success, pid == w.owner,
                      let rect = self.frame(w.element), let s = self.screen(rect),
                      axValue(w.element,kAXMinimizedAttribute) as? Bool != true else { return nil }
                return .init(screen:s.id,rect:rect,usable:s.usable,fullScreen:axValue(w.element,"AXFullScreen") as? Bool == true,
                             movable:self.settable(w.element,kAXPositionAttribute))
            },write:{ target in
                var origin = target.origin, size = target.size
                let resize = self.settable(w.element,kAXSizeAttribute) && self.frame(w.element)?.size != size
                func resizeIfNeeded() {
                    if resize, let v = AXValueCreate(.cgSize,&size) { _ = AXUIElementSetAttributeValue(w.element,kAXSizeAttribute as CFString,v) }
                }
                resizeIfNeeded()
                guard let pos = AXValueCreate(.cgPoint,&origin),
                      AXUIElementSetAttributeValue(w.element,kAXPositionAttribute as CFString,pos) == .success else { return false }
                resizeIfNeeded(); return true
            })
        } catch { notice = error.localizedDescription; return }
        guard let to = screens.first(where:{ $0.id == id }) else { notice = "Destination disconnected."; return }
        notice = "Moved \(w.app) to \(to.name)."; focus = nil; showing = false; choices = []
        NSRunningApplication(processIdentifier:w.owner)?.activate(options: [])
        AXUIElementPerformAction(w.element,kAXRaiseAction as CFString)
    }
    func shortcut() {
        guard AXIsProcessTrusted() else { notice = "Window shortcut needs Accessibility."; NSSound.beep(); return }
        let all = screens
        guard all.count == 2, let w = current(), let other = all.first(where:{ $0.id != w.original }) else { NSSound.beep(); return }
        move(w,to:other.id)
    }
    func installShortcut() {
        lastExternal = NSWorkspace.shared.frontmostApplication
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular, app.processIdentifier != getpid() else { return }
            MainActor.assumeIsolated { self?.lastExternal = app }
        }
        var event = EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _,e,ctx in
            guard let e, let ctx else { return OSStatus(eventNotHandledErr) }
            var hot = EventHotKeyID()
            guard GetEventParameter(e,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,
                                    MemoryLayout<EventHotKeyID>.size,nil,&hot) == noErr, hot.signature == 0x42524d57, hot.id == 1 else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<DeskWindows>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in owner.shortcut() }; return noErr
        },1,&event,Unmanaged.passUnretained(self).toOpaque(),&eventHandler)
        if let d = defaults.dictionary(forKey:pref), let code = d["code"] as? UInt32,
           let mods = d["mods"] as? UInt32, let label = d["label"] as? String { bind(code,mods,label) }
    }
    private func bind(_ code: UInt32,_ mods: UInt32,_ label: String) {
        guard let next = reserve(code,mods) else {
            notice = "Shortcut unavailable. Choose a different combination."; return
        }
        if let hotkey { release(hotkey) }
        hotkey = next; shortcutLabel = label
        defaults.set(["code":code,"mods":mods,"label":label],forKey:pref)
    }
    func record() {
        stopRecording(); recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] e in
            guard let self else { return e }
            self.stopRecording()
            if e.keyCode == 53 { return nil }
            let f = e.modifierFlags
            guard f.contains(.option) || f.contains(.control) || f.contains(.command) else { self.notice = "Include Control, Option or Command."; return nil }
            let modifiers: [(NSEvent.ModifierFlags,Int,String)] = [(.control,controlKey,"⌃"),(.option,optionKey,"⌥"),(.shift,shiftKey,"⇧"),(.command,cmdKey,"⌘")]
            let used = modifiers.filter { f.contains($0.0) }
            self.bind(UInt32(e.keyCode),used.reduce(0) { $0 | UInt32($1.1) },used.map(\.2).joined()+(e.charactersIgnoringModifiers?.uppercased() ?? "Key"))
            return nil
        }
    }
    func stopRecording() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = false }
    func clearShortcut() {
        stopRecording(); if let hotkey { release(hotkey) }; hotkey = nil
        defaults.removeObject(forKey:pref); shortcutLabel = "Not assigned"
    }
    func close() { stopRecording(); choices = []; focus = nil; showing = false }
    #if DEBUG
    static func checkShortcutConflict(_ defaults: UserDefaults) throws {
        var released = 0
        let fake = DeskWindows(defaults:defaults,reserve:{ code,_ in code == 10 ? OpaquePointer(bitPattern:1) : nil },
                               release:{ _ in released += 1 })
        guard fake.shortcutLabel == "Not assigned" else { throw TVError("Shortcut was enabled by default.") }
        fake.bind(10,1,"Fixture A"); fake.bind(11,1,"Taken")
        guard fake.shortcutLabel == "Fixture A", released == 0, fake.notice.contains("unavailable"),
              defaults.dictionary(forKey:fake.pref)?["label"] as? String == "Fixture A" else { throw TVError("Shortcut collision replaced a binding.") }
        fake.clearShortcut()
        guard released == 1, defaults.object(forKey:fake.pref) == nil else { throw TVError("Shortcut did not clear.") }
    }
    func loadFixture() {
        fixture = true; trusted = true; destination = 51000
        focus = DeskWindow(app:"Safari",title:"Fixture browser",owner:0,element:AXUIElementCreateSystemWide(),original:51001)
    }
    #endif
}
