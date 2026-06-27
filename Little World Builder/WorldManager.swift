import Foundation
import RealityKit

final class WorldManager: ObservableObject {
    @Published private(set) var pendingWorldForPlacement: SavedWorld?

    private let store = SavedWorldStore.shared

    func savedWorlds() -> [SavedWorld] { store.loadAll() }
    func save(_ world: SavedWorld) { store.save(world) }
    func delete(_ world: SavedWorld) { store.delete(world) }
    func loadWorld(_ world: SavedWorld) { pendingWorldForPlacement = world }
    func finishPendingWorldPlacement() { pendingWorldForPlacement = nil }
    func cancelPendingWorldPlacement() { pendingWorldForPlacement = nil }
}

final class SavedWorldStore {
    static let shared = SavedWorldStore()
    private init() {}

    var savedWorldsDirectory: URL {
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = documents.appendingPathComponent("SavedWorlds", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            print("World Persistence Error: \(error.localizedDescription)")
            return FileManager.default.temporaryDirectory.appendingPathComponent("SavedWorlds", isDirectory: true)
        }
    }

    func url(for world: SavedWorld) -> URL { savedWorldsDirectory.appendingPathComponent("\(world.id.uuidString).json") }

    func save(_ world: SavedWorld) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(world).write(to: url(for: world), options: .atomic)
            print("World: saved JSON to \(url(for: world).path)")
        } catch {
            print("World Persistence Error: \(error.localizedDescription)")
        }
    }

    func loadAll() -> [SavedWorld] {
        (try? FileManager.default.contentsOfDirectory(at: savedWorldsDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(SavedWorld.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt } ?? []
    }

    func delete(_ world: SavedWorld) {
        try? FileManager.default.removeItem(at: url(for: world))
        if let thumbnail = world.thumbnailFileName { try? FileManager.default.removeItem(at: savedWorldsDirectory.appendingPathComponent(thumbnail)) }
    }
}
