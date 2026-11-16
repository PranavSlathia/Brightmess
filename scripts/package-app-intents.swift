import Foundation

// Run under the same DEVELOPER_DIR as the release build. Only creates build artifacts.
func run(_ arguments:[String]) throws -> String {
    let p=Process(),pipe=Pipe();p.executableURL=URL(fileURLWithPath:"/usr/bin/xcrun");p.arguments=arguments
    p.standardOutput=pipe;p.standardError=FileHandle.standardError;try p.run()
    let data=pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit()
    guard p.terminationStatus==0 else{throw NSError(domain:"AppIntentsPackaging",code:Int(p.terminationStatus),userInfo:[NSLocalizedDescriptionKey:"Failed: \(arguments.first ?? "tool")"])}
    return String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
}
do {
    guard CommandLine.arguments.count==3 else{fatalError("Usage: package-app-intents.swift BUILD_ROOT STAGED_APP")}
    let fm=FileManager.default,root=URL(fileURLWithPath:fm.currentDirectoryPath)
    let build=URL(fileURLWithPath:CommandLine.arguments[1]),app=URL(fileURLWithPath:CommandLine.arguments[2])
    let release=build.appendingPathComponent("release").resolvingSymlinksInPath()
    let artifact=build.appendingPathComponent("app-intents");try fm.createDirectory(at:artifact,withIntermediateDirectories:true)
    let protocols=artifact.appendingPathComponent("protocols.json"),values=artifact.appendingPathComponent("values.swiftconstvalues")
    try JSONSerialization.data(withJSONObject:["AppIntent","AppEnum","AppShortcutsProvider","AppEntity","EntityQuery","AppIntentsPackage"]).write(to:protocols)
    let sources=try fm.contentsOfDirectory(at:root.appendingPathComponent("Sources/BrightnessRelay"),includingPropertiesForKeys:nil).filter{$0.pathExtension=="swift"}.map(\.path).sorted()
    let sdk=try run(["--show-sdk-path"]),swift=try run(["--find","swiftc"])
    let toolchain=URL(fileURLWithPath:swift).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
    let target="arm64-apple-macosx14.0"
    var compile=["swiftc","-parse-as-library","-module-name","BrightnessRelay","-swift-version","5","-target",target,"-sdk",sdk,"-I",release.appendingPathComponent("Modules").path,"-DSWIFT_PACKAGE","-Xfrontend","-const-gather-protocols-file","-Xfrontend",protocols.path,"-emit-const-values-path",values.path]
    for path in [release.appendingPathComponent("CPrivateDisplay.build/module.modulemap").path,build.appendingPathComponent("checkouts/swift-atomics/Sources/_AtomicsShims/include/module.modulemap").path] {compile += ["-Xcc","-fmodule-map-file="+path]}
    compile += ["-Xcc","-I"+root.appendingPathComponent("Sources/CPrivateDisplay/include").path]
    // One frontend job: per-file typecheck jobs would overwrite the same values file.
    compile += ["-emit-module","-emit-module-path",artifact.appendingPathComponent("BrightnessRelay.swiftmodule").path,"-whole-module-optimization"]
    _ = try run(compile+sources)
    let sourceList=artifact.appendingPathComponent("sources.list"),valueList=artifact.appendingPathComponent("values.list")
    try sources.joined(separator:"\n").write(to:sourceList,atomically:true,encoding:.utf8)
    try values.path.write(to:valueList,atomically:true,encoding:.utf8)
    let xcode=try run(["xcodebuild","-version"]).split(separator:"\n").last?.split(separator:" ").last.map(String.init) ?? ""
    let output=app.appendingPathComponent("Contents/Resources")
    print(try run(["appintentsmetadataprocessor","--output",output.path,"--toolchain-dir",toolchain,"--module-name","BrightnessRelay","--sdk-root",sdk,"--xcode-version",xcode,"--platform-family","macOS","--deployment-target","14.0","--target-triple",target,"--source-file-list",sourceList.path,"--swift-const-vals-list",valueList.path,"--force"]))
    let metadata=output.appendingPathComponent("Metadata.appintents/extract.actionsdata")
    let contents=try String(contentsOf:metadata,encoding:.utf8)
    for name in ["OpenBringHereIntent","PreviewArrangementIntent","SelectTVSourceIntent"] {
        guard contents.contains(name) else{throw NSError(domain:"AppIntentsPackaging",code:1,userInfo:[NSLocalizedDescriptionKey:"Missing action metadata: "+name])}
    }
    print("Validated metadata for all three BRIGHTMESS actions.")
} catch {fputs("App Intents packaging failed: \(error)\n",stderr);exit(1)}
