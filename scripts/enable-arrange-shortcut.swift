import Foundation

// Local opt-in helper. Run only after the user chooses this binding and the
// receiver has stopped. The app still checks OS conflicts during registration.
let domain="dev.pranav.BrightnessRelay",key="Brightmess.DeskActions.v2"
guard CommandLine.arguments.dropFirst().first == "--confirmed-control-option-return",
      let prefs=UserDefaults(suiteName:domain),let original=prefs.data(forKey:key),
      var settings=(try? JSONSerialization.jsonObject(with:original)) as? [String:Any],
      var bindings=settings["bindings"] as? [String:Any] else {
    fputs("Existing shortcut settings and explicit confirmation are required.\n",stderr);exit(1)
}
if let existing=bindings["arrange"] as? [String:Any] {
    guard existing["code"] as? Int == 36,existing["mods"] as? Int == 6144 else {
        fputs("An Arrange binding already exists; not overwriting it.\n",stderr);exit(1)
    }
}
bindings["arrange"]=["code":36,"mods":6144,"label":"⌃⌥Return"]
settings["bindings"]=bindings
let data=try JSONSerialization.data(withJSONObject:settings,options:.sortedKeys)
prefs.set(data,forKey:key)
guard prefs.synchronize(),prefs.data(forKey:key)==data else {
    fputs("Could not verify shortcut preference write.\n",stderr);exit(1)
}
print("Saved only Arrange here = Control-Option-Return. Verify native registration after restart.")
