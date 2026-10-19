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

struct PlacedObjectSelection: Equatable {
    let instanceID: UUID
    let catalogAssetID: String
}

enum BuilderInteractionState: Equatable {
    case browse
    case placingAsset(catalogAssetID: String)
    case editing(PlacedObjectSelection)
    case placingSavedWorld(worldID: UUID)

    var selection: PlacedObjectSelection? {
        guard case .editing(let selection) = self else { return nil }
        return selection
    }
}

final class WorldManager: ObservableObject {
    @Published private(set) var pendingWorldForPlacement: SavedWorld?
    private(set) var activeAnchor: AnchorEntity?
    private(set) var buildRoot: Entity?
    private(set) var placedAssets: [UUID: PlacedAssetRecord] = [:]
    private var pendingWorldRestoreID: UUID?
    private let store = SavedWorldStore.shared
    @Published private(set) var gridConfiguration: SavedGridConfiguration?
    @Published private(set) var interactionState: BuilderInteractionState = .browse
    private(set) var heightEditSession: HeightEditSession?
    @Published private(set) var heightAdjustmentState: HeightAdjustmentState = .inactive

    func activate(anchor: AnchorEntity, buildRoot: Entity) { resetActiveWorld(); self.activeAnchor = anchor; self.buildRoot = buildRoot }
    func register(_ entity: ModelEntity, model: Model, instanceID: UUID = UUID(), displayName: String? = nil, category: ModelCategory? = nil) {
        placedAssets[instanceID] = PlacedAssetRecord(id: instanceID, catalogAssetID: model.id, assetFileName: model.assetFileName, displayName: displayName ?? model.name, category: category ?? model.category, entity: entity)
        entity.components.set(LocalModelComponent(instanceID: instanceID, catalogAssetID: model.id, assetFileName: model.assetFileName))
    }
    func record(for instanceID: UUID) -> PlacedAssetRecord? {
        guard let record = placedAssets[instanceID], record.entity?.parent != nil else { return nil }
        return record
    }
    func entity(for instanceID: UUID) -> ModelEntity? { record(for: instanceID)?.entity }

    func isPlacementSupportValid(source: PlacementTargetSource, instanceID: UUID?) -> Bool {
        if source == .arPlane { return instanceID == nil }
        guard let instanceID, let entity = entity(for: instanceID), let buildRoot else { return false }
        return entity.parent === buildRoot && entity.isEnabled
            && (entity.components[PlacementSupportCollision.self] as? PlacementSupportCollision)?.isReady == true
    }

    @discardableResult
    func select(instanceID: UUID) -> Bool {
        guard let record = record(for: instanceID), belongsToActiveBuildRoot(record.entity) else {
            clearSelection(); return false
        }
        if interactionState.selection?.instanceID != instanceID || heightEditSession == nil {
            heightEditSession = nil
            if let entity = directSelectedRoot(id: instanceID), VerticalAdjustment.isFinite(entity.transform) {
                heightEditSession = HeightEditSession(selectedObjectID: instanceID, startingLocalY: entity.position.y)
            }
        }
        heightAdjustmentState = heightState(for: instanceID)
        interactionState = .editing(.init(instanceID: instanceID, catalogAssetID: record.catalogAssetID))
        return true
    }

    func beginPlacingAsset(catalogAssetID: String) {
        endHeightSession()
        let next = BuilderInteractionState.placingAsset(catalogAssetID: catalogAssetID)
        if interactionState != next { interactionState = next }
    }
    func beginPlacingSavedWorld(id: UUID) {
        endHeightSession()
        let next = BuilderInteractionState.placingSavedWorld(worldID: id)
        if interactionState != next { interactionState = next }
    }
    func finishPlacement() { endHeightSession(); if interactionState != .browse { interactionState = .browse } }
    func clearSelection() {
        endHeightSession()
        if interactionState.selection != nil { interactionState = .browse }
    }

    @discardableResult
    func adjustSelectedHeight(_ direction: VerticalAdjustmentDirection) -> Bool {
        guard let (id, entity) = selectedHeightRoot(),
              let adjusted = VerticalAdjustment.applying(direction, to: entity.transform),
              adjusted.translation.y != entity.position.y else { return false }
        heightEditSession?.record(y: entity.position.y)
        entity.transform = adjusted
        heightAdjustmentState = heightState(for: id)
        return true
    }

    @discardableResult
    func undoSelectedHeightAdjustment() -> Bool {
        guard let (id, entity) = selectedHeightRoot(),
              let previousY = heightEditSession?.undoStack.last,
              let restored = VerticalAdjustment.restoring(y: previousY, in: entity.transform) else { return false }
        _ = heightEditSession?.undo()
        entity.transform = restored
        heightAdjustmentState = heightState(for: id)
        return true
    }

    @discardableResult
    func resetSelectedHeight() -> Bool {
        guard let (id, entity) = selectedHeightRoot(),
              let baseline = heightEditSession?.startingLocalY,
              let restored = VerticalAdjustment.restoring(y: baseline, in: entity.transform) else { return false }
        // Even a mixed sequence ending at the baseline must discard its history on Reset.
        heightEditSession?.clearHistory()
        entity.transform = restored
        heightAdjustmentState = heightState(for: id)
        return true
    }

    @discardableResult
    func removeSelected() -> Bool {
        guard let id = interactionState.selection?.instanceID else { return false }
        let entity = placedAssets.removeValue(forKey: id)?.entity
        entity?.removeFromParent()
        interactionState = .browse
        endHeightSession()
        return entity != nil
    }

