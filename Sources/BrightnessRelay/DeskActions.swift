import SwiftUI

struct DeskWindowsView: View {
    @ObservedObject var windows: DeskWindows
    let requestAccess: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Label("Windows",systemImage:"macwindow.on.rectangle").font(.headline)
                Spacer()
                if !windows.trusted { Button("Enable Accessibility",action:requestAccess) }
                else {
                    if let w = windows.focus, windows.canBring { Button("Bring "+w.app+" here") { windows.bring(w) } }
                    Button(windows.showing ? "Close list" : "Choose window…") { windows.list() }
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

struct WindowShortcutView: View {
    @ObservedObject var windows: DeskWindows
    var body: some View {
        HStack {
            Label("Move window",systemImage:"keyboard"); Spacer()
            Button(windows.recording ? "Press keys… (Esc cancels)" : windows.shortcutLabel) { windows.record() }
            if windows.shortcutLabel != "Not assigned" { Button("Clear") { windows.clearShortcut() } }
        }.controlSize(.small).disabled(windows.fixture)
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
                source("PS5","gamecontroller",243,remote.paired?.ps5Picker == true)
                source("Mac mini","desktopcomputer",245,remote.paired?.miniPicker == true)
                source("Smart TV","house",3,false)
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
                    Button("Open TV inputs") { remote.action(178,label:"Open TV inputs") }.disabled(!remote.ready)
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
    private func source(_ title: String,_ icon: String,_ key: Int,_ picker: Bool) -> some View {
        Button { remote.action(picker ? 178 : key,label:picker ? "Open TV inputs" : title) } label: {
            Label(title+(picker ? "…" : ""),systemImage:icon)
        }.disabled(!remote.ready).help(picker ? "Open TV input chooser" : title)
    }
}
