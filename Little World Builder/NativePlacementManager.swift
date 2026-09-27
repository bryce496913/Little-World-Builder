import ARKit
import RealityKit
import UIKit

enum PlacementTargetSource: Equatable {
    case placedObject
    case arPlane
}

struct PlacementTarget {
    let worldPosition: SIMD3<Float>
    let worldTransform: simd_float4x4
    let surfaceNormal: SIMD3<Float>
    let source: PlacementTargetSource
    let supportingObjectID: UUID?
}

enum PlacementQueryPurpose: Equatable {
    case newAsset
    case savedWorldRoot
}

/// Pure policy shared by RealityKit hit handling and unit tests.
enum PlacementTargetPolicy {
    /// Surfaces within about 48 degrees of world up are considered useful horizontal supports.
    static let minimumUpwardNormalDot: Float = 0.67

    struct ObjectCandidate {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let worldTransform: simd_float4x4
        let instanceID: UUID
        let category: ModelCategory?
        let placementRole: PlacementRole?
    }

    static func isSupportCapable(category: ModelCategory?, placementRole: PlacementRole?) -> Bool {
        // The existing manifest identifies islands consistently as land/base. Other roles are
        // intentionally excluded until the manifest can explicitly mark support-capable structures.
        category == .land && placementRole == .base
    }

    static func objectTarget(from candidate: ObjectCandidate?) -> PlacementTarget? {
        guard let candidate,
              isSupportCapable(category: candidate.category, placementRole: candidate.placementRole),
              candidate.position.allFinite,
              candidate.normal.allFinite else { return nil }
        let length = simd_length(candidate.normal)
        guard length.isFinite, length > 0 else { return nil }
        let normal = candidate.normal / length
        guard simd_dot(normal, SIMD3<Float>(0, 1, 0)) >= minimumUpwardNormalDot else { return nil }
        return PlacementTarget(worldPosition: candidate.position,
                               worldTransform: candidate.worldTransform,
                               surfaceNormal: normal,
                               source: .placedObject,
                               supportingObjectID: candidate.instanceID)
    }

    static func select(purpose: PlacementQueryPurpose = .newAsset,
                       objectCandidate: ObjectCandidate?,
                       planeTarget: PlacementTarget?) -> PlacementTarget? {
        guard purpose == .newAsset else { return planeTarget }
        return objectTarget(from: objectCandidate) ?? planeTarget
    }
}

private extension SIMD3 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

final class NativePlacementManager {
    private let indicator = PlacementIndicatorEntity()
    private(set) var placementTarget: PlacementTarget?

    var latestPlacementTransform: simd_float4x4? { placementTarget?.worldTransform }
    var isPlacementAvailable: Bool { placementTarget != nil }

    func install(in arView: ARView) {
        let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
        anchor.name = "native-placement-indicator-anchor"
        anchor.addChild(indicator)
        arView.scene.addAnchor(anchor)
        indicator.isEnabled = false
    }

    func update(in arView: ARView,
                isPlacementActive: Bool,
                alignment: ARRaycastQuery.TargetAlignment,
                purpose: PlacementQueryPurpose,
                models: [Model]) {
        guard isPlacementActive else { clearTarget(); return }

        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let objectCandidate = purpose == .newAsset
            ? placedObjectCandidate(at: center, in: arView, models: models)
            : nil
        let planeTarget = realWorldPlaneTarget(at: center, in: arView, alignment: alignment)
        placementTarget = PlacementTargetPolicy.select(purpose: purpose,
                                                       objectCandidate: objectCandidate,
                                                       planeTarget: planeTarget)

        guard let placementTarget else { clearTarget(); return }
        indicator.transform.matrix = placementTarget.worldTransform
        indicator.isEnabled = true
    }

    /// Resolves a mesh hit to the one registered placed-object root, never to the child itself.
    static func registeredRoot(from hitEntity: Entity) -> (entity: Entity, component: LocalModelComponent)? {
        var current: Entity? = hitEntity
        while let entity = current {
            if let component = entity.components[LocalModelComponent.self] as? LocalModelComponent {
                return (entity, component)
            }
            current = entity.parent
        }
        return nil
    }

