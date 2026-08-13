import ARKit
import RealityKit
import UIKit

final class NativePlacementManager {
    private let indicator = PlacementIndicatorEntity()
    private(set) var latestPlacementTransform: simd_float4x4?

    var isPlacementAvailable: Bool {
        latestPlacementTransform != nil
    }

    func install(in arView: ARView) {
        let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
        anchor.name = "native-placement-indicator-anchor"
        anchor.addChild(indicator)
        arView.scene.addAnchor(anchor)
        indicator.isEnabled = false
    }

    func update(in arView: ARView, isPlacementActive: Bool) {
        guard isPlacementActive else {
            latestPlacementTransform = nil
            indicator.isEnabled = false
            return
        }

        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let query = arView.makeRaycastQuery(from: center, allowing: .estimatedPlane, alignment: .any),
              let result = arView.session.raycast(query).first else {
            latestPlacementTransform = nil
            indicator.isEnabled = false
            return
        }

        latestPlacementTransform = result.worldTransform
        indicator.transform.matrix = result.worldTransform
        indicator.isEnabled = true
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
    private let preview = ModelEntity()
    private let temporaryAnchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
    private var renderedSettings: GridSettings?

    init() {
        grid.name = "build-grid-overlay"
        preview.name = "grid-footprint-preview"
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

    func showPreview(result: GridSnapResult, settings: GridSettings, root: Entity?, rootWorldTransform: simd_float4x4, in arView: ARView) {
        let width = Float(result.effectiveFootprint.width) * settings.cellSizeMeters
        let depth = Float(result.effectiveFootprint.depth) * settings.cellSizeMeters
        preview.model = ModelComponent(mesh: .generatePlane(width: width, depth: depth), materials: [UnlitMaterial(color: UIColor.systemGreen.withAlphaComponent(0.32))])
        if let root {
            if preview.parent !== root { preview.removeFromParent(); root.addChild(preview) }
            preview.transform = result.transform
            preview.position.y += 0.002
        } else {
            if temporaryAnchor.scene == nil { arView.scene.addAnchor(temporaryAnchor) }
            temporaryAnchor.transform.matrix = rootWorldTransform
            if preview.parent !== temporaryAnchor { preview.removeFromParent(); temporaryAnchor.addChild(preview) }
            preview.transform = result.transform
            preview.position.y += 0.002
        }
        preview.isEnabled = true
    }

    func hideGrid() { grid.isEnabled = false; temporaryAnchor.removeFromParent() }
    func hidePreview() { preview.isEnabled = false }

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
