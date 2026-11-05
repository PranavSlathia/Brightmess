import AppKit

enum BringPaint {
    static func rgb(_ hex:UInt32)->NSColor {NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)}
    static let forest=rgb(0x153D2F),cream=rgb(0xF4F9E9),pear=rgb(0xDDEBBA)
    static func ink(_ dark:Bool)->NSColor {dark ? rgb(0xF0F4DF):forest}
    static func muted(_ dark:Bool)->NSColor {dark ? rgb(0xC0CEBB):rgb(0x3D574A)}
    static func ground(_ dark:Bool)->NSColor {dark ? rgb(0x192C24):rgb(0xF0F3E8)}
    static func rule(_ dark:Bool)->NSColor {dark ? rgb(0x576E60):rgb(0xA0B09A)}
}
final class BringTopView:NSView {override var isFlipped:Bool {true}}
final class BringPanel:NSPanel {override var canBecomeKey:Bool {true}}
final class BringButton:NSButton {
    var actionBlock:(()->Void)?
    convenience init(_ title:String,frame:NSRect,action:@escaping()->Void){
        self.init(frame:frame);self.title=title;actionBlock=action;target=self;self.action = #selector(run);bezelStyle = .rounded
    }
    @objc func run(){actionBlock?()}
}
func bringLabel(_ text:String,size:CGFloat,weight:NSFont.Weight = .regular,color:NSColor,frame:NSRect)->NSTextField {
    let field=NSTextField(labelWithString:text);field.frame=frame;field.font = .systemFont(ofSize:size,weight:weight)
    field.textColor=color;field.lineBreakMode = .byTruncatingTail;return field
}
final class BringRow:NSButton {
    let chosen:Bool,dark:Bool
    var actionBlock:(()->Void)?
    init(frame:NSRect,row:BringHereModel.Row,icon:NSImage?,chosen:Bool,dark:Bool,action:@escaping()->Void){
        self.chosen=chosen;self.dark=dark;actionBlock=action;super.init(frame:frame)
        title="";isBordered=false;target=self;self.action = #selector(run)
        setAccessibilityLabel(row.app+", "+row.detail+(row.key.isEmpty ? "":", press "+row.key))
        setAccessibilitySelected(chosen)
        let image=NSImageView(frame:NSRect(x:8,y:9,width:28,height:28))
        image.image=icon ?? NSImage(systemSymbolName:"macwindow",accessibilityDescription:row.app)
        image.contentTintColor=BringPaint.ink(dark);addSubview(image)
        addSubview(bringLabel(row.app,size:13,weight:.semibold,color:BringPaint.ink(dark),frame:NSRect(x:46,y:5,width:253,height:20)))
        addSubview(bringLabel(row.detail,size:11.5,color:BringPaint.muted(dark),frame:NSRect(x:46,y:24,width:253,height:18)))
        if !row.key.isEmpty {
            let key=bringLabel(row.key,size:14,weight:.medium,color:BringPaint.ink(dark),frame:NSRect(x:309,y:11,width:26,height:25))
            key.alignment = .center;key.wantsLayer=true;key.layer?.cornerRadius=5
            key.layer?.borderWidth=1;key.layer?.borderColor=BringPaint.muted(dark).cgColor;addSubview(key)
        }
        toolTip=row.app+" · "+row.detail
    }
    required init?(coder:NSCoder){fatalError()}
    override var isFlipped:Bool {true}
    override func draw(_ dirtyRect:NSRect){
        if chosen || isHighlighted {
            (dark ? BringPaint.rgb(0x2C4436):BringPaint.pear).setFill()
            let p=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:8,yRadius:8);p.fill()
            BringPaint.rule(dark).setStroke();p.lineWidth=1;p.stroke()
        }
    }
    @objc func run(){actionBlock?()}
}

