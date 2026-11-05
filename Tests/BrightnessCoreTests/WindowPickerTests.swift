import Foundation
import Testing
import CoreGraphics
@testable import BrightnessCore

@Test func retrievalWaitsThroughFullScreenGeometryGap() async throws {
    let rect=CGRect(x:0,y:0,width:1440,height:2560),target=CGRect(x:-1920,y:722,width:1920,height:1080)
    var full=true,exits=0,writes=0,missing=0,screen:UInt32=1,time=0.0
    try await WindowRetrieval.run(original:1,destination:2,read:{
        if missing>0 {missing-=1;throw WindowRetrieval.ReadError.temporarilyUnavailable}
        return .init(screen:screen,rect:full ? rect:rect.insetBy(dx:100,dy:100),usable:rect,fullFrame:rect,fullScreen:full,canExitFullScreen:true,movable:!full)
    },target:{target},exitFullScreen:{exits+=1;full=false;missing=3},write:{_ in writes+=1;screen=2;missing=2},pause:{time+=0.1},now:{time})
    #expect(exits==1 && writes==1 && time>=0.5)
}

@Test func retrievalMissingGeometryTimesOutWithoutRepeatedWrites() async {
    let rect=CGRect(x:0,y:0,width:1440,height:2560)
    var full=true,writes=0,time=0.0
    do {
        try await WindowRetrieval.run(original:1,destination:2,read:{
            if !full {throw WindowRetrieval.ReadError.temporarilyUnavailable}
            return .init(screen:1,rect:rect,usable:rect,fullFrame:rect,fullScreen:true,canExitFullScreen:true,movable:false)
        },target:{rect},exitFullScreen:{full=false},write:{_ in writes+=1},pause:{time+=0.1},now:{time})
        Issue.record("Missing geometry must time out")
    } catch {}
    #expect(writes==0 && time<=8.1)
}

@Test func retrievalDoesNotRetryPermanentClosure() async {
    let rect=CGRect(x:0,y:0,width:1440,height:2560)
    var full=true,writes=0,pauses=0
    do {
        try await WindowRetrieval.run(original:1,destination:2,read:{
            if !full {throw TVError("Closed original window")}
            return .init(screen:1,rect:rect,usable:rect,fullFrame:rect,fullScreen:true,canExitFullScreen:true,movable:false)
        },target:{rect},exitFullScreen:{full=false},write:{_ in writes+=1},pause:{pauses+=1})
        Issue.record("Closed window must fail immediately")
    } catch {}
    #expect(writes==0 && pauses==0)
}

@Test func pickerInitialsKeepEveryExactWindow() {
    let a=UUID(),b=UUID(),z=UUID()
    let catalog=WindowPickerCatalog([
        .init(id:z,app:"Zen",title:"Notes"),.init(id:a,app:"Arc",title:"Same title"),
        .init(id:b,app:"Arc",title:"Same title")])
    #expect(catalog.groups.map(\.key)==["Z","A"])
    #expect(catalog.groups.last?.entries.map(\.id)==[a,b])
}

@Test func pickerInitialCollisionDoesNotLoseOrRenumberWindows() {
    let first=WindowPickerCatalog.Entry(id:UUID(),app:"Arc",title:""),second=WindowPickerCatalog.Entry(id:UUID(),app:"Affinity",title:"A long title")
    let catalog=WindowPickerCatalog([first,second])
    #expect(catalog.groups.count==1)
    #expect(catalog.groups[0].key=="A")
    #expect(catalog.groups[0].entries==[first,second])
}

