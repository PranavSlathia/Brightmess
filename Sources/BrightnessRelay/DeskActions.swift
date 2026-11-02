import SwiftUI

struct DeskWindowsView: View {
    @ObservedObject var windows: DeskWindows
    @ObservedObject var shortcuts: DeskShortcuts
    let requestAccess: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Label("Windows",systemImage:"macwindow.on.rectangle").font(.headline)
                Spacer()
                if !windows.trusted { Button("Enable Accessibility",action:requestAccess) }
                else {
                    Button(windows.showing ? "Close list" : "Choose window…") { windows.list() }
                }
            }
            if windows.trusted {
                HStack {
                    Button { windows.toggle(captured:true) } label: {
                        Label("Move to other screen",systemImage:shortcuts.symbol(.move))
                    }.disabled(windows.focus == nil).help(shortcuts.binding(.move)?.label ?? "Move the focused window to the other display")
                    if let w = windows.focus, windows.canBring {
                        Button("Bring "+w.app+" here") { windows.bring(w) }
                    }
                }
            }
            if windows.showing {
                if windows.choices.isEmpty { Text("No eligible windows on another screen.").font(.caption) }
                ForEach(windows.choices) { w in
                    Button { windows.bring(w) } label: {
                        Text(windows.label(w)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                    }.help("Move to "+windows.destinationName)
                }
            }
            if !windows.notice.isEmpty { Text(windows.notice).font(.caption) }
        }.controlSize(.small).padding(10)
        .background(.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
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
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Label("TV input",systemImage:"tv").font(.headline)
                Spacer()
                if remote.paired != nil && !remote.ready && !remote.busy { Button("Reconnect") { remote.reconnect() } }
                if !remote.fixture {
                    Button(form.setup ? "Close setup" : (remote.paired == nil ? "Pair TV" : "Set up")) {
                        form.setup.toggle(); form.mapping = false; form.code = ""
                    }
                }
            }
            HStack {
                source(.ps5); source(.mac); source(.home)
            }
            Text(remote.notice).font(.caption).foregroundStyle(.secondary)
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
        }.padding(.horizontal,12).padding(.bottom,10).controlSize(.small)
    }
    private func submit() { remote.verify(form.code); form.code = "" }
    private func source(_ a: DeskAction) -> some View {
        let picker = remote.usesPicker(a)
        return Button { remote.activate(a) } label: {
            Label(a.name+(picker ? "…" : ""),systemImage:shortcuts.symbol(a))
        }.disabled(!remote.ready).help([picker ? "Open TV input chooser" : a.name,shortcuts.binding(a)?.label].compactMap{$0}.joined(separator:" · "))
    }
}