    func remove(entity: Entity) {
        if let item = placedAssets.first(where: { $0.value.entity === entity }) {
            placedAssets.removeValue(forKey: item.key)
            if interactionState.selection?.instanceID == item.key { interactionState = .browse; endHeightSession() }
        }
        entity.removeFromParent()
    }
    func resetActiveWorld() { pendingWorldRestoreID = nil; activeAnchor?.removeFromParent(); activeAnchor=nil; buildRoot=nil; placedAssets.removeAll(); interactionState = .browse; endHeightSession(); setGridConfiguration(nil) }

    func belongsToActiveBuildRoot(_ entity: Entity?) -> Bool {
        guard let buildRoot, var current = entity else { return false }
        while let parent = current.parent {
            if parent === buildRoot { return true }
            current = parent
        }
        return false
    }
    private func directSelectedRoot(id: UUID) -> ModelEntity? {
        guard let buildRoot, let entity = entity(for: id), entity.parent === buildRoot else { return nil }
        return entity
    }
    private func endHeightSession() {
        heightEditSession = nil
        heightAdjustmentState = .inactive
    }
    private func heightState(for id: UUID) -> HeightAdjustmentState {
        guard let entity = directSelectedRoot(id: id), VerticalAdjustment.isFinite(entity.transform),
              let session = heightEditSession, session.selectedObjectID == id else {
            return HeightAdjustmentState(selectedInstanceID: id, currentY: nil, previousY: nil)
        }
        return HeightAdjustmentState(selectedInstanceID: id, currentY: entity.position.y,
                                     previousY: session.undoStack.last, startingLocalY: session.startingLocalY)
    }
    /// Scene updates retire stale selection/history even when no height button is pressed.
    func validateHeightEditSession() {
        guard let id = interactionState.selection?.instanceID else { return }
        guard let entity = directSelectedRoot(id: id) else { clearSelection(); return }
        if heightEditSession != nil && !VerticalAdjustment.isFinite(entity.transform) { endHeightSession() }
    }
    private func selectedHeightRoot() -> (UUID, ModelEntity)? {
        guard let id = interactionState.selection?.instanceID, let entity = directSelectedRoot(id: id) else {
            clearSelection()
            return nil
        }
        guard VerticalAdjustment.isFinite(entity.transform), heightEditSession?.selectedObjectID == id else {
            endHeightSession()
            return nil
        }
        return (id, entity)
    }
    func setGridConfiguration(_ configuration: SavedGridConfiguration?) {
        guard gridConfiguration != configuration else { return }
        gridConfiguration = configuration
    }
    func savedWorlds() -> [SavedWorld] { store.loadAll() }
    func save(_ world: SavedWorld) { store.save(world) }
    func delete(_ world: SavedWorld) { store.delete(world) }
    func beginPendingWorldRestore(worldID: UUID) -> UUID? {
        guard pendingWorldForPlacement?.id == worldID, pendingWorldRestoreID == nil else { return nil }
        let id = UUID()
        pendingWorldRestoreID = id
        return id
    }
    func isPendingWorldRestoreCurrent(_ id: UUID, worldID: UUID) -> Bool {
        pendingWorldRestoreID == id && pendingWorldForPlacement?.id == worldID
    }
    func loadWorld(_ world: SavedWorld) { pendingWorldRestoreID = nil; pendingWorldForPlacement = world; beginPlacingSavedWorld(id: world.id) }
    func finishPendingWorldPlacement() { pendingWorldRestoreID = nil; pendingWorldForPlacement = nil; finishPlacement() }
    func cancelPendingWorldPlacement() { pendingWorldRestoreID = nil; pendingWorldForPlacement = nil; finishPlacement() }
}

final class SavedWorldStore {
    static let shared = SavedWorldStore(); private init() {}
    var savedWorldsDirectory: URL { let base=(try? FileManager.default.url(for:.documentDirectory,in:.userDomainMask,appropriateFor:nil,create:true)) ?? .temporaryDirectory; let url=base.appendingPathComponent("SavedWorlds",isDirectory:true); try? FileManager.default.createDirectory(at:url,withIntermediateDirectories:true); return url }
    func url(for world: SavedWorld)->URL { savedWorldsDirectory.appendingPathComponent("\(world.id.uuidString).json") }
    func save(_ world: SavedWorld) { do { let e=JSONEncoder(); e.outputFormatting=[.prettyPrinted,.sortedKeys]; try e.encode(world).write(to:url(for:world),options:.atomic) } catch { print("World Persistence Error: \(error.localizedDescription)") } }
    func loadAll()->[SavedWorld] { ((try? FileManager.default.contentsOfDirectory(at:savedWorldsDirectory,includingPropertiesForKeys:nil)) ?? []).filter{$0.pathExtension=="json"}.compactMap { url in do { return try JSONDecoder().decode(SavedWorld.self,from:Data(contentsOf:url)) } catch { print("World Compatibility Error [\(url.lastPathComponent)]: \(error.localizedDescription)"); return nil } }.sorted{$0.updatedAt>$1.updatedAt} }
    func delete(_ world: SavedWorld) { try? FileManager.default.removeItem(at:url(for:world)); if let t=world.thumbnailFileName { try? FileManager.default.removeItem(at:savedWorldsDirectory.appendingPathComponent(t)) } }
}
