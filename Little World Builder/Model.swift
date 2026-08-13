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
    /// Final size multiplier applied once, after normalizing the asset to its footprint size.
    let defaultScale: Float
    let rotationXDegrees: Float
    private var cancellable: AnyCancellable?

    init(entry: AssetManifestEntry, assetURL: URL, bundle: Bundle = .main) {
        id = entry.id; name = entry.displayName; category = entry.category
        self.assetURL = assetURL; assetFileName = entry.fileName
        thumbnailFileName = entry.thumbnailFileName; placementRole = entry.placementRole
        gridFootprint = entry.gridFootprint; snapBehavior = entry.snapBehavior
        defaultScale = entry.defaultScale
        rotationXDegrees = entry.rotationXDegrees ?? 0
        thumbnail = Self.loadThumbnail(fileName: entry.thumbnailFileName, assetID: entry.id, bundle: bundle)
    }

    func asyncLoadModelEntity(handler: @escaping (Bool, Error?) -> Void) {
        cancellable = ModelEntity.loadModelAsync(contentsOf: assetURL).sink(receiveCompletion: {
            if case .failure(let error) = $0 { print("Model Error: \(self.assetFileName): \(error.localizedDescription)"); handler(false, error) }
        }, receiveValue: { entity in
            self.modelEntity = entity; handler(true, nil)
        })
    }

    func applyCatalogTransform(to entity: ModelEntity) {
        entity.orientation *= simd_quatf(angle: rotationXDegrees * .pi / 180, axis: [1, 0, 0])
    }

    /// Keeps assets authored in different unit systems at a predictable world-builder size.
    var placementSize: Float {
        0.18 * Float(max(gridFootprint.width, gridFootprint.depth))
    }

    func normalizePlacementSize(of entity: ModelEntity, relativeTo parent: Entity, at placementPosition: SIMD3<Float>) {
        var bounds = entity.visualBounds(relativeTo: parent)
        let largestDimension = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        guard largestDimension.isFinite, largestDimension > 0 else {
            print("Placement Warning: \(assetFileName) has invalid visual bounds; using its authored size.")
            return
        }

        entity.scale *= (placementSize * defaultScale) / largestDimension
        bounds = entity.visualBounds(relativeTo: parent)
        let bottomCenter = SIMD3<Float>(bounds.center.x, bounds.min.y, bounds.center.z)
        entity.position += placementPosition - bottomCenter
    }

    static func loadThumbnail(fileName: String, assetID: String, bundle: Bundle = .main) -> UIImage {
        let file = fileName as NSString
        if let url = bundle.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: "Thumbnails"),
           let image = UIImage(contentsOfFile: url.path) { return image }
        print("Thumbnail Error: missing or invalid Thumbnails/\(fileName) for asset \(assetID).")
        return UIImage(systemName: "photo") ?? UIImage()
    }
}
