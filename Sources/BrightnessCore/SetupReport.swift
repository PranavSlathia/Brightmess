import Foundation

/// Explicit export allowlist. Never encode the raw status dictionary or localized errors.
public struct SetupReport: Codable, Sendable {
    public enum State:String,Codable,Sendable {case ready,attention,notVerified}
    public enum Recovery:String,Codable,Sendable {case accessibility,sync,tvSetup,tvReconnect,inputs,displays}
    public struct Check:Codable,Identifiable,Sendable {
        public let id:String,group:String,title:String,detail:String,code:String
        public let state:State
        public let recovery:Recovery?
    }
    public let schemaVersion:Int
    public let appVersion:String,build:String
    public let uptimeSeconds:Double
    public let checks:[Check]
    public let counters:[String:UInt64]
    public var suggested:Check? {checks.first{$0.state == .attention && $0.recovery != nil}}
    public func json() throws -> Data {
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        return try encoder.encode(self)
    }
    public static func make(_ raw:[String:Any]) -> Self {
        func version(_ value:Any?) -> String {
            guard let s=value as? String,!s.isEmpty,s.count<32,s.allSatisfy({$0.isNumber || $0=="."}) else{return "unknown"};return s
        }
        func number(_ value:Any?) -> Double? {
            guard let n=value as? Double,n.isFinite,n>=0,n<1e12 else{return nil};return n
        }
        func flag(_ key:String)->Bool {raw[key] as? Bool == true}
        var rows=[Check]()
        func row(_ id:String,_ group:String,_ title:String,_ detail:String,_ code:String,_ state:State,_ recovery:Recovery?=nil) {
            rows.append(.init(id:id,group:group,title:title,detail:detail,code:code,state:state,recovery:recovery))
        }
        let source=raw["sourceState"] as? String,mode=raw["sourceMode"] as? String
        let age=number(raw["airReadingAgeSeconds"])
        let sourceOK=source == "Live" || source == "Scheduled"
        let sourceLabel=["Live","Scheduled","Air asleep","Lid closed","No recent Air reading","Solar fallback"].contains(source ?? "") ? source!:"No valid Air reading"
        row("air","Air","Source 1",sourceLabel+(age.map{" · \(Int($0))s old"} ?? "")+(mode == "scheduled" ? " · scheduled helper":""),sourceOK ? "air.ready":"air.unavailable",sourceOK ? .ready:.attention,.sync)
        let paired=flag("tvPaired"),ready=flag("tvRemoteReady"),opening=flag("tvIdentityOpening")
        let failure=raw["tvFailureCode"] as? String
        let identityIssue=failure == "identityAccess" || failure == "identityMismatch"
        let tvDetail=ready ? "Authenticated remote ready":opening ? "Waiting for saved Keychain identity; check both Mac displays":failure == "identityMismatch" ? "TV identity differs from saved pairing. No commands sent.":failure == "identityAccess" ? "Saved Keychain identity needs approval; check both Mac displays":paired ? "Pairing saved; not connected":"No TV pairing saved"
        let tvCode=ready ? "tv.ready":opening ? "tv.identity_pending":failure == "identityMismatch" ? "tv.identity_mismatch":failure == "identityAccess" ? "tv.identity_access":paired ? "tv.unavailable":"tv.unpaired"
        row("tv","TV connection","TV 1",tvDetail,tvCode,ready ? .ready:.attention,paired && !opening && !identityIssue ? .tvReconnect:.tvSetup)
        for (key,title) in [("ps5Port","PS5"),("macPort","Mac mini")] {
            let port=raw[key] as? Int
            let chooser=flag(key+"Chooser")
            let valid=port.map{(1...4).contains($0)} == true
            row(key,"TV inputs",title,paired && valid ? (chooser ? "Input chooser":"HDMI \(port!)")+" · picture not verified by this report":"No valid saved mapping","input.not_verified",.notVerified,.inputs)
        }
        row("access","Permissions","Window moves and keyboard",flag("windowAccessibility") ? "Accessibility allowed":"Accessibility required","permission.accessibility",flag("windowAccessibility") ? .ready:.attention,.accessibility)
        row("network","Permissions","Local network",ready ? "TV connection observed":"Permission state not inferred from connection failure",ready ? "network.observed":"network.unknown",ready ? .ready:.notVerified,ready ? nil:.tvSetup)
        let displays=raw["displays"] as? [[String:Any]] ?? []
        if displays.isEmpty {row("displays","Displays","No displays","No display snapshot available","display.absent",.attention,.displays)}
        for (index,display) in displays.enumerated() {
            let connected=display["connected"] as? Bool == true
            let method=display["method"] as? String,reading=display["readingKind"] as? String
            let label=method == "hardwareDDC" ? "Hardware DDC":method == "softwareDimming" ? "Software dimming":"Control method not verified"
            let readLabel:[String:String]=["liveHardware":"Fresh hardware readback","staleHardware":"Older hardware readback","lastSet":"Last command only; readback not verified","liveSoftware":"Software level; not TV hardware brightness","unavailable":"Readback not verified"]
            let readAge=number(display["hardwareReadingAgeSeconds"]).map{" · \(Int($0))s old"} ?? ""
            let known=method == "hardwareDDC" || method == "softwareDimming"
            row("display\(index+1)","Displays","Display \(index+1)",connected ? label+". "+(readLabel[reading ?? ""] ?? "Readback not verified")+readAge:"Disconnected","display."+(connected ? "connected":"disconnected"),connected ? (known ? .ready:.notVerified):.attention,connected ? nil:.displays)
        }
        let allowed=["hardwareWritesSinceStart","softwareWritesSinceStart","hardwareReadAttemptsSinceStart","acceptedSamplesSinceStart","applicationRequestsSinceStart","applicationResponsesSinceStart","tvMessagesSentSinceStart"]
        var counters=[String:UInt64]()
        for key in allowed {if let value=raw[key] as? NSNumber,value.doubleValue>=0,value.doubleValue<Double(UInt64.max){counters[key]=value.uint64Value}}
        return .init(schemaVersion:1,appVersion:version(raw["appVersion"]),build:version(raw["build"]),uptimeSeconds:number(raw["uptimeSeconds"]) ?? 0,checks:rows,counters:counters)
    }
}
