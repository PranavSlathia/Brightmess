import AppIntents
import AppKit
import BrightnessCore

/// The sole action bridge. Intents reuse the running app's panels and authenticated remote.
@MainActor final class DeskIntentCoordinator {
    static let shared=DeskIntentCoordinator()
    var open:((UInt32,Bool)throws->Void)?
    var selectSource:((DeskAction)async throws->Void)?
    var pointerDisplay:()->UInt32? = {
        guard let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) else{return nil}
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    func openHere(arrange:Bool) throws -> String {
        guard let id=pointerDisplay() else {
            throw TVError("No destination display is available. Move the pointer to a connected display and try again.")
        }
        guard let open else {throw TVError("BRIGHTMESS is starting. Open the app and try again.")}
        try open(id,arrange)
        return arrange ? "Preview opened":"Picker opened"
    }
}

enum ShortcutTVSource:String,AppEnum {
    case ps5,macMini,smartTV
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name:"TV source")
    static let caseDisplayRepresentations:[Self:DisplayRepresentation]=[
        .ps5:"PS5",.macMini:"Mac mini",.smartTV:"Smart TV"
    ]
    var action:DeskAction {switch self {case .ps5:return .ps5;case .macMini:return .mac;case .smartTV:return .home}}
}
struct OpenBringHereIntent:AppIntent {
    static let title:LocalizedStringResource="Open Bring Here"
    static let description=IntentDescription("Open the window picker on the display under the pointer. No window moves until you choose one.")
    static let openAppWhenRun=false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result=try DeskIntentCoordinator.shared.openHere(arrange:false)
        return .result(value:result)
    }
}
struct PreviewArrangementIntent:AppIntent {
    static let title:LocalizedStringResource="Preview arrangement here"
    static let description=IntentDescription("Preview a layout on the pointer's display. Apply remains an explicit action.")
    static let openAppWhenRun=false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result=try DeskIntentCoordinator.shared.openHere(arrange:true)
        return .result(value:result)
    }
}
struct SelectTVSourceIntent:AppIntent {
    static let title:LocalizedStringResource="Select TV source"
    static let description=IntentDescription("Send the chosen source using your paired TV and saved input mapping. This does not confirm the picture shown.")
    static let openAppWhenRun=false
    @Parameter(title:"Source") var source:ShortcutTVSource
    static var parameterSummary:some ParameterSummary {Summary("Select \(\.$source) on TV")}
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let send=DeskIntentCoordinator.shared.selectSource else {throw TVError("Open BRIGHTMESS and try again.")}
        try await send(source.action)
        return .result(value:"Command sent")
    }
}
struct BrightmessAppShortcuts:AppShortcutsProvider {
    static var appShortcuts:[AppShortcut] {
        AppShortcut(intent:OpenBringHereIntent(),phrases:["Bring a window here with \(.applicationName)"],shortTitle:"Bring Here",systemImageName:"macwindow")
        AppShortcut(intent:PreviewArrangementIntent(),phrases:["Preview arrangement with \(.applicationName)"],shortTitle:"Arrange Here",systemImageName:"rectangle.split.2x2")
        AppShortcut(intent:SelectTVSourceIntent(),phrases:["Select TV source with \(.applicationName)"],shortTitle:"TV source",systemImageName:"tv")
    }
}
