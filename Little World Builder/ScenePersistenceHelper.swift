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
#if DEBUG
            let position = transform.position
            let scale = transform.scale
            print("SAVE \(record.catalogAssetID) \(record.id)\nlocal position: x=\(position.x), y=\(position.y), z=\(position.z)\nscale: x=\(scale.x), y=\(scale.y), z=\(scale.z)")
#endif
            return SavedPlacedAsset(id:record.id,catalogAssetID:record.catalogAssetID,assetFileName:record.assetFileName,displayName:record.displayName,category:record.category,localTransform:transform)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        return SavedWorld(id:UUID(),name:"Saved World",createdAt:now,updatedAt:now,placedAssets:assets,thumbnailFileName:nil,gridConfiguration:worldManager.gridConfiguration)
    }
    static func saveWorld(using worldManager: WorldManager) { if let world=makeWorld(from:worldManager) { worldManager.save(world) } }
}
