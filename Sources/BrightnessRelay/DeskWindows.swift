import AppKit
import BrightnessCore

@MainActor final class DeskWindows: ObservableObject {
    @Published private(set) var focus:DeskWindow?
    @Published private(set) var choices=[DeskWindow]()
    @Published private(set) var notice=""
    @Published private(set) var showing=false
    @Published private(set) var trusted=false
    @Published private(set) var loading=false
    @Published private(set) var destinationName="this screen"
    @Published private(set) var sourceNames=""
    @Published private(set) var hint=""
    private(set) var successfulMoves=0
    private var port:any WindowDeskPort
    private var destination:UInt32?, ticket=UUID(), job:Task<Void,Never>?
    private var lastExternal:NSRunningApplication?, observer:NSObjectProtocol?
    private var iconCache=[String:NSImage]()
    init(port:(any WindowDeskPort)?=nil){self.port=port ?? MacWindowDesk()}

    func capture(screen:NSScreen?) {
        capture(destination:(screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value)
    }
    func capture(destination id:UInt32?) {
        close();destination=id;trusted=port.trusted
        // Capture the exact focused AX window before the popover activates.
        focus=trusted ? port.current(previous:lastExternal):nil
        refresh()
    }
    func topologyChanged(){if destination != nil { refresh() }}
    func refresh() {
        job?.cancel();ticket=UUID()
        let request=ticket,screens=port.screens
        trusted=port.trusted;choices=[];iconCache=[:];loading=false
        guard let dest=destination,let screen=screens.first(where:{$0.id==dest}) else{
            destinationName="unavailable display";sourceNames="";hint="Destination is no longer connected. Reopen on a connected screen.";return
        }
        destinationName=screen.name
        sourceNames=screens.filter{$0.id != dest}.map(\.name).joined(separator:", ")
        guard trusted else{hint="Enable Accessibility to list and move windows.";return}
        guard !sourceNames.isEmpty else{hint="No other Mac display is connected.";return}
        loading=true;hint="Finding windows…"
        let backend=port
        job=Task { [weak self] in
            let rows=await backend.inventory(excluding:dest,screens:screens)
            guard !Task.isCancelled,let self,self.ticket==request,self.destination==dest else{return}
            guard backend.trusted,backend.screens.contains(where:{$0.id==dest}) else{self.refresh();return}
            self.choices=rows.map { row in var w=row;w.shelfTicket=request;return w }
            self.loading=false;self.hint=rows.isEmpty ? "No movable windows on "+self.sourceNames+"." : ""
        }
    }
    func icon(for window:DeskWindow)->NSImage? {
        let key="\(window.owner)/\(window.app)"
        if let img=iconCache[key]{return img}
        let img=port.icon(for:window);iconCache[key]=img;return img
    }
    func label(_ window:DeskWindow)->String {
        "\(window.app) · \(window.displayTitle) · "+(port.screens.first{$0.id==window.original}?.name ?? "Unavailable")
    }
    func list(){ showing.toggle();if showing{refresh()} }
    func bring(_ w:DeskWindow) {
        guard let id=destination,w.shelfTicket==ticket,choices.contains(where:{$0.id==w.id && $0.original==w.original}) else{
            notice="That window list has changed. Choose it again.";return
        }
        move(w,to:id)
    }
    private func move(_ w:DeskWindow,to id:UInt32) {
        do {
            try port.move(w,to:id);successfulMoves+=1
            notice="Moved "+w.app+" to "+(port.screens.first{$0.id==id}?.name ?? "the destination")+"."
            if focus?.id==w.id || focus.map({$0.owner==w.owner && CFEqual($0.element,w.element)}) == true {focus=nil}
        } catch { notice=error.localizedDescription }
        if destination != nil {refresh()}
    }
    func toggle(captured:Bool) {
        guard port.trusted else{notice="Moving windows needs Accessibility.";NSSound.beep();return}
        guard let w=captured ? focus : port.current(previous:nil) else{notice="Focus a normal app window first.";NSSound.beep();return}
        guard let other=WindowPlacement.otherDisplay(containing:w.original,connected:port.screens.map(\.id)) else{
            notice="Connect two separate displays to move a window between them.";return
        }
        move(w,to:other)
    }
    func observeFocus() {
        lastExternal=NSWorkspace.shared.frontmostApplication
        observer=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main){[weak self] n in
            guard let app=n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular,app.processIdentifier != getpid() else{return}
            MainActor.assumeIsolated{self?.lastExternal=app}
        }
    }
    func close(){job?.cancel();job=nil;ticket=UUID();destination=nil;focus=nil;choices=[];iconCache=[:];showing=false;loading=false;notice="";sourceNames="";hint=""}
    func stop(){close();if let observer{NSWorkspace.shared.notificationCenter.removeObserver(observer)};observer=nil}
    #if DEBUG
    func loadFixture(onTV:Bool=false){let desk=FixtureWindowDesk();port=desk;capture(destination:onTV ? desk.tv:desk.samsung)}
    func finishScan() async {await job?.value}
    #endif
}
