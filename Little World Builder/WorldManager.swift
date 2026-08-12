import Foundation
import RealityKit

struct PlacedAssetRecord {
    let id: UUID
    let catalogAssetID: String
    let assetFileName: String
    let displayName: String
    let category: ModelCategory
    weak var entity: ModelEntity?
}

final class WorldManager: ObservableObject {
    @Published private(set) var pendingWorldForPlacement: SavedWorld?
    private(set) var activeAnchor: AnchorEntity?
    private(set) var buildRoot: Entity?
    private(set) var placedAssets: [UUID: PlacedAssetRecord] = [:]
    private let store = SavedWorldStore.shared

    func activate(anchor: AnchorEntity, buildRoot: Entity) { resetActiveWorld(); self.activeAnchor = anchor; self.buildRoot = buildRoot }
    func register(_ entity: ModelEntity, model: Model, instanceID: UUID = UUID(), displayName: String? = nil, category: ModelCategory? = nil) {
        placedAssets[instanceID] = PlacedAssetRecord(id: instanceID, catalogAssetID: model.id, assetFileName: model.assetFileName, displayName: displayName ?? model.name, category: category ?? model.category, entity: entity)
        entity.components.set(LocalModelComponent(instanceID: instanceID, catalogAssetID: model.id, assetFileName: model.assetFileName))
    }
    func remove(entity: Entity) { if let item = placedAssets.first(where: { $0.value.entity === entity }) { placedAssets.removeValue(forKey: item.key) }; entity.removeFromParent() }
    func resetActiveWorld() { activeAnchor?.removeFromParent(); activeAnchor=nil; buildRoot=nil; placedAssets.removeAll() }
    func savedWorlds() -> [SavedWorld] { store.loadAll() }
    func save(_ world: SavedWorld) { store.save(world) }
    func delete(_ world: SavedWorld) { store.delete(world) }
    func loadWorld(_ world: SavedWorld) { pendingWorldForPlacement = world }
    func finishPendingWorldPlacement() { pendingWorldForPlacement = nil }
    func cancelPendingWorldPlacement() { pendingWorldForPlacement = nil }
}

final class SavedWorldStore {
    static let shared = SavedWorldStore(); private init() {}
    var savedWorldsDirectory: URL { let base=(try? FileManager.default.url(for:.documentDirectory,in:.userDomainMask,appropriateFor:nil,create:true)) ?? .temporaryDirectory; let url=base.appendingPathComponent("SavedWorlds",isDirectory:true); try? FileManager.default.createDirectory(at:url,withIntermediateDirectories:true); return url }
    func url(for world: SavedWorld)->URL { savedWorldsDirectory.appendingPathComponent("\(world.id.uuidString).json") }
    func save(_ world: SavedWorld) { do { let e=JSONEncoder(); e.outputFormatting=[.prettyPrinted,.sortedKeys]; try e.encode(world).write(to:url(for:world),options:.atomic) } catch { print("World Persistence Error: \(error.localizedDescription)") } }
    func loadAll()->[SavedWorld] { ((try? FileManager.default.contentsOfDirectory(at:savedWorldsDirectory,includingPropertiesForKeys:nil)) ?? []).filter{$0.pathExtension=="json"}.compactMap { url in do { return try JSONDecoder().decode(SavedWorld.self,from:Data(contentsOf:url)) } catch { print("World Compatibility Error [\(url.lastPathComponent)]: \(error.localizedDescription)"); return nil } }.sorted{$0.updatedAt>$1.updatedAt} }
    func delete(_ world: SavedWorld) { try? FileManager.default.removeItem(at:url(for:world)); if let t=world.thumbnailFileName { try? FileManager.default.removeItem(at:savedWorldsDirectory.appendingPathComponent(t)) } }
}
