import Foundation

/// Independent per-panel calibration. Inputs are Air slider percentages (not lux).
/// Monotone Hermite interpolation follows the shape-preserving approach in LuxCurve.
public struct LearnedCurve: Codable, Equatable, Sendable {
    private struct Point: Codable, Equatable, Sendable { let x: Int; var y: Int }
    private let version: Int
    private var points: [Point] = [] // oldest to newest; bounded by 101 integer bins
    private var previous: [Point]?
    public var count: Int { points.count }
    public var canUndo: Bool { previous != nil }
    public var isCalibrated: Bool { count > 0 }
    public var summary: String { "\(count) learned \(count == 1 ? "match" : "matches")" }
    public init(legacy: BrightnessCalibration? = nil) {
        version = 2
        if let l = legacy {
            for (x,y) in [(l.loBuiltin,l.loLum),(l.hiBuiltin,l.hiLum)] {
                if let x, let y, (0...100).contains(y) { learn(x,y) }
            }
            previous = nil
        }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        points = try c.decode([Point].self, forKey: .points)
        previous = try c.decodeIfPresent([Point].self, forKey: .previous)
        for list in [points, previous ?? []] {
            guard version == 2, list.count <= 101, Set(list.map(\.x)).count == list.count,
                  list.allSatisfy({ (0...100).contains($0.x) && (0...100).contains($0.y) }) else {
                throw DecodingError.dataCorruptedError(forKey: .points, in: c, debugDescription: "Invalid calibration")
            }
        }
    }
    public mutating func learn(_ air: Double, _ level: Int) {
        guard air.isFinite, (0...1).contains(air), (0...100).contains(level) else { return }
        let x = Int((air * 100).rounded())
        previous = points
        points.removeAll { $0.x == x }; points.append(Point(x: x, y: level))
    }
    public mutating func undo() { if let previous { points = previous; self.previous = nil } }
    public mutating func reset() { points = []; previous = nil }
    public func target(_ air: Double, base: BrightnessCurve) -> UInt16 {
        guard air.isFinite else { return base.map(normalized: 0) }
        let x = Int((min(max(air, 0), 1) * 100).rounded())
        var fit = [Int:Int]()
        for p in points {
            // Later preferences take precedence, without discarding the raw points.
            for (k,y) in fit { fit[k] = k < p.x ? min(y,p.y) : max(y,p.y) }
            fit[p.x] = p.y
        }
        let xs = fit.keys.sorted()
        guard let first = xs.first, let last = xs.last else { return base.map(normalized: air) }
        if let y = fit[x] { return UInt16(y) }
        if x < first || x > last {
            let end = x < first ? first : last
            let level = fit[end]! + Int(base.map(normalized: Double(x)/100)) - Int(base.map(normalized: Double(end)/100))
            return UInt16(clamping: min(100, max(0, level)))
        }
        let i = xs.firstIndex(where: { $0 > x })! - 1
        let ys = xs.map { Double(fit[$0]!) }
        let hs = (1..<xs.count).map { Double(xs[$0] - xs[$0-1]) }
        let ds = hs.indices.map { (ys[$0+1] - ys[$0]) / hs[$0] }
        func tangent(_ j: Int) -> Double {
            if j == 0 { return ds[0] }; if j == xs.count-1 { return ds[j-1] }
            if ds[j-1] == 0 || ds[j] == 0 { return 0 }
            let a = 2*hs[j]+hs[j-1], b = hs[j]+2*hs[j-1]
            return (a+b) / (a/ds[j-1]+b/ds[j])
        }
        let t = Double(x-xs[i])/hs[i], t2 = t*t, t3 = t2*t
        let y = (2*t3-3*t2+1)*ys[i] + (t3-2*t2+t)*hs[i]*tangent(i)
              + (-2*t3+3*t2)*ys[i+1] + (t3-t2)*hs[i]*tangent(i+1)
        return UInt16(min(ys[i+1], max(ys[i], y.rounded())))
    }
}

/// One retargetable ramp per screen, evaluated on monotonic time only while moving.
public struct LevelTransition: Sendable {
    public let start: UInt16, goal: UInt16
    public let began: Double, duration: Double
    public init(start: UInt16, goal: UInt16, began: Double, duration: Double = 1) {
        self.start = start; self.goal = goal; self.began = began; self.duration = duration
    }
    public func value(at now: Double) -> UInt16 {
        let t = duration > 0 ? min(1,max(0,(now-began)/duration)) : 1
        let smooth = t*t*(3-2*t)
        return UInt16((Double(start) + smooth*(Double(goal)-Double(start))).rounded())
    }
}
