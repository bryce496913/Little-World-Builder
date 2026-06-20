import Foundation
import RealityKit
import UIKit

final class IslandManager: ObservableObject {
    @Published private(set) var activeIsland: SavedIsland?
    @Published private(set) var isIslandRootPlaced = false

    private(set) var islandRootEntity: Entity?
    private(set) var islandAnchorEntity: AnchorEntity?
    private let store = SavedIslandStore.shared

    func createNewIsland(using modelsViewModel: ModelsViewModel) -> Bool {
        guard let baseModel = modelsViewModel.defaultBaseIslandModel() else {
            print("Island Error: No bundled base island USDZ was found in App Ready USDZ.")
            return false
        }

        activeIsland = SavedIsland(
            id: UUID(),
            name: "Little Island",
            createdAt: Date(),
            updatedAt: Date(),
            baseIslandAssetFileName: baseModel.assetFileName,
            waterType: .none,
            placedAssets: [],
            animationMetadata: .empty,
            scale: .one,
            thumbnailFileName: nil
        )
        islandRootEntity = makeEmptyIslandRoot(scale: .one)
        isIslandRootPlaced = false
        return true
    }

    func rebuildActiveIslandRoot(using modelsViewModel: ModelsViewModel, completion: @escaping (Bool) -> Void) {
        guard let island = activeIsland else { completion(false); return }
        guard modelsViewModel.model(matching: island.baseIslandAssetFileName) != nil else {
            print("Island Error: Missing base island asset \(island.baseIslandAssetFileName). Placement cancelled.")
            completion(false)
            return
        }

        let root = makeEmptyIslandRoot(scale: island.scale)
        islandRootEntity = root
        let group = DispatchGroup()
        var canPlace = true

        func attach(_ model: Model, transform: Transform?, isBase: Bool) {
            group.enter()
            loadEntity(for: model) { entity in
                defer { group.leave() }
                guard let entity else {
                    if isBase { canPlace = false }
                    return
                }
                let clone = entity.clone(recursive: true)
                clone.name = isBase ? "base-island" : model.id
                clone.components.set(LocalModelComponent(modelIdentifier: model.id, assetFileName: model.assetFileName, displayName: model.name, category: model.category.rawValue))
                if let transform { clone.transform = transform }
                clone.generateCollisionShapes(recursive: true)
                root.addChild(clone)
            }
        }

        if let base = modelsViewModel.model(matching: island.baseIslandAssetFileName) {
            attach(base, transform: nil, isBase: true)
        }

        for savedAsset in island.placedAssets {
            guard let model = modelsViewModel.model(matching: savedAsset.assetFileName) else {
                print("Island Warning: Missing child asset \(savedAsset.assetFileName). Skipping.")
                continue
            }
            let transform = CodableTransform(position: savedAsset.relativePosition, rotation: savedAsset.relativeRotation, scale: savedAsset.relativeScale).realityKitTransform
            attach(model, transform: transform, isBase: false)
        }

        group.notify(queue: .main) { completion(canPlace) }
    }

    func placeIslandRoot(on anchor: AnchorEntity, in arView: ARView) {
        guard let root = islandRootEntity else { return }
        islandAnchorEntity?.removeFromParent()
        islandAnchorEntity = anchor
        anchor.name = "island-root-anchor"
        anchor.addChild(root)
        arView.scene.addAnchor(anchor)
        for child in root.children where child.name != "base-island" {
            if let modelEntity = child as? ModelEntity {
                arView.installGestures([.translation, .rotation, .scale], for: modelEntity)
            }
        }
        isIslandRootPlaced = true
        print("Island: placed root as one portable AR object.")
    }

