import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BrightnessCore

@MainActor final class PickerPreferences: ObservableObject {
    static let key="Brightmess.PinnedApps.v1"
    @Published private(set) var pins:[PinnedApplication]
    private let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        if let data=defaults.data(forKey:Self.key) {
            pins=(try? JSONDecoder().decode([PinnedApplication].self,from:data)) ?? []
        } else { pins=PinnedApplication.defaults;save() }
    }
    func save() { if let data=try? JSONEncoder().encode(pins) {defaults.set(data,forKey:Self.key)} }
    func remove(_ id:String) {pins.removeAll{$0.id==id};save()}
    func move(_ id:String,by delta:Int) {
        guard let i=pins.firstIndex(where:{$0.id==id}),pins.indices.contains(i+delta) else{return}
        pins.swapAt(i,i+delta);save()
    }
    func add(_ pin:PinnedApplication) {guard !pins.contains(where:{$0.id==pin.id}) else{return};pins.append(pin);save()}
}
struct PinnedAppsView:View {
    @ObservedObject var preferences:PickerPreferences
    let available:[PinnedApplication]
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Pinned apps").font(.title2.bold())
            Text("Pins lead Bring Here when they have a window on another display. Changes apply next time you open the picker.").foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing:8) {
                    ForEach(Array(preferences.pins.enumerated()),id:\.element.id) { index,pin in
                        HStack {
                            Text(pin.name);Spacer()
                            Button {preferences.move(pin.id,by:-1)} label:{Image(systemName:"arrow.up")}
                                .disabled(index==0).accessibilityLabel("Move \(pin.name) up")
                            Button {preferences.move(pin.id,by:1)} label:{Image(systemName:"arrow.down")}
                                .disabled(index==preferences.pins.count-1).accessibilityLabel("Move \(pin.name) down")
                            Button {preferences.remove(pin.id)} label:{Image(systemName:"minus")}
                                .accessibilityLabel("Unpin \(pin.name)")
                        }.padding(.vertical,3)
                    }
                    if preferences.pins.isEmpty {Text("No pinned apps. Recent moves and alphabetical order still work.").foregroundStyle(.secondary)}
                }
            }
            Menu("Pin a running app") {
                ForEach(available.filter{candidate in !preferences.pins.contains{$0.id==candidate.id}}) {pin in
                    Button(pin.name){preferences.add(pin)}
                }
            }
            Button("Choose an application…") {
                let panel=NSOpenPanel();panel.directoryURL=URL(fileURLWithPath:"/Applications")
                panel.canChooseDirectories=false;panel.allowedContentTypes=[.applicationBundle]
                if panel.runModal() == .OK,let url=panel.url,let bundle=Bundle(url:url),let id=bundle.bundleIdentifier {
                    preferences.add(.init(id:id,name:FileManager.default.displayName(atPath:url.path).replacingOccurrences(of:".app",with:"")))
                }
            }
        }.padding(20).frame(width:400,height:350)
    }
}
