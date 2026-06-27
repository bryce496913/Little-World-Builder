import Foundation
import RealityKit

struct LocalModelComponent: Component {
    let modelIdentifier: String
    let assetFileName: String
    let displayName: String?
    let category: String?
}

final class ScenePersistenceHelper {
    static func saveWorld(from sceneManager: SceneManager, using worldManager: WorldManager) {
        let placedAssets = sceneManager.anchorEntities.flatMap { anchorEntity -> [SavedPlacedAsset] in
            anchorEntity.children.compactMap { child in
                guard let metadata = child.components[LocalModelComponent.self] else {
                    print("World Persistence Warning: Skipping entity without local asset metadata.")
                    return nil
                }
                let transform = child.transform
                return SavedPlacedAsset(
                    id: UUID(),
                    assetFileName: metadata.assetFileName,
                    displayName: metadata.displayName ?? child.name,
                    category: ModelCategory(rawValue: metadata.category ?? "") ?? .misc,
                    position: CodableVector3(transform.translation),
                    rotation: CodableQuaternion(transform.rotation),
                    scale: CodableVector3(transform.scale)
                )
            }
        }

        guard !placedAssets.isEmpty else {
            print("World Persistence Warning: No placed assets to save.")
            return
        }

        let now = Date()
        let world = SavedWorld(
            id: UUID(),
            name: "Saved World",
            createdAt: now,
            updatedAt: now,
            placedAssets: placedAssets,
            thumbnailFileName: nil
        )
        worldManager.save(world)
    }
}
