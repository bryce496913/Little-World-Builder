//
//  ScenePersistenceHelper.swift
//  Little World Builder
//
//  Created by Bryce on 17/02/22.
//

import Foundation
import RealityKit
import ARKit

struct PersistedModelPlacement: Codable {
    let modelIdentifier: String
    let modelFileName: String
    let displayName: String?
    let category: String?
    let anchorTransform: [Float]
    let modelTransform: [Float]
    let position: [Float]
    let scale: [Float]
    let rotation: [Float]
}

struct PersistedScene: Codable {
    let version: Int
    let savedAt: Date
    let placements: [PersistedModelPlacement]
}

final class ScenePersistenceHelper {
    static func saveScene(for arView: CustomARView, sceneManager: SceneManager, at persistenceUrl: URL) {
        print("Save scene metadata to local filesystem.")
        
        let placements = sceneManager.anchorEntities.compactMap { anchorEntity -> PersistedModelPlacement? in
            guard let modelEntity = anchorEntity.children.compactMap({ $0 as? ModelEntity }).first else {
                print("Persistence Warning: Skipping anchor without a model entity.")
                return nil
            }
            
            let identifier = modelEntity.name
            guard !identifier.isEmpty else {
                print("Persistence Warning: Skipping model entity without a local model identifier.")
                return nil
            }
            
            let metadata = modelEntity.components[LocalModelComponent.self]
            let fileName = metadata?.assetFileName ?? "\(identifier).usdz"
            return PersistedModelPlacement(
                modelIdentifier: metadata?.modelIdentifier ?? identifier,
                modelFileName: fileName,
                displayName: metadata?.displayName ?? identifier,
                category: metadata?.category ?? ModelCategory.misc.rawValue,
                anchorTransform: anchorEntity.transformMatrix(relativeTo: nil).flatArray,
                modelTransform: modelEntity.transform.matrix.flatArray,
                position: modelEntity.transform.translation.array,
                scale: modelEntity.transform.scale.array,
                rotation: modelEntity.transform.rotation.vector.array
            )
        }
        
        let scene = PersistedScene(version: 1, savedAt: Date(), placements: placements)
        
        do {
            let sceneData = try JSONEncoder().encode(scene)
            try sceneData.write(to: persistenceUrl, options: [.atomic])
            print("Persistence: Scene metadata saved to \(persistenceUrl.path) with \(placements.count) placement(s).")
        } catch {
            print("Persistence Error: Can't save scene metadata to local filesystem: \(error.localizedDescription)")
        }
    }
    
    static func loadScene(from scenePersistenceData: Data, modelsViewModel: ModelsViewModel, placementSettings: PlacementSettings) {
        print("Load scene metadata from local filesystem.")
        
        do {
            let persistedScene = try JSONDecoder().decode(PersistedScene.self, from: scenePersistenceData)
            for placement in persistedScene.placements {
                guard let model = modelsViewModel.model(matching: placement.modelIdentifier) ?? modelsViewModel.model(matching: placement.modelFileName) else {
                    print("Persistence Warning: Missing bundled model for saved placement \(placement.modelIdentifier) / \(placement.modelFileName). Skipping placement.")
                    continue
                }
                
                guard let anchorMatrix = simd_float4x4(flatArray: placement.anchorTransform),
                      let modelMatrix = simd_float4x4(flatArray: placement.modelTransform) else {
                    print("Persistence Warning: Invalid transform data for saved placement \(placement.modelIdentifier). Skipping placement.")
                    continue
                }
                
                let anchor = ARAnchor(name: anchorNamePrefix + model.id, transform: anchorMatrix)
                let modelAnchor = ModelAnchor(model: model, anchor: anchor, modelTransform: Transform(matrix: modelMatrix))
                
                if model.modelEntity == nil {
                    model.asyncLoadModelEntity { completed, error in
                        if completed {
                            placementSettings.modelConfirmedForPlacement.append(modelAnchor)
                        } else if let error = error {
                            print("Persistence Error: Unable to load model \(model.name): \(error.localizedDescription)")
                        }
                    }
                } else {
                    placementSettings.modelConfirmedForPlacement.append(modelAnchor)
                }
            }
        } catch {
            print("Persistence Error: Unable to decode persisted scene metadata: \(error.localizedDescription)")
        }
    }
}

struct LocalModelComponent: Component {
    let modelIdentifier: String
    let assetFileName: String
    let displayName: String?
    let category: String?
}

private extension SIMD3 where Scalar == Float {
    var array: [Float] { [x, y, z] }
}

private extension SIMD4 where Scalar == Float {
    var array: [Float] { [x, y, z, w] }
}

private extension simd_float4x4 {
    var flatArray: [Float] {
        [columns.0.x, columns.0.y, columns.0.z, columns.0.w,
         columns.1.x, columns.1.y, columns.1.z, columns.1.w,
         columns.2.x, columns.2.y, columns.2.z, columns.2.w,
         columns.3.x, columns.3.y, columns.3.z, columns.3.w]
    }
    
    init?(flatArray: [Float]) {
        guard flatArray.count == 16 else { return nil }
        self.init(
            SIMD4<Float>(flatArray[0], flatArray[1], flatArray[2], flatArray[3]),
            SIMD4<Float>(flatArray[4], flatArray[5], flatArray[6], flatArray[7]),
            SIMD4<Float>(flatArray[8], flatArray[9], flatArray[10], flatArray[11]),
            SIMD4<Float>(flatArray[12], flatArray[13], flatArray[14], flatArray[15])
        )
    }
}
