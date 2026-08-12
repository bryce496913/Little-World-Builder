import SwiftUI
import RealityKit
import Combine

enum ModelCategory: String, CaseIterable, Codable {
    case land, water, trees, plants, creatures, vehicles, structures, decor, misc
    var label: String { rawValue.capitalized }
}

final class Model: ObservableObject, Identifiable {
    let id: String
    let name: String
    let category: ModelCategory
    let assetURL: URL
    let assetFileName: String
    let thumbnailFileName: String
    let placementRole: PlacementRole
    let gridFootprint: GridFootprint
    let snapBehavior: SnapBehavior
    @Published var thumbnail: UIImage
    var modelEntity: ModelEntity?
    let scaleCompensation: Float
    private var cancellable: AnyCancellable?

    init(entry: AssetManifestEntry, assetURL: URL, bundle: Bundle = .main) {
        id = entry.id; name = entry.displayName; category = entry.category
        self.assetURL = assetURL; assetFileName = entry.fileName
        thumbnailFileName = entry.thumbnailFileName; placementRole = entry.placementRole
        gridFootprint = entry.gridFootprint; snapBehavior = entry.snapBehavior
        scaleCompensation = entry.defaultScale
        thumbnail = Self.loadThumbnail(fileName: entry.thumbnailFileName, assetID: entry.id, bundle: bundle)
    }

    func asyncLoadModelEntity(handler: @escaping (Bool, Error?) -> Void) {
        cancellable = ModelEntity.loadModelAsync(contentsOf: assetURL).sink(receiveCompletion: {
            if case .failure(let error) = $0 { print("Model Error: \(self.assetFileName): \(error.localizedDescription)"); handler(false, error) }
        }, receiveValue: { entity in
            self.modelEntity = entity; entity.scale *= self.scaleCompensation; handler(true, nil)
        })
    }

    static func loadThumbnail(fileName: String, assetID: String, bundle: Bundle = .main) -> UIImage {
        let file = fileName as NSString
        if let url = bundle.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: "Thumbnails"),
           let image = UIImage(contentsOfFile: url.path) { return image }
        print("Thumbnail Error: missing or invalid Thumbnails/\(fileName) for asset \(assetID).")
        return UIImage(systemName: "photo") ?? UIImage()
    }
}
