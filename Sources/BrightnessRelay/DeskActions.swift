import SwiftUI

struct DeskWindowsView: View {
    @ObservedObject var windows: DeskWindows
    @ObservedObject var shortcuts: DeskShortcuts
    let requestAccess: () -> Void
    var openPicker: (() -> Void)? = nil
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            HStack {
                Text("Bring a window here").font(DeckPaint.title(16))
                Spacer()
                Label(windows.destinationName, systemImage: "arrow.turn.down.left")
                    .lineLimit(1).font(.caption.weight(.semibold))
                    .padding(.horizontal,7).padding(.vertical,3)
                    .background(DeckPaint.button,in:Capsule())
                    .accessibilityLabel("To "+windows.destinationName)
            }
            if !windows.sourceNames.isEmpty || openPicker != nil {
                HStack {
                    if !windows.sourceNames.isEmpty {
                        Text("From "+windows.sourceNames).font(.caption).foregroundStyle(DeckPaint.muted).lineLimit(1)
                    }
                    Spacer(minLength:4)
                    if let openPicker {
                        Button {openPicker()} label: {
                            HStack(spacing:5){
                                Label("Window picker",systemImage:"macwindow")
                                if let key=shortcuts.activeBinding(.bringHere){Text(key.label)}
                            }.fixedSize()
                        }.buttonStyle(.borderless).controlSize(.small)
                            .help("Choose a window using visible letter keys")
                    }
                }
            }
            if windows.choices.isEmpty {
                HStack {
                    Text(windows.hint).font(.caption).foregroundStyle(DeckPaint.muted)
                    if !windows.trusted {Button("Enable Accessibility",action:requestAccess)}
                }.controlSize(.small).frame(minHeight:38)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing:5) {
                        ForEach(windows.choices) { w in
                            DeskWindowTile(window:w,icon:windows.icon(for:w),destination:windows.destinationName,bring:{windows.bring(w)})
                        }
                    }.padding(.vertical,1)
                }.frame(height:41)
            }
            HStack {
                Button {windows.toggle(captured:true)} label:{
                    HStack(spacing:4) {
                        Label("Move focused window",systemImage:shortcuts.symbol(.move))
                        if let key=shortcuts.activeBinding(.move){ Text(key.label).font(.system(size:10)) }
                    }
                }.disabled(windows.focus==nil || windows.sourceNames.isEmpty)
                .help(shortcuts.activeBinding(.move)?.label ?? "Move the captured window to the other display")
                Spacer()
                Button(windows.showing ? "Close list":"All windows…"){windows.list()}
                    .buttonStyle(.borderless).disabled(!windows.trusted || windows.sourceNames.isEmpty)
            }.controlSize(.small).font(.system(size:11,weight:.medium))
            if windows.showing {
                ForEach(windows.choices) { w in
                    Button { windows.bring(w) } label: {
                        Text(windows.label(w)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                    }.controlSize(.small).help("Bring this window to "+windows.destinationName)
                }
            }
            if !windows.notice.isEmpty {Text(windows.notice).font(.caption)}
        }.padding(.horizontal,16).padding(.vertical,10)
        .frame(maxWidth:.infinity,minHeight:117,alignment:.leading)
        .foregroundStyle(DeckPaint.ink)
        .overlay(alignment:.top) { Rectangle().fill(DeckPaint.rule).frame(height:0.5) }
        .overlay(alignment:.bottom) { Rectangle().fill(DeckPaint.rule).frame(height:0.5) }
    }
}