@Test func retrievalWaitsForFullScreenThenFitsPortrait() async throws {
    let wide=CGRect(x:-1920,y:0,width:1920,height:1080),portrait=CGRect(x:0,y:30,width:1440,height:2500)
    var full=true,exits=0,writes=[CGRect](),time=0.0,screen:UInt32=2
    try await WindowRetrieval.run(original:2,destination:1,read:{
        .init(screen:screen,rect:full ? wide:wide.insetBy(dx:50,dy:50),usable:wide,fullFrame:wide,fullScreen:full,canExitFullScreen:true,movable:!full)
    },target:{portrait},exitFullScreen:{exits+=1},write:{rect in writes.append(rect);screen=1},pause:{time+=0.1;full=false},now:{time})
    #expect(exits==1 && writes.count==1)
    #expect(writes[0].width<=portrait.width && portrait.contains(writes[0]))
}

@Test func retrievalRefusesSplitViewAndUnavailableDestinations() async {
    let full=CGRect(x:0,y:0,width:1920,height:1080),half=CGRect(x:0,y:0,width:960,height:1080)
    var exits=0,writes=0
    do {
        try await WindowRetrieval.run(original:1,destination:2,read:{
            .init(screen:1,rect:half,usable:full,fullFrame:full,fullScreen:true,canExitFullScreen:true,movable:false)
        },target:{full},exitFullScreen:{exits+=1},write:{_ in writes+=1})
        Issue.record("Split View should fail closed")
    } catch {}
    #expect(exits==0 && writes==0)
    do {
        try await WindowRetrieval.run(original:1,destination:2,read:{
            .init(screen:1,rect:full,usable:full,fullFrame:full,fullScreen:false,canExitFullScreen:false,movable:true)
        },target:{throw TVError("Disconnected")},exitFullScreen:{exits+=1},write:{_ in writes+=1})
        Issue.record("Disconnected destination should stop before writing")
    } catch {}
    #expect(exits==0 && writes==0)
}

@Test func retrievalTimeoutNeverSendsMove() async {
    let rect=CGRect(x:0,y:0,width:1920,height:1080)
    var writes=0,time=0.0
    do {
        try await WindowRetrieval.run(original:1,destination:2,read:{
            .init(screen:1,rect:rect,usable:rect,fullFrame:rect,fullScreen:true,canExitFullScreen:true,movable:false)
        },target:{rect},exitFullScreen:{},write:{_ in writes+=1},pause:{time+=1},now:{time})
        Issue.record("Unfinished full-screen exit should time out")
    } catch {}
    #expect(writes==0 && time==8)
}

@Test func retrievalRevalidatesSourceAfterExit() async {
    let rect=CGRect(x:0,y:0,width:1920,height:1080)
    var source:UInt32=1,full=true,writes=0
    do {
        try await WindowRetrieval.run(original:1,destination:2,read:{
            .init(screen:source,rect:rect,usable:rect,fullFrame:rect,fullScreen:full,canExitFullScreen:true,movable:true)
        },target:{rect},exitFullScreen:{full=false;source=3},write:{_ in writes+=1})
        Issue.record("An externally relocated window must not be moved again")
    } catch {}
    #expect(writes==0)
}

@Test func retrievalRechecksAfterProgressAndStopsOnCancellation() async {
    let rect=CGRect(x:0,y:0,width:1920,height:1080)
    var source:UInt32=1,writes=0
    do {
        try await WindowRetrieval.run(original:1,destination:2,read:{
            .init(screen:source,rect:rect,usable:rect,fullFrame:rect,fullScreen:false,canExitFullScreen:false,movable:true)
        },target:{rect},exitFullScreen:{},write:{_ in writes+=1},progress:{_ in source=3})
        Issue.record("A window relocated during progress cannot be moved again")
    } catch {}
    #expect(writes==0)
    var full=true
    do {
        try await WindowRetrieval.run(original:1,destination:2,read:{
            .init(screen:1,rect:rect,usable:rect,fullFrame:rect,fullScreen:full,canExitFullScreen:true,movable:!full)
        },target:{rect},exitFullScreen:{full=false},write:{_ in writes+=1},pause:{throw CancellationError()})
        Issue.record("A cancelled settling wait must stop before movement")
    } catch {}
    #expect(writes==0)
}
