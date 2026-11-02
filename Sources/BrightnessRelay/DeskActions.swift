import SwiftUI

struct DeskWindowsView: View {
    @ObservedObject var windows: DeskWindows
    @ObservedObject var shortcuts: DeskShortcuts
    let requestAccess: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            HStack {
                Text("Bring a window here").font(.system(size:15,weight:.bold))
                Spacer()
                Text("To "+windows.destinationName).lineLimit(1).font(.caption)
            }
            if !windows.sourceNames.isEmpty {
                Text("From "+windows.sourceNames).font(.caption).foregroundStyle(DeckPaint.muted).lineLimit(1)
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
        }.padding(.horizontal,16).padding(.vertical,9)
        .frame(maxWidth:.infinity,minHeight:137,alignment:.leading)
        .foregroundStyle(DeckPaint.ink).background(DeckPaint.shelf)
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
        .background(DeckPaint.button,in:RoundedRectangle(cornerRadius:6))
        .overlay(RoundedRectangle(cornerRadius:6).strokeBorder(DeckPaint.rule,lineWidth:1))
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
                Text("Shortcuts & icons").font(.headline); Spacer()
                Button("Use suggested keys") { shortcuts.suggestions() }
                    .help("Fill only unassigned actions: ⌃⌥⌘M, ⌃⌥⌘1, ⌃⌥⌘2. Smart TV stays click-only.")
            }
            Text("Choose an icon or record a global shortcut. Esc cancels recording.").font(.caption).foregroundStyle(.secondary)
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
                        Text("Button only").font(.caption).foregroundStyle(.secondary)
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
        .background(.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
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
}

struct TVStrip: View {
    @ObservedObject var remote: TVRemote
    @ObservedObject var shortcuts: DeskShortcuts
    let display: String
    @StateObject private var form = TVForm()
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text("TV source").font(.system(size:27,weight:.bold)).tracking(-0.9)
                Spacer()
                if remote.paired != nil || remote.fixture { Text("TV paired").font(.caption) }
                if remote.paired != nil && !remote.ready && !remote.busy { Button("Reconnect") { remote.reconnect() } }
                    Button(form.setup ? "Close setup" : (remote.paired == nil && !remote.fixture ? "Pair TV" : "Set up")) {
                        form.setup.toggle(); form.mapping = false; form.code = ""
                    }.buttonStyle(.plain).padding(4).overlay(RoundedRectangle(cornerRadius:5).strokeBorder(DeckPaint.cream.opacity(0.55)))
            }
            HStack {
                source(.ps5); source(.mac); source(.home)
            }
            Text(remote.fixture ? "Remote ready":remote.notice).font(.caption).foregroundStyle(DeckPaint.cream)
            if form.setup {
                if remote.wantsCode {
                    HStack {
                        SecureField("Code shown on TV",text:$form.code).onSubmit { submit() }
                        Button("Verify") { submit() }.disabled(form.code.count != 6)
                    }
                } else if !remote.busy {
                    if remote.names.isEmpty { Text("No Android TVs found. Check Wi-Fi and Local Network access.").font(.caption) }
                    ForEach(remote.names,id:\.self) { name in
                        Button("Pair with "+name) { remote.pair(name,display:display) }
                    }
                }
                if let p = remote.paired {
                    Button("Open TV inputs") { remote.inputMenu() }.disabled(!remote.ready)
                    Button(form.mapping ? "Close input mapping" : "Configure HDMI fallback…") {
                        form.mapping.toggle(); form.ps5 = p.ps5; form.mini = p.mini; form.picker1 = p.ps5Picker; form.picker3 = p.miniPicker
                    }
                    if form.mapping {
                        Text("Use IDs verified on this TV. Leave blank for standard HDMI keys. If neither works, use the input chooser.").font(.caption)
                        TextField("HDMI 1 · verified TCL input ID",text:$form.ps5)
                        Toggle("PS5 uses input chooser",isOn:$form.picker1)
                        TextField("HDMI 3 · verified TCL input ID",text:$form.mini)
                        Toggle("Mac mini uses input chooser",isOn:$form.picker3)
                        Button("Save mapping") { remote.map(ps5:form.ps5,mini:form.mini,ps5Picker:form.picker1,miniPicker:form.picker3) }
                    }
                }
            }
        }.controlSize(.small).padding(.horizontal,16).padding(.vertical,9)
        .frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(DeckPaint.cream).background(DeckPaint.forest)
    }
    private func submit() { remote.verify(form.code); form.code = "" }
    private func source(_ a: DeskAction) -> some View {
        let picker = remote.usesPicker(a)
        let route = picker ? "Input chooser" : (a == .ps5 ? "HDMI 1" : a == .mac ? "HDMI 3":"Home")
        return Button { remote.activate(a) } label: {
            VStack(alignment:.leading,spacing:2) {
                HStack(alignment:.top) {
                    Text(shortcuts.activeBinding(a)?.label ?? "").font(.system(size:10,weight:.semibold))
                    Spacer(minLength:0)
                }
                Spacer(minLength:0)
                Text(a.name+(picker ? "…" : "")).font(.system(size:19,weight:.bold)).tracking(-0.4)
                Text(route).font(.system(size:11,weight:.medium))
            }.padding(9).frame(maxWidth:.infinity,alignment:.leading).frame(height:99)
            .background(alignment:.topTrailing){
                Image(systemName:shortcuts.symbol(a)).resizable().scaledToFit().frame(width:61,height:43)
                    .rotationEffect(.degrees(-9)).offset(x:5,y:-3).opacity(0.64).accessibilityHidden(true)
            }.foregroundStyle(DeckPaint.forest).background(DeckPaint.pear,in:RoundedRectangle(cornerRadius:8))
            .clipShape(RoundedRectangle(cornerRadius:8))
        }.buttonStyle(.plain).disabled(!remote.ready)
        .accessibilityLabel("Send "+a.name+" · "+route)
        .help([picker ? "Open TV input chooser" : a.name,shortcuts.activeBinding(a)?.label].compactMap{$0}.joined(separator:" · "))
    }
}
