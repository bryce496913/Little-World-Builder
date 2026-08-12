import Combine
import Foundation

final class ModelsViewModel: ObservableObject {
    static let appReadyUSDZSubdirectory = "App Ready USDZ"
    @Published var models: [Model] = []

    func fetchData(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "AssetManifest", withExtension: "json") else {
            print("Asset Manifest Error: bundled AssetManifest.json is missing."); models = []; return
        }
        let entries: [AssetManifestEntry]
        do { entries = try AssetManifestLoader.decode(Data(contentsOf: url)) }
        catch { print("Asset Manifest Error: \(error.localizedDescription)"); models = []; return }

        var ids = Set<String>(), files = Set<String>()
        let valid = entries.compactMap { entry -> Model? in
            let errors = entry.validationErrors
            guard errors.isEmpty else { print("Asset Manifest Error [\(entry.id)]: \(errors.joined(separator: ", "))"); return nil }
            guard ids.insert(entry.id).inserted else { print("Asset Manifest Error: duplicate id \(entry.id)"); return nil }
            guard files.insert(entry.fileName).inserted else { print("Asset Manifest Error: duplicate fileName \(entry.fileName)"); return nil }
            let file = entry.fileName as NSString
            guard let assetURL = bundle.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: Self.appReadyUSDZSubdirectory) else {
                print("Asset Manifest Error [\(entry.id)]: missing exact USDZ \(entry.fileName)"); return nil
            }
            return Model(entry: entry, assetURL: assetURL, bundle: bundle)
        }
        let bundled = Set((bundle.urls(forResourcesWithExtension: "usdz", subdirectory: Self.appReadyUSDZSubdirectory) ?? []).map(\.lastPathComponent))
        for unlisted in bundled.subtracting(files).sorted() { print("Asset Manifest Warning: unlisted bundled USDZ \(unlisted)") }
        models = valid.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func model(matching identifier: String) -> Model? { models.first { $0.id == identifier || $0.assetFileName == identifier } }
    func clearModelEntitiesFromMemory() { models.forEach { $0.modelEntity = nil } }
}