private struct DeskWindowTile: View {
    let window:DeskWindow,icon:NSImage?,destination:String,bring:()->Void
    private var actionName:String{"Bring \(window.app), \(window.displayTitle) to \(destination)"}
    @ViewBuilder private var appIcon:some View {
        if let icon { Image(nsImage:icon).resizable().frame(width:24,height:24) }
        else { Image(systemName:"macwindow").frame(width:24,height:24) }
    }
    private var tile:some View {
        HStack(spacing:5){
            appIcon
            VStack(alignment:.leading,spacing:2){
                Text(verbatim:window.app).font(Font.system(size:11.5,weight:.semibold))
                Text(verbatim:window.displayTitle).font(.system(size:10.5)).foregroundStyle(DeckPaint.muted)
            }.lineLimit(1)
            Spacer(minLength:0)
        }.padding(.horizontal,6).frame(width:135,height:37)
        .background(DeckPaint.button,in:RoundedRectangle(cornerRadius:8))
        .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(DeckPaint.rule,lineWidth:1))
    }
    var body:some View {
        Button(action:bring){tile}.buttonStyle(.plain).accessibilityLabel(Text(actionName)).help(actionName)
    }
}

struct DeskShortcutEditor: View {
    @ObservedObject var shortcuts: DeskShortcuts
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text("Shortcuts & icons").font(DeckPaint.title(16)); Spacer()
                Button("Use suggested keys") { shortcuts.suggestions() }
                    .help("Fill only unassigned actions, including ⌃⌥Space for the window picker and ⌃⌥Return for Arrange here. Smart TV stays click-only.")
            }
            Text("Choose an icon or record a global shortcut. Esc cancels recording.").font(.caption).foregroundStyle(DeckPaint.muted)
            ForEach(DeskAction.allCases) { action in
                HStack {
                    Menu {
                        ForEach(DeskAction.symbols, id:\.0) { item in
                            Button { shortcuts.changeIcon(action,item.0) } label: { Label(item.1,systemImage:item.0) }
                        }
                        Divider()
                        Button("Restore default icon") { shortcuts.changeIcon(action,action.symbol) }
                    } label: { Image(systemName:shortcuts.symbol(action)).frame(width:24) }
                    .fixedSize().accessibilityLabel("Icon for "+action.name)
                    .help("Change "+action.name+" icon")
                    Text(action.name)
                    Spacer()
                    if action == .home {
                        Text("Button only").font(.caption).foregroundStyle(DeckPaint.muted)
                    } else {
                        if shortcuts.unavailable.contains(action) { Image(systemName:"exclamationmark.triangle").help("Shortcut unavailable") }
                        Button(shortcuts.recording == action ? "Press keys…" : shortcuts.binding(action)?.label ?? "Record…") { shortcuts.record(action) }
                            .accessibilityLabel("Record shortcut for "+action.name)
                            .accessibilityValue(shortcuts.binding(action)?.label ?? "Unassigned")
                        if shortcuts.binding(action) != nil {
                            Button { shortcuts.clear(action) } label: { Image(systemName:"xmark.circle") }
                                .accessibilityLabel("Clear shortcut for "+action.name)
                        }
                    }
                }
            }
            if !shortcuts.notice.isEmpty { Text(shortcuts.notice).font(.caption) }
        }.controlSize(.small).padding(12).frame(maxWidth:.infinity,alignment:.leading)
        .background(DeckPaint.shelf,in:RoundedRectangle(cornerRadius:10))
    }
}

@MainActor private final class TVForm: ObservableObject {
    @Published var setup = false
    @Published var mapping = false
    @Published var code = ""
    @Published var ps5 = ""
    @Published var mini = ""
    @Published var picker1 = false
    @Published var picker3 = false
    @Published var ps5HDMI = 1
    @Published var miniHDMI = 3
    @Published var tvHost = ""
}

