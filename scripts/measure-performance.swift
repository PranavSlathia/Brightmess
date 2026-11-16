import Foundation
import Darwin

func command(_ path:String,_ args:[String]) throws -> String {
    let p=Process(),pipe=Pipe();p.executableURL=URL(fileURLWithPath:path);p.arguments=args
    p.standardOutput=pipe;p.standardError=FileHandle.nullDevice;try p.run()
    let data=pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit()
    guard p.terminationStatus==0 else{throw NSError(domain:"Measurement",code:1)}
    return String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
}
func cpu(_ value:String)->Double {value.split(separator:":").reduce(0){$0*60+(Double($1) ?? 0)}}
func sleepOffset()->UInt64 {
    let continuous=mach_continuous_time(),awake=mach_absolute_time()
    return continuous>=awake ? continuous-awake:0
}
let keys=["hardwareWritesSinceStart","softwareWritesSinceStart","hardwareReadAttemptsSinceStart","acceptedSamplesSinceStart","applicationRequestsSinceStart","applicationResponsesSinceStart"]
do {
    guard CommandLine.arguments.count==3,let pid=Int(CommandLine.arguments[2]) else{fatalError("Usage: measure-performance.swift air|mini PID")}
    let role=CommandLine.arguments[1],home=FileManager.default.homeDirectoryForCurrentUser
    let cli=home.appendingPathComponent(".local/bin/brightness-relay").path
    func counterSnapshot() -> [String:Double] {
        guard role=="mini",let output=try? command(cli,["status","--host","127.0.0.1"]),
              let raw=try? JSONSerialization.jsonObject(with:Data(output.utf8)) as? [String:Any] else{return [:]}
        var result=[String:Double]()
        for key in keys {if let n=raw[key] as? NSNumber {result[key]=n.doubleValue}}
        if let controls=raw["controls"] as? [String:Any],let n=controls["tvMessagesSentSinceStart"] as? NSNumber {result["tvMessagesSentSinceStart"]=n.doubleValue}
        return result
    }
    let born=try command("/bin/ps",["-p",String(pid),"-o","lstart="])
    guard !born.isEmpty else{throw NSError(domain:"Measurement",code:2)}
    let before=counterSnapshot(),initial=cpu(try command("/bin/ps",["-p",String(pid),"-o","time="]))
    let start=Date(),awake=ProcessInfo.processInfo.systemUptime,offset=sleepOffset()
    var info=mach_timebase_info_data_t();mach_timebase_info(&info)
    print("Measuring \(role) for 600 seconds. Keep the desk quiet and awake. No controls will be changed.")
    fflush(stdout)
    for _ in 0..<20 {
        Thread.sleep(forTimeInterval:30)
        guard try command("/bin/ps",["-p",String(pid),"-o","lstart="])==born else{throw NSError(domain:"Helper restarted; discard run",code:3)}
        let current=sleepOffset(),ticks=current>offset ? current-offset:0
        guard Double(ticks)*Double(info.numer)/Double(info.denom)<1_000_000_000 else{throw NSError(domain:"System slept; discard run",code:4)}
    }
    let elapsed=ProcessInfo.processInfo.systemUptime-awake
    guard abs(Date().timeIntervalSince(start)-elapsed)<3 else{throw NSError(domain:"Clock changed; discard run",code:5)}
    let final=cpu(try command("/bin/ps",["-p",String(pid),"-o","time="])),after=counterSnapshot()
    let percent=100*(final-initial)/elapsed
    var deltas=[String:Double]()
    for (key,value) in before {if let end=after[key] {guard end>=value else{throw NSError(domain:"Counters reset; discard run",code:6)};deltas[key]=end-value}}
    let report:[String:Any]=["schemaVersion":1,"role":role,"durationSeconds":elapsed,"cpuPercentOfOneCore":percent,"cpuTargetUnderOnePercent":percent<1,"counterDeltas":deltas,"measurementStatusRequests":role=="mini" ? 2:0,"scope":"Application requests, not network packets. Sender traffic is not directly measured. User activity and sensor changes must be noted separately."]
    print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
} catch {fputs("Measurement invalid: \(error)\n",stderr);exit(1)}
