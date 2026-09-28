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

struct HeightAdjustmentState: Equatable {
    let selectedInstanceID: UUID?
    let currentY: Float?
    let previousY: Float?

    static let inactive = HeightAdjustmentState(selectedInstanceID: nil, currentY: nil, previousY: nil)

    var canAdjust: Bool { selectedInstanceID != nil && currentY?.isFinite == true }
    var canUndo: Bool { canAdjust && previousY?.isFinite == true }
}

/// Pure build-root-local transform editing shared by placed-object editing and future placement UI.
enum VerticalAdjustment {
    static func applying(_ direction: VerticalAdjustmentDirection, to transform: Transform) -> Transform? {
        guard isFinite(transform), transform.translation.y.isFinite else { return nil }
        let nextY = transform.translation.y + direction.signedStep
        guard nextY.isFinite else { return nil }
        return replacingY(in: transform, with: nextY)
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
