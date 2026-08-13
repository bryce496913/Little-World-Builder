//
//  PlacementSettings.swift
//  AR Test
//
//  Created by Bryce on 6/07/21.
//

import Combine
import ARKit
import RealityKit

struct ModelAnchor {
    var model: Model
    var anchor: ARAnchor?
    var modelTransform: Transform? = nil
}

final class PlacementSettings: ObservableObject {

    /// The single source of truth for placement behavior in the AR builder.
    @Published var placementMode: PlacementMode = .free
    @Published var gridSettings: GridSettings = .default
    @Published private(set) var requestedQuarterTurns: Int = 0
    var latestResolvedTransform: Transform?
    var latestRawWorldTransform: simd_float4x4?

    // When the user selects a model in BrowseView, this property is set.
    @Published var selectedModel: Model? {
        willSet(newValue) {
            print("Setting selectedModel to \(String(describing: newValue?.name))")
        }
    }

    @Published var isPlacementAvailable: Bool = false
    @Published var placementStatusMessage: String = "Scan a surface"

    //  This property retains a record of placed models in the scene. The last element in the array is the most recently placed model.
    @Published var recentlyPlaced: [Model] = []

    // This property will keep track of all the content that has been confirmed for placement in the scene.
    var modelConfirmedForPlacement: [ModelAnchor] = []

    // This property retains the cancellable object for our SceneEvents.Update subscriber.
    var sceneObserver: Cancellable?

    func rotatePending(clockwise: Bool) {
        requestedQuarterTurns = (requestedQuarterTurns + (clockwise ? 1 : 3)) % 4
    }

    func resetPendingRotation() {
        requestedQuarterTurns = 0
        latestResolvedTransform = nil
        latestRawWorldTransform = nil
    }
}

enum PlacementMode: String, Codable, Equatable { case free, grid }

struct GridSettings: Codable, Equatable {
    static let `default` = GridSettings(cellSizeMeters: 0.10, rotationStepDegrees: 90, visibleRadiusInCells: 10)
    private static let maximumRadius = 50

    var cellSizeMeters: Float
    var rotationStepDegrees: Float
    var visibleRadiusInCells: Int

    init(cellSizeMeters: Float, rotationStepDegrees: Float, visibleRadiusInCells: Int) {
        self.cellSizeMeters = cellSizeMeters.isFinite && cellSizeMeters > 0 ? cellSizeMeters : Self.default.cellSizeMeters
        // This first implementation intentionally supports quarter turns only; arbitrary angles
        // would require a different footprint model.
        self.rotationStepDegrees = rotationStepDegrees.isFinite && abs(rotationStepDegrees - 90) < 0.0001 ? rotationStepDegrees : Self.default.rotationStepDegrees
        self.visibleRadiusInCells = (1...Self.maximumRadius).contains(visibleRadiusInCells) ? visibleRadiusInCells : Self.default.visibleRadiusInCells
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(cellSizeMeters: (try? values.decode(Float.self, forKey: .cellSizeMeters)) ?? Self.default.cellSizeMeters,
                  rotationStepDegrees: (try? values.decode(Float.self, forKey: .rotationStepDegrees)) ?? Self.default.rotationStepDegrees,
                  visibleRadiusInCells: (try? values.decode(Int.self, forKey: .visibleRadiusInCells)) ?? Self.default.visibleRadiusInCells)
    }
}

struct GridSnapResult {
    let transform: Transform
    let effectiveFootprint: GridFootprint
    let gridCoordinateX: Int
    let gridCoordinateZ: Int
}

enum GridSnapResolver {
    /// Snaps on the build-root-local X/Z plane. Even footprints use a half-cell phase.
    static func resolve(rawLocalTransform: Transform, footprint: GridFootprint, snapBehavior: SnapBehavior,
                        settings: GridSettings, requestedQuarterTurns: Int) -> GridSnapResult? {
        guard footprint.isValid, rawLocalTransform.translation.allFinite, rawLocalTransform.scale.allFinite else { return nil }
        if snapBehavior == .free {
            return GridSnapResult(transform: rawLocalTransform, effectiveFootprint: footprint, gridCoordinateX: 0, gridCoordinateZ: 0)
        }
        let turns = ((requestedQuarterTurns % 4) + 4) % 4
        let effective = turns.isMultiple(of: 2) ? footprint : GridFootprint(width: footprint.depth, depth: footprint.width)
        let cell = settings.cellSizeMeters
        guard cell.isFinite, cell > 0 else { return nil }
        func snap(_ value: Float, dimension: Int) -> (Float, Int) {
            let offset = dimension.isMultiple(of: 2) ? cell / 2 : 0
            let coordinate = Int(((value - offset) / cell).rounded())
            return (Float(coordinate) * cell + offset, coordinate)
        }
        let x = snap(rawLocalTransform.translation.x, dimension: effective.width)
        let z = snap(rawLocalTransform.translation.z, dimension: effective.depth)
        var result = rawLocalTransform
        result.translation = [x.0, snapBehavior == .floating ? rawLocalTransform.translation.y : 0, z.0]
        let yaw = Float(turns) * settings.rotationStepDegrees * .pi / 180
        result.rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        return result.translation.allFinite ? GridSnapResult(transform: result, effectiveFootprint: effective, gridCoordinateX: x.1, gridCoordinateZ: z.1) : nil
    }
}

private extension SIMD3 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
