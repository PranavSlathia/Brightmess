import Foundation

public enum BrightnessStepDirection: Sendable {
    case up
    case down
}

public enum BrightnessStepPolicy {
    public static let standardStep: UInt16 = 6
    public static let fineStep: UInt16 = 1

    public static func next(
        from current: UInt16,
        direction: BrightnessStepDirection,
        fine: Bool = false
    ) -> UInt16 {
        let boundedCurrent = min(current, 100)
        let amount = fine ? fineStep : standardStep
        switch direction {
        case .up:
            return min(boundedCurrent + amount, 100)
        case .down:
            return boundedCurrent > amount ? boundedCurrent - amount : 0
        }
    }
}

public enum DisplayConnectionPolicy {
    public static func canDisconnect(connectedDisplayCount: Int) -> Bool {
        connectedDisplayCount > 1
    }
}
