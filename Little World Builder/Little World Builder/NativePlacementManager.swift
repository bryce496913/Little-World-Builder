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
        let anchor = AnchorEntity(world: .init(translation: [0, 0, 0]))
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

    func makeAnchorEntity() -> AnchorEntity? {
        guard let latestPlacementTransform else { return nil }
        return AnchorEntity(world: latestPlacementTransform)
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
