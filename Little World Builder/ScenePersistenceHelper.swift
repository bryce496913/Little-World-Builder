import Foundation
import RealityKit

struct LocalModelComponent: Component { let instanceID: UUID; let catalogAssetID: String; let assetFileName: String }

final class ScenePersistenceHelper {
    static func makeWorld(from worldManager: WorldManager, now: Date = Date()) -> SavedWorld? {
        guard worldManager.buildRoot != nil else { print("World Persistence Warning: no active build root."); return nil }
        let assets = worldManager.placedAssets.values.compactMap { record -> SavedPlacedAsset? in
            guard let entity = record.entity else { print("World Persistence Warning: missing entity for \(record.id)"); return nil }
            let transform = CodableTransform(entity.transform)
            guard transform.isFinite else { print("World Persistence Warning: non-finite transform for \(record.id)"); return nil }
            return SavedPlacedAsset(id:record.id,catalogAssetID:record.catalogAssetID,assetFileName:record.assetFileName,displayName:record.displayName,category:record.category,localTransform:transform)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        return SavedWorld(id:UUID(),name:"Saved World",createdAt:now,updatedAt:now,placedAssets:assets,thumbnailFileName:nil)
    }
    static func saveWorld(using worldManager: WorldManager) { if let world=makeWorld(from:worldManager) { worldManager.save(world) } }
}