struct TVStrip: View {
    @ObservedObject var remote: TVRemote
    @ObservedObject var shortcuts: DeskShortcuts
    let display: String
    @StateObject private var form = TVForm()
    var previewMapping = false
    var previewPairing = false
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            HStack(spacing:7) {
                Text("TV source").font(DeckPaint.title(27)).tracking(-0.5).fixedSize()
                Spacer(minLength:2)
                if remote.paired != nil || remote.fixture {
                    Text(remote.ready ? "TV connected" : "Pairing saved").font(.caption.weight(.semibold)).lineLimit(1)
                }
                if remote.paired != nil && !remote.ready {
                    Button("Reconnect") { remote.reconnect() }.disabled(remote.pairingInProgress)
                }
                Button(form.setup ? "Close setup" : (remote.paired == nil && !remote.fixture ? "Pair TV" : "Set up")) {
                    form.setup.toggle(); form.mapping = false; form.code = ""
                }
            }
            SolarKeyGroup {
                VStack(spacing:8) {
                    HStack(spacing:8) {
                        source(.ps5)
                        source(.mac)
                    }
                    source(.home)
                }
            }
            Text(remote.notice).font(.caption).padding(.top,1)
                .onChange(of:remote.requestedSetup){_,_ in applySetupRequests()}
                .onChange(of:remote.requestedMapping){_,_ in applySetupRequests()}
            if form.setup {
                if remote.wantsCode {
                    VStack(alignment:.leading,spacing:6) {
                        Text("Enter the code shown on your TV").font(.system(size:13,weight:.semibold))
                        Text("Use the six-character code on the physical TV, not your Mac password.").font(.caption)
                        HStack {
                            SecureField("TV code",text:$form.code).foregroundStyle(Color(nsColor:.textColor))
                                .accessibilityLabel("Six-character TV pairing code").onSubmit { submit() }
                            Button("Verify") { submit() }.disabled(form.code.count != 6)
                            Button("Cancel") { form.code = ""; remote.cancelPairing() }
                        }
                    }
                } else {
                    Button(remote.paired == nil ? "Show code on TV" : "Pair again with TV code") {
                        form.code = ""; remote.pairWithCode(display:display,address:form.tvHost)
                    }.disabled(remote.pairingInProgress)
                    Text("Shows a code on the TV. Your saved pairing stays until the new code is verified.").font(.caption)
                    if remote.pairingInProgress { Button("Cancel pairing") { remote.cancelPairing() } }
                    ForEach(remote.names,id:\.self) { name in
                        Button("Show code on "+name) { remote.pair(name,display:display) }.disabled(remote.pairingInProgress)
                    }
                    DisclosureGroup("TV not found? Use its network address") {
                        Text("TV IPv4 address · find it in the TV's Network settings").font(.caption)
                        TextField("For example, 192.168.1.20",text:$form.tvHost)
                            .foregroundStyle(Color(nsColor:.textColor)).accessibilityLabel("TV local IPv4 address")
                        Text("Then choose Show code on TV or Pair again above. The address alone never replaces pairing.").font(.caption)
                    }.tint(DeckPaint.ink)
                }
                if let p = remote.paired {
                    Button("Open TV inputs") { remote.inputMenu() }.disabled(!remote.ready)
                    Button(form.mapping ? "Close input mapping" : "Configure TV inputs…") {
                        form.mapping.toggle(); form.ps5 = p.ps5; form.mini = p.mini; form.picker1 = p.ps5Picker; form.picker3 = p.miniPicker
                        form.ps5HDMI = p.hdmi(.ps5); form.miniHDMI = p.hdmi(.mac)
                    }
                    if form.mapping {
                        Text("Assign devices to physical ports. Saving updates the buttons and their shortcuts; it does not switch the TV.").font(.caption)
                        Picker("PS5 port",selection:$form.ps5HDMI) {
                            ForEach(p.availableHDMIPorts,id:\.self) { Text("HDMI \($0)").tag($0) }
                        }.onChange(of:form.ps5HDMI) { _,port in form.ps5 = p.hdmiInputs?[String(port)] ?? "" }
                        Text("PS5 input ID (advanced)").font(.caption)
                        TextField("Blank uses the standard HDMI key",text:$form.ps5)
                            .foregroundStyle(Color(nsColor:.textColor)).accessibilityLabel("PS5 input ID")
                        Toggle("PS5 uses input chooser",isOn:$form.picker1)
                        Picker("Mac mini port",selection:$form.miniHDMI) {
                            ForEach(p.availableHDMIPorts,id:\.self) { Text("HDMI \($0)").tag($0) }
                        }.onChange(of:form.miniHDMI) { _,port in form.mini = p.hdmiInputs?[String(port)] ?? "" }
                        Text("Mac mini input ID (advanced)").font(.caption)
                        TextField("Blank uses the standard HDMI key",text:$form.mini)
                            .foregroundStyle(Color(nsColor:.textColor)).accessibilityLabel("Mac mini input ID")
                        Toggle("Mac mini uses input chooser",isOn:$form.picker3)
                        Text("Saved port IDs come from this TV, not a device detector. Blank IDs use standard keys, which some TVs ignore. Enable the input chooser only if it works on your TV.").font(.caption)
                        Button("Save mapping") { remote.map(ps5:form.ps5,mini:form.mini,ps5Picker:form.picker1,miniPicker:form.picker3,ps5HDMI:form.ps5HDMI,miniHDMI:form.miniHDMI) }
                    }
                }
            }
        }.controlSize(.small).buttonStyle(SolarUtilityButtonStyle())
        .padding(.horizontal,16).padding(.vertical,11)
        .frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(DeckPaint.ink)
        .onAppear {
            applySetupRequests()
            if previewPairing { form.setup = true }
            if previewMapping, let p = remote.paired {
                form.setup = true; form.mapping = true; form.ps5HDMI = p.hdmi(.ps5); form.miniHDMI = p.hdmi(.mac)
                form.ps5 = p.ps5; form.mini = p.mini; form.picker1 = p.ps5Picker; form.picker3 = p.miniPicker
            }
        }
    }
    private func submit() { remote.verify(form.code); form.code = "" }
    private func applySetupRequests() {
        if remote.requestedSetup != nil {form.setup=true;form.mapping=false;remote.requestedSetup=nil}
        if remote.requestedMapping != nil {
            form.setup=true;form.mapping=true;remote.requestedMapping=nil
            if let p=remote.paired {form.ps5HDMI=p.hdmi(.ps5);form.miniHDMI=p.hdmi(.mac);form.ps5=p.ps5;form.mini=p.mini;form.picker1=p.ps5Picker;form.picker3=p.miniPicker}
        }
    }
    private func source(_ a: DeskAction) -> some View {
        let picker = remote.usesPicker(a)
        let route = remote.routeLabel(a)
        let name = a.name+(picker ? "…" : "")
        let icon = shortcuts.symbol(a)
        return Button { remote.activate(a) } label: {
            if a == .home {
                HStack(spacing:8) {
                    Image(systemName:icon).font(.system(size:13,weight:.semibold)).accessibilityHidden(true)
                    Text(name).font(.system(size:13,weight:.semibold))
                    Spacer()
                    Text(route).font(.caption)
                    Image(systemName:"arrow.up.right").font(.system(size:9,weight:.semibold)).accessibilityHidden(true)
                }.padding(.horizontal,10).frame(height:29)
            } else {
                VStack(alignment:.leading,spacing:5) {
                    HStack {
                        Image(systemName:icon).font(.system(size:17,weight:.semibold)).accessibilityHidden(true)
                        Spacer(minLength:0)
                        if let key = shortcuts.activeBinding(a) {
                            Text(key.label).font(.system(size:10,weight:.semibold))
                                .padding(.horizontal,5).padding(.vertical,2)
                                .background(DeckPaint.button,in:RoundedRectangle(cornerRadius:4))
                        }
                    }
                    HStack(alignment:.firstTextBaseline,spacing:4) {
                        Text(name).font(DeckPaint.title(18)).lineLimit(1)
                        Spacer(minLength:0)
                        Text(route).font(.caption.weight(.medium)).lineLimit(1)
                    }
                }.padding(.horizontal,11).frame(height:62)
            }
        }.buttonStyle(SolarSourceKeyStyle(primary:a != .home)).disabled(!remote.ready)
        .accessibilityLabel("Send "+a.name+" · "+route)
        .help([picker ? "Open TV input chooser" : a.name,shortcuts.activeBinding(a)?.label].compactMap{$0}.joined(separator:" · "))
    }
}