    private func placedObjectCandidate(at point: CGPoint, in arView: ARView, models: [Model]) -> PlacementTargetPolicy.ObjectCandidate? {
        guard let hit = arView.hitTest(point, query: .nearest).first,
              let resolved = Self.registeredRoot(from: hit.entity),
              resolved.entity.isEnabled,
              let model = models.first(where: { $0.id == resolved.component.catalogAssetID }) else { return nil }

        let position = hit.position
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(position, 1)
        return .init(position: position,
                     normal: hit.normal,
                     worldTransform: transform,
                     instanceID: resolved.component.instanceID,
                     category: model.category,
                     placementRole: model.placementRole)
    }

    private func realWorldPlaneTarget(at point: CGPoint, in arView: ARView, alignment: ARRaycastQuery.TargetAlignment) -> PlacementTarget? {
        guard let query = arView.makeRaycastQuery(from: point, allowing: .estimatedPlane, alignment: alignment),
              let result = arView.session.raycast(query).first else { return nil }
        let position = SIMD3<Float>(result.worldTransform.columns.3.x,
                                    result.worldTransform.columns.3.y,
                                    result.worldTransform.columns.3.z)
        let normal = SIMD3<Float>(result.worldTransform.columns.1.x,
                                  result.worldTransform.columns.1.y,
                                  result.worldTransform.columns.1.z)
        guard position.allFinite, normal.allFinite, simd_length(normal) > 0 else { return nil }
        return PlacementTarget(worldPosition: position,
                               worldTransform: result.worldTransform,
                               surfaceNormal: simd_normalize(normal),
                               source: .arPlane,
                               supportingObjectID: nil)
    }

    private func clearTarget() {
        placementTarget = nil
        indicator.isEnabled = false
    }
}

final class PlacementIndicatorEntity: Entity, HasModel {
    required init() {
        super.init()
        let mesh = MeshResource.generatePlane(width: 0.18, depth: 0.18)
        let material = SimpleMaterial(color: UIColor.systemTeal.withAlphaComponent(0.65), roughness: 0.35, isMetallic: false)
        self.model = ModelComponent(mesh: mesh, materials: [material])
        self.name = "native-placement-indicator"
    }
}

/// Ephemeral rendering only: these entities have no collisions and are never registered as world assets.
final class GridVisualController {
    private let grid = Entity()
    private let footprintMarker = ModelEntity()
    private let assetOutline = Entity()
    private let temporaryAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
    private var renderedSettings: GridSettings?
    private var renderedFootprintDimensions: SIMD2<Float>?
    private var renderedOutlineDimensions: SIMD2<Float>?

    init() {
        grid.name = "build-grid-overlay"
        footprintMarker.name = "temporary-grid-footprint-marker"
        assetOutline.name = "temporary-asset-size-outline"
        temporaryAnchor.name = "temporary-grid-preview-anchor"
    }

    func showGrid(settings: GridSettings, root: Entity?, candidateWorldTransform: simd_float4x4, in arView: ARView) {
        if renderedSettings != settings { rebuildGrid(settings: settings); renderedSettings = settings }
        if let root {
            if grid.parent !== root { grid.removeFromParent(); root.addChild(grid) }
            grid.transform = .identity
            temporaryAnchor.removeFromParent()
        } else {
            if temporaryAnchor.scene == nil { arView.scene.addAnchor(temporaryAnchor) }
            temporaryAnchor.transform.matrix = candidateWorldTransform
            if grid.parent !== temporaryAnchor { grid.removeFromParent(); temporaryAnchor.addChild(grid) }
            grid.transform = .identity
        }
        grid.isEnabled = true
    }

