import Foundation
import Testing
@testable import BrightnessCore

@Test func learningKeepsTheNewestMatchAndUndoRestoresPriorCurve() throws {
    let base = try BrightnessCurve()
    var c = LearnedCurve()
    c.learn(0.2, 35); c.learn(0.8, 70)
    let before = c
    c.learn(0.5, 83)
    #expect(c.target(0.5, base: base) == 83)
    let levels = (0...100).map { c.target(Double($0)/100, base: base) }
    #expect(zip(levels, levels.dropFirst()).allSatisfy { $0 <= $1 })
    c.undo()
    #expect(c.count == before.count)
    #expect(c.target(0.5, base: base) == before.target(0.5, base: base))
}

@Test func retiredSessionCannotChangeReceiverState() throws {
    var order = SourceOrder()
    let a = UUID(), b = UUID()
    try order.accept(SourceMetadata(session: a, sequence: 4, measuredAt: 1000, state: .awake), at: 1000)
    try order.accept(SourceMetadata(session: b, sequence: 1, measuredAt: 1001, state: .awake), at: 1001)
    #expect(throws: RelayProtocolError.replayedEnvelope) {
        try order.accept(SourceMetadata(session: a, sequence: 5, measuredAt: 1002, state: .asleep), at: 1002)
    }
}

@Test func noContactIsNotProofOfSleep() {
    var p = SourcePresence()
    p.receive(mode: .live, state: .awake, time: 100, brightness: 0.4)
    #expect(p.label(now: 191, solar: false) == "No recent Air reading")
    #expect(p.cutoff(started: 0) == 400)
}

@Test func quietTenMinutesPublishesOnlyHeartbeats() {
    var last:Double?=0,sends=0
    for second in stride(from:2,through:600,by:2) {
        if LivePublicationPolicy.shouldPublish(force:false,changed:false,last:last,now:Double(second)) {sends+=1;last=Double(second)}
    }
    #expect(sends==10)
    #expect(LivePublicationPolicy.shouldPublish(force:true,changed:false,last:600,now:601))
    #expect(LivePublicationPolicy.shouldPublish(force:false,changed:true,last:600,now:601))
}
@Test func publisherCoalescesBurstsDeliversFinalValueAndStops() {
    var p=LatestPublisher<Int>();p.offer(1);#expect(p.take(at:0)==1)
    for n in 2...100 {p.offer(n)}
    #expect(p.take(at:0.1)==nil)
    p.finish(1,success:true,now:0.1);#expect(p.delay(at:0.1)==0.15)
    #expect(p.take(at:0.25)==100);p.finish(100,success:true,now:0.26)
    #expect(p.delay(at:600)==nil)
}
@Test func failedPublisherRetriesRemainBoundedAndKeepNewest() {
    var p=LatestPublisher<Int>(),now=0.0;p.offer(1)
    for n in 1...12 {
        let delay=p.delay(at:now) ?? 0
        #expect(delay<=60);now+=delay
        let sent=p.take(at:now)!;p.offer(n+1);p.finish(sent,success:false,now:now)
    }
    now+=p.delay(at:now) ?? 0
    #expect(p.take(at:now)==13)
}
