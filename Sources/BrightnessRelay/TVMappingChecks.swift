#if DEBUG
import BrightnessCore
import Foundation

@MainActor enum TVMappingChecks {
    static func run() throws {
        func expect(_ b: @autoclosure () -> Bool, _ message: String) throws {
            if !b() { throw TVError(message) }
        }
        let old = PairedTV(service:"Fixture TCL",display:"fixture-tv",pin:Data([1,2,3]),
            ps5:"fixture/.Input/HW1",mini:"fixture/.Input/HW3")
        let migrated = try JSONDecoder().decode(PairedTV.self,from:JSONEncoder().encode(old))
        try expect(migrated.ps5HDMI == nil && migrated.miniHDMI == nil && migrated.route(.mac)?.code == 245,
                   "Legacy pairing/HDMI 3 migration changed")
        var catalog = migrated
        catalog.hdmiInputs = ["1":"fixture/.Input/HW1","2":"fixture/.Input/HW2","3":"fixture/.Input/HW3"]
        let changed = try catalog.settingInputs(ps5:"fixture/.Input/HW2",mini:"fixture/.Input/HW1",
            ps5HDMI:2,miniHDMI:1,ps5Picker:false,miniPicker:false)
        try expect(changed.routeLabel(.ps5) == "HDMI 2" && changed.routeLabel(.mac) == "HDMI 1",
                   "Cable reshuffle left old HDMI captions")
        try expect(changed.route(.ps5)?.link == "fixture/.Input/HW2" && changed.route(.mac)?.link == "fixture/.Input/HW1" &&
            changed.route(.ps5)?.code == 244 && changed.route(.mac)?.code == 243,
            "Buttons/shortcuts did not route to reassigned ports")
        let decoded = try JSONDecoder().decode(PairedTV.self,from:JSONEncoder().encode(changed))
        try expect(decoded.pin == old.pin && decoded.service == old.service && decoded.display == old.display &&
            decoded.hdmiInputs == catalog.hdmiInputs && decoded.routeLabel(.mac) == "HDMI 1",
            "Remapping lost TV identity or persisted port assignment")
        try expect(decoded.availableHDMIPorts == [1,2,3], "Reported TV catalog ignored")
        for (ps5Port,miniPort,ps5ID,miniID) in [(1,1,"",""),(0,1,"",""),(2,5,"",""),
            (2,1,"fixture/.Input/HW1","fixture/.Input/HW1"),(2,1,"fixture/.Input/HW3","fixture/.Input/HW1"),
            (2,1,"https://example.com","fixture/.Input/HW1")] {
            do {
                _ = try catalog.settingInputs(ps5:ps5ID,mini:miniID,ps5HDMI:ps5Port,miniHDMI:miniPort,ps5Picker:false,miniPicker:false)
                throw TVError("Invalid or mismatched mapping accepted")
            } catch let error as TVError {
                if error.localizedDescription == "Invalid or mismatched mapping accepted" { throw error }
            }
        }
        var picker = changed; picker.ps5Picker = true
        try expect(picker.route(.ps5)?.code == 178 && picker.routeLabel(.ps5) == "Input chooser" &&
            picker.route(.mac)?.link == changed.mini && picker.route(.home)?.code == 3,
            "Picker or Home crossed another action's route")
        let before = UserDefaults.standard.data(forKey:"Brightmess.TV.v1")
        let remote = TVRemote(fixture:true)
        remote.loadFixtureMapping(catalog)
        remote.map(ps5:changed.ps5,mini:changed.mini,ps5Picker:false,miniPicker:false,ps5HDMI:2,miniHDMI:1)
        try expect(remote.routeLabel(.ps5) == "HDMI 2" && remote.routeLabel(.mac) == "HDMI 1" && remote.lastSent == nil,
            "Saving the mapping changed the wrong caption or sent a TV command")
        remote.map(ps5:changed.ps5,mini:changed.mini,ps5Picker:false,miniPicker:false,ps5HDMI:2,miniHDMI:2)
        try expect(remote.routeLabel(.mac) == "HDMI 1" && UserDefaults.standard.data(forKey:"Brightmess.TV.v1") == before,
            "Rejected save or fixture changed stored pairing")
        print("TV mapping checks passed: cable reshuffle, captions, button/key routes, legacy pairing, persistence, catalog and invalid mappings.")
    }
}
#endif