    func showPreview(result: GridSnapResult, settings: GridSettings, visualBounds: SIMD2<Float>?, showsFootprint: Bool,
                     root: Entity?, rootWorldTransform: simd_float4x4, in arView: ARView) {
        if showsFootprint, let dimensions = GuideGeometry.gridMarkerDimensions(footprint: result.effectiveFootprint, cellSizeMeters: settings.cellSizeMeters) {
            if renderedFootprintDimensions != dimensions {
                footprintMarker.model = ModelComponent(mesh: .generatePlane(width: dimensions.x, depth: dimensions.y), materials: [UnlitMaterial(color: UIColor.systemGreen.withAlphaComponent(0.24))])
                renderedFootprintDimensions = dimensions
            }
            footprintMarker.isEnabled = true
        } else { footprintMarker.isEnabled = false }
        rebuildAssetOutline(dimensions: visualBounds)
        let previewEntities = [footprintMarker, assetOutline]
        if let root {
            for entity in previewEntities where entity.parent !== root { entity.removeFromParent(); root.addChild(entity) }
        } else {
            if temporaryAnchor.scene == nil { arView.scene.addAnchor(temporaryAnchor) }
            temporaryAnchor.transform.matrix = rootWorldTransform
            for entity in previewEntities where entity.parent !== temporaryAnchor { entity.removeFromParent(); temporaryAnchor.addChild(entity) }
        }
        footprintMarker.transform = result.transform
        footprintMarker.scale = .one
        footprintMarker.position.y += 0.002
        assetOutline.transform = result.transform
        assetOutline.position.y += 0.004
    }

    func hideGrid() { grid.isEnabled = false; temporaryAnchor.removeFromParent() }
    func hidePreview() { footprintMarker.isEnabled = false; assetOutline.isEnabled = false }

    private func rebuildAssetOutline(dimensions: SIMD2<Float>?) {
        if renderedOutlineDimensions == dimensions { assetOutline.isEnabled = dimensions != nil; return }
        for child in assetOutline.children { child.removeFromParent() }
        guard let dimensions, GuideGeometry.validVisualDimensions(dimensions) else {
            renderedOutlineDimensions = nil; assetOutline.isEnabled = false; return
        }
        let thickness = max(min(dimensions.x, dimensions.y) * 0.012, 0.0012)
        let material = UnlitMaterial(color: UIColor.systemYellow.withAlphaComponent(0.82))
        let horizontal = MeshResource.generateBox(size: [dimensions.x, 0.0008, thickness])
        let vertical = MeshResource.generateBox(size: [thickness, 0.0008, dimensions.y])
        for z in [-dimensions.y / 2, dimensions.y / 2] {
            let edge = ModelEntity(mesh: horizontal, materials: [material]); edge.position.z = z; assetOutline.addChild(edge)
        }
        for x in [-dimensions.x / 2, dimensions.x / 2] {
            let edge = ModelEntity(mesh: vertical, materials: [material]); edge.position.x = x; assetOutline.addChild(edge)
        }
        renderedOutlineDimensions = dimensions
        assetOutline.isEnabled = true
    }

    private func rebuildGrid(settings: GridSettings) {
        for child in grid.children { child.removeFromParent() }
        let radius = settings.visibleRadiusInCells
        let extent = Float(radius * 2) * settings.cellSizeMeters
        let thickness = max(settings.cellSizeMeters * 0.012, 0.0008)
        for index in -radius...radius {
            let coordinate = Float(index) * settings.cellSizeMeters
            let color = index == 0 ? UIColor.systemTeal.withAlphaComponent(0.78) : UIColor.white.withAlphaComponent(0.34)
            let material = UnlitMaterial(color: color)
            let xLine = ModelEntity(mesh: .generateBox(size: [thickness, 0.0005, extent]), materials: [material])
            xLine.position.x = coordinate
            let zLine = ModelEntity(mesh: .generateBox(size: [extent, 0.0005, thickness]), materials: [material])
            zLine.position.z = coordinate
            grid.addChild(xLine); grid.addChild(zLine)
        }
    }
}
