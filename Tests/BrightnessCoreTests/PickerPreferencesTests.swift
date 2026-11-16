import Foundation
import Testing
@testable import BrightnessCore

@Test func pinOrderPrecedesRecencyAndKeepsExactWindows() {
    let a=UUID(),b=UUID(),c=UUID(),recent=RecentWindowIdentity(process:1,startedAt:1,window:2)
    let items:[PickerOrdering.Item]=[
        .init(id:a,app:"Terminal",title:"A",bundleID:"com.apple.Terminal",identity:nil),
        .init(id:b,app:"Aside",title:"B",bundleID:"at.studio.AsideBrowser",identity:nil),
        .init(id:c,app:"Terminal",title:"Z",bundleID:"com.apple.Terminal",identity:recent)]
    #expect(PickerOrdering.ordered(items,pins:PinnedApplication.defaults,recent:[recent])==[b,c,a])
    #expect(PickerOrdering.ordered(items,pins:[],recent:[recent])==[c,a,b])
}
@Test func recentIdentityIsBoundedAndRejectsProcessReuse() {
    var history=RecentWindowHistory()
    for n in 1...30 {history.record(.init(process:1,startedAt:1,window:UInt32(n)))}
    #expect(history.entries.count==20)
    let previous=history.entries[0];history.record(previous)
    #expect(history.entries.count==20)
    #expect(!history.entries.contains(.init(process:1,startedAt:2,window:30)))
    history.discardExitedProcesses([]);#expect(history.entries.isEmpty)
}
@Test func pinReorderDoesNotChangeInitialCollisionMeaning() {
    let entries=[WindowPickerCatalog.Entry(id:UUID(),app:"Aside",title:"One"),.init(id:UUID(),app:"Arc",title:"Two")]
    let catalog=WindowPickerCatalog(entries)
    #expect(catalog.groups.count==1 && catalog.groups[0].key=="A")
    #expect(catalog.groups[0].entries.map(\.id)==entries.map(\.id))
}