@MainActor final class BringHerePanel:NSObject,NSWindowDelegate,NSSearchFieldDelegate {
    let model:BringHereModel
    let panel:BringPanel
    private let root=BringTopView()
    private var monitor:Any?,focusObserver:NSObjectProtocol?,appearanceObserver:NSObjectProtocol?
    private var previous:NSRunningApplication?,lastExternal:NSRunningApplication?
    private var queryField:NSSearchField?,lastStage=BringHereModel.Stage.closed
    private var lastAnnouncement=""
    private var icons=[String:NSImage](),armed=true,restoreOnClose=true,closing=false
    var requestAccess:(()->Void)?
    var fixtureAppearance:Bool?
    init(model:BringHereModel?=nil){
        self.model=model ?? BringHereModel()
        panel=BringPanel(contentRect:NSRect(x:0,y:0,width:376,height:304),styleMask:[.borderless],backing:.buffered,defer:false)
        super.init()
        panel.title="BRIGHTMESS · Bring a window here";panel.isReleasedWhenClosed=false
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .floating
        panel.collectionBehavior=[.moveToActiveSpace,.fullScreenAuxiliary];panel.delegate=self
        root.wantsLayer=true;root.layer?.cornerRadius=12;root.layer?.masksToBounds=true;panel.contentView=root
        self.model.changed={[weak self] in self?.modelChanged()}
        self.model.succeeded={[weak self] _ in self?.restoreOnClose=false}
        lastExternal=NSWorkspace.shared.frontmostApplication
        focusObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main){[weak self] note in
            guard let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,app.processIdentifier != getpid() else{return}
            MainActor.assumeIsolated{self?.lastExternal=app}
        }
        appearanceObserver=DistributedNotificationCenter.default().addObserver(forName:NSNotification.Name("AppleInterfaceThemeChangedNotification"),object:nil,queue:.main){[weak self] _ in
            MainActor.assumeIsolated{if self?.model.visible == true {self?.draw()}}
        }
    }
    func toggle(){if model.visible {dismiss() }else{open()}}
    func open(destination:UInt32?=nil){
        let front=NSWorkspace.shared.frontmostApplication
        previous=front?.processIdentifier==getpid() ? lastExternal:front
        restoreOnClose=true;icons=[:]
        armed=NSEvent.modifierFlags.intersection([.control,.option,.command,.shift]).isEmpty
        let screen=NSScreen.screens.first{NSMouseInRect(NSEvent.mouseLocation,$0.frame,false)} ?? NSScreen.main
        let id=destination ?? (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        installKeys();model.open(destination:id);place()
        panel.alphaValue=1;panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        // Alpha only: no travel when Reduce Motion is enabled, no idle animation.
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue=0.4;NSAnimationContext.runAnimationGroup {context in context.duration=0.12;panel.animator().alphaValue=1}
        }
    }
    func dismiss(restoring:Bool=true){restoreOnClose=restoring;model.close()}
    private func modelChanged(){
        guard model.visible else {
            guard !closing else{return};closing=true
            panel.orderOut(nil);if let monitor{NSEvent.removeMonitor(monitor)};monitor=nil
            icons=[:];queryField=nil;lastAnnouncement="";root.subviews.forEach{$0.removeFromSuperview()}
            if restoreOnClose,NSWorkspace.shared.frontmostApplication?.processIdentifier==getpid(),let previous,!previous.isTerminated {
                previous.activate(options:[])
            }
            self.previous=nil;closing=false;return
        }
        draw();place()
    }
    private func place(){
        guard let id=model.destination,let screen=NSScreen.screens.first(where:{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value==id}) else{return}
        let f=screen.visibleFrame,size=panel.frame.size
        panel.setFrameOrigin(NSPoint(x:max(f.minX,min(f.maxX-size.width,f.midX-size.width/2)),y:max(f.minY,min(f.maxY-size.height,f.minY+f.height*0.64-size.height/2))))
    }
    private func icon(_ window:DeskWindow)->NSImage? {
        let key="\(window.owner)/\(window.app)"
        if let cached=icons[key]{return cached}
        let icon=model.port.icon(for:window);icons[key]=icon;return icon
    }
    func draw(){
        let dark=fixtureAppearance ?? (NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua)
        panel.appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
        let visibleRows=max(3,min(6,model.rows.count)),height=CGFloat(160+visibleRows*48)+(model.notice.isEmpty ? 0:34)
        panel.setContentSize(NSSize(width:376,height:height));root.frame=NSRect(x:0,y:0,width:376,height:height)
        let keepSearch=model.stage == .search && lastStage == .search
        root.subviews.filter{!keepSearch || $0 !== queryField}.forEach{$0.removeFromSuperview()}
        if !keepSearch {queryField=nil}
        root.layer?.backgroundColor=BringPaint.ground(dark).cgColor
        let header=BringTopView(frame:NSRect(x:0,y:0,width:376,height:61));header.wantsLayer=true;header.layer?.backgroundColor=BringPaint.forest.cgColor
        header.addSubview(bringLabel(model.title,size:22,weight:.bold,color:BringPaint.cream,frame:NSRect(x:16,y:16,width:344,height:30)));root.addSubview(header)
        let muted=BringPaint.muted(dark)
        switch model.stage {
        case .apps,.group,.search:
            if model.stage == .search {
                if queryField == nil {
                    let field=NSSearchField(frame:NSRect(x:16,y:71,width:344,height:26));field.placeholderString="Search windows"
                    field.stringValue=model.query;field.delegate=self;field.setAccessibilityLabel("Search app or window name");root.addSubview(field);queryField=field
                    panel.makeFirstResponder(field)
                }
                if queryField?.stringValue != model.query {queryField?.stringValue=model.query}
            } else {root.addSubview(bringLabel(armed ? model.subtitle:"Release the shortcut keys…",size:12,color:muted,frame:NSRect(x:16,y:75,width:344,height:21)))}
            let scroll=NSScrollView(frame:NSRect(x:12,y:103,width:352,height:CGFloat(visibleRows*48)))
            scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
            let list=BringTopView(frame:NSRect(x:0,y:0,width:352,height:max(CGFloat(visibleRows*48),CGFloat(model.rows.count*48))))
            for (index,row) in model.rows.enumerated() {
                list.addSubview(BringRow(frame:NSRect(x:0,y:CGFloat(index*48),width:352,height:46),row:row,icon:row.windows.first.flatMap{icon($0)},chosen:index==model.selected,dark:dark){[weak self] in
                    guard self?.armed == true else{return};self?.model.select(index)
                })
            }
            if model.rows.isEmpty {
                let text=model.stage == .search ? "No matching windows on the other display.":"No eligible windows on the other display."
                let label=bringLabel(text,size:13,color:muted,frame:NSRect(x:4,y:18,width:340,height:42));label.maximumNumberOfLines=2;label.lineBreakMode = .byWordWrapping;list.addSubview(label)
            }
            scroll.documentView=list;root.addSubview(scroll)
            list.scrollToVisible(NSRect(x:0,y:CGFloat(model.selected*48),width:352,height:46))
        case .loading:
            root.addSubview(bringLabel("Finding windows…",size:16,weight:.semibold,color:BringPaint.ink(dark),frame:NSRect(x:20,y:111,width:336,height:30)))
        case .working:
            root.addSubview(bringLabel(model.progress,size:17,weight:.semibold,color:BringPaint.ink(dark),frame:NSRect(x:20,y:111,width:336,height:30)))
            let note=bringLabel("Esc stops further steps. A full-screen exit already sent may still finish.",size:12,color:muted,frame:NSRect(x:20,y:153,width:336,height:46));note.maximumNumberOfLines=3;note.lineBreakMode = .byWordWrapping;root.addSubview(note)
        case .problem(let text):
            let label=bringLabel(text,size:14,weight:.medium,color:BringPaint.ink(dark),frame:NSRect(x:20,y:91,width:336,height:104));label.maximumNumberOfLines=5;label.lineBreakMode = .byWordWrapping;root.addSubview(label)
            let button:BringButton
            if !model.port.trusted {
                button=BringButton("Open Accessibility settings",frame:NSRect(x:16,y:209,width:236,height:30)){[weak self] in self?.requestAccess?()}
            } else {button=BringButton("Refresh choices",frame:NSRect(x:16,y:209,width:154,height:30)){[weak self] in self?.model.refresh()}}
            button.keyEquivalent="\r";root.addSubview(button)
            if lastStage != model.stage {panel.makeFirstResponder(button)}
        case .closed:break
        }
        if !model.notice.isEmpty {root.addSubview(bringLabel(model.notice,size:11,color:muted,frame:NSRect(x:16,y:height-73,width:344,height:30)))}
        let line=NSBox(frame:NSRect(x:16,y:height-44,width:344,height:1));line.boxType = .separator;root.addSubview(line)
        let footer:String
        switch model.stage {
        case .apps:footer="← → Display      / Search      Esc Close"
        case .group:footer="← → Display      1–9 Choose      Esc Back"
        case .search:footer="↑ ↓ Choose      Return Bring      Esc Back"
        case .working:footer="Esc Cancel"
        default:footer="Esc Close"
        }
        root.addSubview(bringLabel(footer,size:12,color:muted,frame:NSRect(x:16,y:height-29,width:344,height:21)))
        root.setAccessibilityLabel(model.title)
        if model.stage != lastStage {NSAccessibility.post(element:root,notification:.layoutChanged)}
        if model.rows.indices.contains(model.selected) {
            let row=model.rows[model.selected]
            let announcement=model.title+". "+row.app+", "+row.detail+(row.key.isEmpty ? "":". Press "+row.key)
            if announcement != lastAnnouncement && panel.isVisible {
                NSAccessibility.post(element:NSApp as Any,notification:.announcementRequested,
                    userInfo:[.announcement:announcement,.priority:NSAccessibilityPriorityLevel.medium.rawValue])
            }
            lastAnnouncement=announcement
        }
        lastStage=model.stage
    }
    func controlTextDidChange(_ notification:Notification){if let field=notification.object as? NSSearchField {model.search(field.stringValue)}}
    private func installKeys(){
        if let monitor{NSEvent.removeMonitor(monitor)}
        monitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.flagsChanged]){[weak self] event in
            guard let self else{return event}
            let mods=event.modifierFlags.intersection([.control,.option,.command,.shift])
            if event.type == .flagsChanged {if !self.armed && mods.isEmpty {self.armed=true;self.draw()};return event}
            guard self.panel.isKeyWindow else{return event}
            if event.keyCode==53 {self.model.key("escape");return nil}
            guard self.armed,!event.isARepeat,mods.subtracting(.shift).isEmpty else{return event}
            let special:[UInt16:String]=[123:"left",124:"right",125:"down",126:"up",36:"return",76:"return"]
            let key=event.keyCode==48 ? (mods.contains(.shift) ? "backtab":"tab") : (special[event.keyCode] ?? event.characters?.lowercased() ?? "")
            guard self.model.handlesKey(key) else{return event}
            self.model.key(key);return nil
        }
    }
    func windowDidResignKey(_ notification:Notification){if model.visible && !model.working {dismiss(restoring:false)}}
    func stop(){dismiss(restoring:false);if let focusObserver{NSWorkspace.shared.notificationCenter.removeObserver(focusObserver)};if let appearanceObserver{DistributedNotificationCenter.default().removeObserver(appearanceObserver)}}
}
