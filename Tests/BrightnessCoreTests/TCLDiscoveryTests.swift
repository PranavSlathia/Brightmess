import Foundation
import Testing
@testable import BrightnessCore

@Test func tclDiscoveryIsOnlyALocalLocator() {
    let data = Data("14:123:Smart TV:TV:3:Smart TV:caps\0".utf8)
    #expect(TCLDiscovery.candidate(data,expectedName:"Smart TV",host:"192.168.1.8") == "192.168.1.8")
    #expect(TCLDiscovery.candidate(data,expectedName:"Other TV",host:"192.168.1.8") == nil)
    #expect(TCLDiscovery.candidate(data,expectedName:"Smart TV",host:"127.0.0.1") == nil)
    #expect(TCLDiscovery.candidate(data,expectedName:"Smart TV",host:"8.8.8.8") == nil)
    #expect(TCLDiscovery.candidate(Data(repeating:65,count:16385),expectedName:"Smart TV",host:"192.168.1.8") == nil)
}
@Test func tclDiscoveryRequestNeverContainsAnAction() {
    #expect(TCLDiscovery.request(clientID:"fixture",milliseconds:123) == Data("1:123:BRIGHTMESS:PHONE:1:BRIGHTMESS:fixture:0:0\0".utf8))
    #expect(!TCLDiscovery.isLocalIPv4("192.168.1.8:6466"))
    #expect(!TCLDiscovery.isLocalIPv4("https://192.168.1.8"))
    #expect(TCLDiscovery.isLocalIPv4("172.16.1.8"))
}
