//
//  ScenePersistenceHelper.swift
//  Little World Builder
//
//  Created by Bryce on 17/02/22.
//

import Foundation
import RealityKit
import ARKit

struct PersistedPlacedModel: Codable, Identifiable {
    let id: UUID
    let modelIdentifier: String
    let modelAssetFileName: String
    let displayName: String?
    let category: String?
    let anchorTransform: [Float]
    let modelTransform: [Float]
    let position: [Float]
    let scale: [Float]
    let rotation: [Float]

    var modelFileName: String { modelAssetFileName }
}

typealias PersistedModelPlacement = PersistedPlacedModel

struct PersistedScene: Codable, Identifiable {
    let id: UUID
    let version: Int
    let title: String
    let savedAt: Date
    let placements: [PersistedPlacedModel]

    var name: String { title }
    var placedModelCount: Int { placements.count }
}

final class LocalSavedWorldStore {
    static let shared = LocalSavedWorldStore()

    private init() {}

    func defaultSceneURL() -> URL {
        do {
            return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("SavedScene.json")
        } catch {
            let fallbackUrl = FileManager.default.temporaryDirectory.appendingPathComponent("SavedScene.json")
            print("Persistence Error: Unable to get documents directory: \(error.localizedDescription). Falling back to \(fallbackUrl.path).")
            return fallbackUrl
        }
    }

    func loadScene(at url: URL) -> PersistedScene? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PersistedScene.self, from: data)
        } catch {
            print("Persistence Error: Unable to load saved world at \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    func deleteScene(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            print("Persistence: Deleted saved scene at \(url.path).")
        } catch {
            print("Persistence Error: Unable to delete saved scene: \(error.localizedDescription)")
        }
    }
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
            return PersistedPlacedModel(
                id: UUID(),
                modelIdentifier: metadata?.modelIdentifier ?? identifier,
                modelAssetFileName: fileName,
                displayName: metadata?.displayName ?? identifier,
                category: metadata?.category ?? ModelCategory.misc.rawValue,
                anchorTransform: anchorEntity.transformMatrix(relativeTo: nil).flatArray,
                modelTransform: modelEntity.transform.matrix.flatArray,
                position: modelEntity.transform.translation.array,
                scale: modelEntity.transform.scale.array,
                rotation: modelEntity.transform.rotation.vector.array
            )
        }
        
        let scene = PersistedScene(id: UUID(), version: 1, title: "Saved World", savedAt: Date(), placements: placements)
        
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
                guard let model = modelsViewModel.model(matching: placement.modelIdentifier) ?? modelsViewModel.model(matching: placement.modelAssetFileName) else {
                    print("Persistence Warning: Missing bundled model for saved placement \(placement.modelIdentifier) / \(placement.modelAssetFileName). Skipping placement.")
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
