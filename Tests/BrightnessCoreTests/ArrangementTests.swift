import Foundation
import CoreGraphics
import Testing
@testable import BrightnessCore

private func arrangementWindows(_ count:Int)->[ArrangementWindow] {
    (0..<count).map{.init(id:"w\($0)",app:"App \($0)",title:"Fixture",frame:CGRect(x:CGFloat($0*30),y:CGFloat($0*20),width:700,height:500))}
}
@Test func arrangementLayoutsFitPortraitAndLandscapeWithoutOverlap() {
    for bounds in [CGRect(x:0,y:0,width:1440,height:2560),CGRect(x:-1920,y:722,width:1920,height:1080)] {
        for mode in ArrangementMode.allCases {for n in 1...8 {
            let display=ArrangementDisplay(id:1,name:"Fixture",usable:bounds,scale:2)
            guard let plan=ArrangementPlanner.plan(windows:arrangementWindows(n),display:display,mode:mode) else{Issue.record("Expected feasible \(n) windows");continue}
            #expect(Set(plan.items.map{ $0.window.id })==Set(arrangementWindows(n).map(\.id)))
            for item in plan.items {#expect(bounds.contains(item.target));#expect(item.target.width>=320);#expect(item.target.height>=200)}
            for i in plan.items.indices {for j in plan.items.indices where j>i {#expect(plan.items[i].target.intersection(plan.items[j].target).isEmpty)}}
        }}
    }
}
@Test func arrangementRejectsImpossibleAndInvalidPlans() {
    let d=ArrangementDisplay(id:1,name:"Fixture",usable:CGRect(x:0,y:0,width:600,height:400))
    #expect(ArrangementPlanner.plan(windows:arrangementWindows(4),display:d,mode:.smart)==nil)
    #expect(ArrangementPlanner.plan(windows:[],display:d,mode:.equal)==nil)
    let w=arrangementWindows(1)[0]
    #expect(ArrangementPlanner.plan(windows:[w,w],display:d,mode:.smart)==nil)
    #expect(ArrangementPlanner.plan(windows:[w],display:.init(id:1,name:"Bad",usable:.infinite),mode:.smart)==nil)
}
@Test func arrangementPreservesFixedSizeAndDeterminism() {
    let fixed=ArrangementWindow(id:"fixed",app:"Fixed",title:"Fixture",frame:CGRect(x:10,y:10,width:420,height:300),resizable:false)
    let d=ArrangementDisplay(id:1,name:"Fixture",usable:CGRect(x:0,y:0,width:1440,height:2560))
    let input=[fixed]+arrangementWindows(3)
    let a=ArrangementPlanner.plan(windows:input,display:d,mode:.smart)
    #expect(a==ArrangementPlanner.plan(windows:input.reversed(),display:d,mode:.smart))
    #expect(a?.items.first(where:{$0.window.id=="fixed"})?.target.size==fixed.frame.size)
}
private final class ArrangementFake:ArrangementDriver {
    var screen=ArrangementDisplay(id:1,name:"Fixture",usable:CGRect(x:0,y:0,width:1440,height:2560))
    var frames=[String:CGRect](),writes=[String](),afterWrite:(()->Void)?
    var refuse=false
    var settleAfterReads=0,pending:[String:(CGRect,Int)]=[:]
    init(_ windows:[ArrangementWindow]){frames=Dictionary(uniqueKeysWithValues:windows.map{($0.id,$0.frame)})}
    func display(_ id:UInt32)async->ArrangementDisplay? {id==screen.id ? screen:nil}
    func read(_ id:String)async throws->CGRect{
        if let (target,reads)=pending[id] {
            if reads<=0{frames[id]=target;pending.removeValue(forKey:id)}else{pending[id]=(target,reads-1)}
        }
        guard let frame=frames[id] else{throw TVError("Closed")};return frame
    }
    func write(_ id:String,frame:CGRect)async throws{
        writes.append(id)
        if !refuse{if settleAfterReads>0{pending[id]=(frame,settleAfterReads)}else{frames[id]=frame}}
        afterWrite?()
    }
}
@Test func arrangementApplyAndUndoOnlyExactUnchangedWindows() async throws {
    let windows=arrangementWindows(4),driver=ArrangementFake(arrangementWindows(4))
    let plan=try #require(ArrangementPlanner.plan(windows:windows,display:driver.screen,mode:.smart))
    let result=await ArrangementTransaction.apply(plan,driver:driver,pause:{})
    #expect(result.complete && driver.writes.count==4 && result.undo.entries.count==4)
    driver.frames["w1"] = CGRect(x:20,y:20,width:450,height:450)
    _ = await ArrangementTransaction.undo(result.undo,driver:driver)
    #expect(driver.frames["w0"]==windows[0].frame)
    #expect(driver.frames["w1"]==CGRect(x:20,y:20,width:450,height:450))
    #expect(driver.writes.count==7)
}
@Test func arrangementStalePreviewWritesNothing() async throws {
    let driver=ArrangementFake(arrangementWindows(3)),plan=try #require(ArrangementPlanner.plan(windows:arrangementWindows(3),display:driver.screen,mode:.smart))
    driver.frames.removeValue(forKey:"w2")
    let result=await ArrangementTransaction.apply(plan,driver:driver,pause:{})
    #expect(!result.complete && driver.writes.isEmpty)
}
@Test func arrangementDisconnectStopsAfterOneWriteWithUndoRecord() async throws {
    let driver=ArrangementFake(arrangementWindows(3)),plan=try #require(ArrangementPlanner.plan(windows:arrangementWindows(3),display:driver.screen,mode:.smart))
    driver.afterWrite={driver.screen = .init(id:2,name:"Replacement",usable:driver.screen.usable)}
    let result=await ArrangementTransaction.apply(plan,driver:driver,pause:{})
    #expect(!result.complete && driver.writes.count==1 && result.undo.entries.count==1)
}
@Test func arrangementRefusalNeverLoopsWrites() async throws {
    let driver=ArrangementFake(arrangementWindows(3)),plan=try #require(ArrangementPlanner.plan(windows:arrangementWindows(3),display:driver.screen,mode:.equal))
    driver.refuse=true
    let result=await ArrangementTransaction.apply(plan,driver:driver,pause:{})
    #expect(!result.complete && driver.writes.count==1 && result.undo.entries.isEmpty)
}

@Test func arrangementCancellationKeepsPartialUndoAndStopsWrites() async throws {
    let driver=ArrangementFake(arrangementWindows(3)),plan=try #require(ArrangementPlanner.plan(windows:arrangementWindows(3),display:driver.screen,mode:.equal))
    driver.afterWrite={withUnsafeCurrentTask{$0?.cancel()}}
    let task=Task{await ArrangementTransaction.apply(plan,driver:driver,pause:{})}
    let result=await task.value
    #expect(!result.complete && driver.writes.count==1 && result.undo.entries.count==1)
}

@Test func arrangementRejectsUnboundedAppMinimum() {
    let d=ArrangementDisplay(id:1,name:"Fixture",usable:CGRect(x:0,y:0,width:1440,height:2560))
    let w=ArrangementWindow(id:"bad",app:"Bad",title:"",frame:CGRect(x:0,y:0,width:500,height:500),minimum:CGSize(width:1e100,height:200))
    #expect(ArrangementPlanner.plan(windows:[w],display:d,mode:.smart)==nil)
}

@Test func arrangementEqualReallyUsesEqualZonesForOddCounts() throws {
    for size in [CGSize(width:1440,height:2560),CGSize(width:1920,height:1080)] {
        for count in [3,5,7] {
            let display=ArrangementDisplay(id:1,name:"Fixture",usable:CGRect(origin:.zero,size:size),scale:2)
            let plan=try #require(ArrangementPlanner.plan(windows:arrangementWindows(count),display:display,mode:.equal))
            let first=try #require(plan.items.first?.zone)
            for item in plan.items {
                #expect(abs(item.zone.width-first.width)<=0.5)
                #expect(abs(item.zone.height-first.height)<=0.5)
            }
        }
    }
}

@Test func arrangementUndoWaitsForDelayedNativeReadback() async throws {
    let driver=ArrangementFake(arrangementWindows(2)),plan=try #require(ArrangementPlanner.plan(windows:arrangementWindows(2),display:driver.screen,mode:.equal))
    let applied=await ArrangementTransaction.apply(plan,driver:driver,pause:{})
    driver.settleAfterReads=3
    let restored=await ArrangementTransaction.undo(applied.undo,driver:driver,pause:{})
    #expect(restored.remaining.entries.isEmpty)
    #expect(restored.message=="Restored 2 windows.")
    #expect(driver.writes.count==4)
    #expect(driver.frames["w0"]==arrangementWindows(2)[0].frame)
}

@Test func arrangementUndoRetainsRefusedRecoveryWithoutRepeatedWrites() async throws {
    let driver=ArrangementFake(arrangementWindows(2)),plan=try #require(ArrangementPlanner.plan(windows:arrangementWindows(2),display:driver.screen,mode:.equal))
    let applied=await ArrangementTransaction.apply(plan,driver:driver,pause:{})
    driver.refuse=true
    let refused=await ArrangementTransaction.undo(applied.undo,driver:driver,pause:{})
    #expect(refused.remaining.entries.count==2 && driver.writes.count==4)
    driver.refuse=false
    let restored=await ArrangementTransaction.undo(refused.remaining,driver:driver,pause:{})
    #expect(restored.remaining.entries.isEmpty && driver.writes.count==6)
}

@Test func arrangementUndoCancellationPreservesUnattemptedRecovery() async throws {
    let driver=ArrangementFake(arrangementWindows(3)),plan=try #require(ArrangementPlanner.plan(windows:arrangementWindows(3),display:driver.screen,mode:.equal))
    let applied=await ArrangementTransaction.apply(plan,driver:driver,pause:{})
    driver.afterWrite={withUnsafeCurrentTask{$0?.cancel()}}
    let task=Task{await ArrangementTransaction.undo(applied.undo,driver:driver,pause:{})}
    let result=await task.value
    #expect(driver.writes.count==4 && result.remaining.entries.count==2)
}
