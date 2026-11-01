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
