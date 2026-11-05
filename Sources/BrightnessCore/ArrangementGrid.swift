// Adapted from Rectangle 0698b04de4349f806beeb2e27b1ef9ab71b537b2.
// Copyright (c) 2019-2026 Ryan Hanson; Spectacle (c) 2017 Eric Czarny.
// MIT license: ThirdParty/Rectangle-LICENSE.txt. Pure allocation only;
// upstream window writes, cycling and infeasible execution are not imported.
import Foundation
import CoreGraphics

/// Pure backing-pixel allocation. Window discovery and native writes remain
/// outside this allocator; infeasible allocations must not be applied.
/// Callers supply a nonempty, spatially ordered window set and positive bounds.
enum ArrangementGrid {
    enum Direction: Hashable {
        case rows, columns

        var cross: Direction { self == .rows ? .columns : .rows }
    }

    enum Constraint: Equatable {
        case fixed(Int)
        case resizable(minimum: Int, maximum: Int)

        var lowerBound: Int {
            switch self {
            case .fixed(let size): return max(0, size)
            case .resizable(let minimum, _): return max(0, minimum)
            }
        }

        var upperBound: Int {
            switch self {
            case .fixed(let size): return max(0, size)
            case .resizable(_, let maximum): return max(0, maximum)
            }
        }

    }

    struct WindowConstraints: Equatable {
        var width: Constraint
        var height: Constraint

        subscript(_ direction: Direction) -> Constraint {
            get { direction == .rows ? height : width }
            set {
                if direction == .rows { height = newValue } else { width = newValue }
            }
        }
    }

    struct Bounds: Equatable {
        let left: Int
        let right: Int
        let bottom: Int
        let top: Int

        init(_ frame: CGRect) {
            left = Int(frame.minX.rounded())
            right = Int(frame.maxX.rounded())
            bottom = Int(frame.minY.rounded())
            top = Int(frame.maxY.rounded())
        }

        func extent(_ direction: Direction) -> Int {
            direction == .rows ? top - bottom : right - left
        }

        var rect: CGRect { CGRect(x: left, y: bottom, width: right - left, height: top - bottom) }
    }

    struct Layout {
        let frames: [CGRect]
        let feasible: Bool
    }

    /// Partition the work area across balanced groups and then within each group.
    /// When size restrictions cannot all fit, return equal targets marked infeasible.
    static func layout(bounds: Bounds, direction: Direction, subdivision: Int,
                       constraints: [WindowConstraints]) -> Layout {
        let count = constraints.count
        let groupCount = 1 + (count - 1) / subdivision
        var offset = 0
        let groups = (0..<groupCount).map { index -> Range<Int> in
            let population = count / groupCount + (index < count % groupCount ? 1 : 0)
            let range = offset..<(offset + population)
            offset += population
            return range
        }
        // Every member shares its group's breadth, so their permitted ranges
        // intersect. Population never determines the breadth of a group.
        let groupConstraints = groups.map { group -> Constraint in
            let limits = group.map { constraints[$0][direction] }
            return .resizable(minimum: limits.map(\.lowerBound).max()!,
                              maximum: limits.map(\.upperBound).min()!)
        }
        let breadths = balancedBandLengths(totalPixels: bounds.extent(direction), constraints: groupConstraints)
        let groupFrames = backingBandRects(bounds: bounds, lengths: breadths.lengths, direction: direction)
        var frames = [CGRect]()
        var feasible = breadths.feasible
        for (group, frame) in zip(groups, groupFrames) {
            let lengths = balancedBandLengths(totalPixels: bounds.extent(direction.cross),
                                              constraints: group.map { constraints[$0][direction.cross] })
            frames.append(contentsOf: backingBandRects(bounds: Bounds(frame), lengths: lengths.lengths,
                                                       direction: direction.cross))
            feasible = feasible && lengths.feasible
        }
        return Layout(frames: frames, feasible: feasible)
    }

    static func backingBandRects(bounds: Bounds, lengths: [Int], direction: Direction) -> [CGRect] {
        var next = direction == .rows ? bounds.top : bounds.left
        return lengths.map { length in
            if direction == .rows {
                next -= length
                return CGRect(x: bounds.left, y: next, width: bounds.right - bounds.left, height: length)
            } else {
                let rect = CGRect(x: next, y: bounds.bottom, width: length, height: bounds.top - bounds.bottom)
                next += length
                return rect
            }
        }
    }

    /// Equalize flexible bands within observed limits, retaining exact fixed
    /// extents when feasible. Infeasible restrictions use equal targets for every window.
    static func balancedBandLengths(totalPixels: Int, constraints: [Constraint]) -> (lengths: [Int], feasible: Bool) {
        guard !constraints.isEmpty, totalPixels > 0 else { return ([], false) }
        let count = constraints.count
        let equal = (0..<count).map { totalPixels / count + ($0 < totalPixels % count ? 1 : 0) }
        let lower = constraints.map(\.lowerBound)
        let upper = constraints.map(\.upperBound)
        guard zip(lower, upper).allSatisfy({ pair in pair.0 <= pair.1 }),
              lower.reduce(0, +) <= totalPixels,
              upper.reduce(0, +) >= totalPixels
        else { return (equal, false) }

        var low = 0
        var high = totalPixels
        while low < high {
            let middle = low + (high - low + 1) / 2
            let required = zip(lower, upper).reduce(0) { $0 + min($1.1, max($1.0, middle)) }
            if required <= totalPixels { low = middle } else { high = middle - 1 }
        }
        var lengths = zip(lower, upper).map { min($0.1, max($0.0, low)) }
        var remainder = totalPixels - lengths.reduce(0, +)
        for index in lengths.indices where lengths[index] == low && lengths[index] < upper[index] && remainder > 0 {
            lengths[index] += 1
            remainder -= 1
        }
        return (lengths, true)
    }
}

