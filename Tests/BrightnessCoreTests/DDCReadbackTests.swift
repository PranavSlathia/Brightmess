import Testing
@testable import BrightnessHardware

@Test func ddcPacketsMatchTheVerifiedSamsungExchange() throws {
    try DDCReadbackChecks.run()
}