    func addChildAsset(_ model: Model, modelEntity: ModelEntity, worldTransform: simd_float4x4, in arView: ARView) {
        guard let root = islandRootEntity, var island = activeIsland else { return }
        let clone = modelEntity.clone(recursive: true)
        clone.name = model.id
        clone.components.set(LocalModelComponent(modelIdentifier: model.id, assetFileName: model.assetFileName, displayName: model.name, category: model.category.rawValue))
        clone.transform = root.convert(transform: Transform(matrix: worldTransform), from: nil)
        clone.generateCollisionShapes(recursive: true)
        arView.installGestures([.translation, .rotation, .scale], for: clone)
        root.addChild(clone)

        island.placedAssets.append(SavedIslandAsset(id: UUID(), assetFileName: model.assetFileName, displayName: model.name, category: model.category, relativePosition: CodableVector3(clone.transform.translation), relativeRotation: CodableQuaternion(clone.transform.rotation), relativeScale: CodableVector3(clone.transform.scale), animationState: nil))
        island.updatedAt = Date()
        activeIsland = island
    }

    func refreshActiveIslandFromRoot() {
        guard var island = activeIsland, let root = islandRootEntity else { return }
        island.scale = CodableVector3(root.transform.scale)
        island.placedAssets = root.children.compactMap { child in
            guard child.name != "base-island", let metadata = child.components[LocalModelComponent.self] else { return nil }
            return SavedIslandAsset(id: UUID(), assetFileName: metadata.assetFileName, displayName: metadata.displayName ?? child.name, category: ModelCategory(rawValue: metadata.category ?? "") ?? .misc, relativePosition: CodableVector3(child.transform.translation), relativeRotation: CodableQuaternion(child.transform.rotation), relativeScale: CodableVector3(child.transform.scale), animationState: nil)
        }
        island.updatedAt = Date()
        activeIsland = island
    }

    func saveActiveIsland() { refreshActiveIslandFromRoot(); if let activeIsland { store.save(activeIsland) } }
    func loadIsland(_ island: SavedIsland) { activeIsland = island; islandRootEntity = nil; islandAnchorEntity = nil; isIslandRootPlaced = false }
    func savedIslands() -> [SavedIsland] { store.loadAll() }
    func delete(_ island: SavedIsland) { store.delete(island) }
    func clearActiveIsland() { activeIsland = nil; islandRootEntity = nil; islandAnchorEntity?.removeFromParent(); islandAnchorEntity = nil; isIslandRootPlaced = false }

    private func makeEmptyIslandRoot(scale: CodableVector3) -> Entity {
        let root = Entity()
        root.name = "island-root"
        root.transform.scale = scale.simd
        return root
    }

    private func loadEntity(for model: Model, completion: @escaping (ModelEntity?) -> Void) {
        if let entity = model.modelEntity { completion(entity); return }
        model.asyncLoadModelEntity { completed, error in
            if let error { print("Island Error: Unable to load \(model.assetFileName): \(error.localizedDescription)") }
            completion(completed ? model.modelEntity : nil)
        }
    }
}

final class SavedIslandStore {
    static let shared = SavedIslandStore()
    private init() {}

    var savedIslandsDirectory: URL {
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = documents.appendingPathComponent("SavedIslands", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            print("Island Persistence Error: \(error.localizedDescription)")
            return FileManager.default.temporaryDirectory.appendingPathComponent("SavedIslands", isDirectory: true)
        }
    }

    func url(for island: SavedIsland) -> URL { savedIslandsDirectory.appendingPathComponent("\(island.id.uuidString).json") }
    func save(_ island: SavedIsland) { do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(island).write(to: url(for: island), options: .atomic); print("Island: saved JSON to \(url(for: island).path)") } catch { print("Island Persistence Error: \(error.localizedDescription)") } }
    func loadAll() -> [SavedIsland] { (try? FileManager.default.contentsOfDirectory(at: savedIslandsDirectory, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "json" }.compactMap { try? JSONDecoder().decode(SavedIsland.self, from: Data(contentsOf: $0)) }.sorted { $0.updatedAt > $1.updatedAt } ?? [] }
    func delete(_ island: SavedIsland) { try? FileManager.default.removeItem(at: url(for: island)); if let thumbnail = island.thumbnailFileName { try? FileManager.default.removeItem(at: savedIslandsDirectory.appendingPathComponent(thumbnail)) } }
}
