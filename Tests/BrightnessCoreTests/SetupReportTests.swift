import Foundation
import Testing
@testable import BrightnessCore

@Test func diagnosticsAllowlistCannotExportRawPrivateStatus() throws {
    let secret="PRIVATE_SENTINEL_192.168.1.11_password_window_title"
    let raw:[String:Any]=["appVersion":secret,"build":secret,"sourceState":secret,"airSource":secret,"sourceSession":secret,
        "tvNotice":secret,"tvInputs":["macInputID":secret],"error":secret,"windowTitle":secret,"token":secret,
        "displays":[["name":secret,"id":secret,"method":secret,"readingKind":secret,"error":secret]],
        "acceptedSamplesSinceStart":12,"arbitraryCounter":secret]
    let report=SetupReport.make(raw),json=String(decoding:try report.json(),as:UTF8.self)
    #expect(!json.contains(secret));#expect(!json.contains("windowTitle"));#expect(report.counters.count==1)
    #expect(report.suggested?.id=="air")
}
@Test func reportSeparatesSavedPairingFromConnectionAndMappingProof() {
    let report=SetupReport.make(["tvPaired":true,"ps5Port":2,"macPort":1,"sourceState":"Live","airReadingAgeSeconds":2.0,"windowAccessibility":true])
    #expect(report.checks.first{$0.id=="tv"}?.code=="tv.unavailable")
    #expect(report.checks.first{$0.id=="network"}?.state == .notVerified)
    #expect(report.checks.first{$0.id=="ps5Port"}?.state == .notVerified)
    #expect(report.suggested?.recovery == .tvReconnect)
}
@Test func reportRejectsNonfiniteValuesAndUnknownCapabilities() throws {
    let report=SetupReport.make(["airReadingAgeSeconds":Double.infinity,"uptimeSeconds":Double.nan,"displays":[["connected":true,"method":"unverified"]]])
    #expect(report.uptimeSeconds==0);#expect(!(try report.json()).isEmpty)
    #expect(report.checks.last?.detail.contains("not verified")==true)
}

@Test func reportNamesAuthenticationFailureWithoutLeakingItsMessage() throws {
    for (failure,code) in [("identityMismatch","tv.identity_mismatch"),("identityAccess","tv.identity_access")] {
        let report=SetupReport.make(["tvPaired":true,"tvFailureCode":failure,"tvConnectionError":"PRIVATE_KEY_PATH"])
        #expect(report.checks.first{$0.id=="tv"}?.code==code)
        #expect(report.checks.first{$0.id=="tv"}?.recovery == .tvSetup)
        #expect(!String(decoding:try report.json(),as:UTF8.self).contains("PRIVATE_KEY_PATH"))
    }
}
