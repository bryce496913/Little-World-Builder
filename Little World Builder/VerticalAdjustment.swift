import Foundation
import RealityKit

enum VerticalAdjustmentConfiguration {
    static let stepMeters: Float = 0.02
}

enum VerticalAdjustmentDirection {
    case raise
    case lower

    var signedStep: Float {
        switch self {
        case .raise: return VerticalAdjustmentConfiguration.stepMeters
        case .lower: return -VerticalAdjustmentConfiguration.stepMeters
        }
    }
}

/// Transient, height-only history. Reset always retains the original baseline, even after eviction.
struct HeightEditSession: Equatable {
    static let maximumHistoryCount = 200
    let selectedObjectID: UUID
    let startingLocalY: Float
    private(set) var undoStack: [Float] = []

    mutating func record(y: Float) {
        if undoStack.count == Self.maximumHistoryCount { undoStack.removeFirst() }
        undoStack.append(y)
    }
    mutating func undo() -> Float? { undoStack.popLast() }
    mutating func clearHistory() { undoStack.removeAll(keepingCapacity: true) }
}

struct HeightAdjustmentState: Equatable {
    let selectedInstanceID: UUID?
    let currentY: Float?
    let previousY: Float?
    var startingLocalY: Float? = nil

    static let inactive = HeightAdjustmentState(selectedInstanceID: nil, currentY: nil, previousY: nil)

    var canAdjust: Bool { selectedInstanceID != nil && currentY?.isFinite == true }
    var canUndo: Bool { canAdjust && previousY?.isFinite == true }
    var canReset: Bool {
        guard canAdjust, let currentY, let startingLocalY, startingLocalY.isFinite else { return false }
        return currentY != startingLocalY
    }
}

/// Pure build-root-local transform editing shared by placed-object editing and future placement UI.
enum VerticalAdjustment {
    static func applying(_ direction: VerticalAdjustmentDirection, to offset: Float) -> Float? {
        guard offset.isFinite else { return nil }
        let result = offset + direction.signedStep
        return result.isFinite ? result : nil
    }

    static func applying(offset: Float, to transform: Transform) -> Transform? {
        guard offset.isFinite, isFinite(transform) else { return nil }
        let nextY = transform.translation.y + offset
        guard nextY.isFinite else { return nil }
        return replacingY(in: transform, with: nextY)
    }

    static func applying(_ direction: VerticalAdjustmentDirection, to transform: Transform) -> Transform? {
        applying(offset: direction.signedStep, to: transform)
    }

    static func restoring(y: Float, in transform: Transform) -> Transform? {
        guard y.isFinite, isFinite(transform) else { return nil }
        return replacingY(in: transform, with: y)
    }

    static func isFinite(_ transform: Transform) -> Bool {
        transform.translation.allFinite && transform.rotation.vector.allFinite && transform.scale.allFinite
    }

    private static func replacingY(in transform: Transform, with y: Float) -> Transform {
        var result = transform
        result.translation.y = y
        return result
    }
}

private extension SIMD3 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

private extension SIMD4 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite && w.isFinite }
}
