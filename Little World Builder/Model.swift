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
    private var loadHandlers: [(Bool, Error?) -> Void] = []
    private let entityLoader: (URL) -> AnyPublisher<ModelEntity, Error>
    private var cachedNormalizedHorizontalBounds: SIMD2<Float>?

    init(entry: AssetManifestEntry, assetURL: URL, bundle: Bundle = .main,
         entityLoader: @escaping (URL) -> AnyPublisher<ModelEntity, Error> = { ModelEntity.loadModelAsync(contentsOf: $0).eraseToAnyPublisher() }) {
        self.entityLoader = entityLoader
        id = entry.id; name = entry.displayName; category = entry.category
        self.assetURL = assetURL; assetFileName = entry.fileName
        thumbnailFileName = entry.thumbnailFileName; placementRole = entry.placementRole
        gridFootprint = entry.gridFootprint; snapBehavior = entry.snapBehavior
        defaultScale = entry.defaultScale
        rotationXDegrees = entry.rotationXDegrees ?? 0
        thumbnail = Self.loadThumbnail(fileName: entry.thumbnailFileName, assetID: entry.id, bundle: bundle)
    }

    func asyncLoadModelEntity(handler: @escaping (Bool, Error?) -> Void) {
        if modelEntity != nil { handler(true, nil); return }
        loadHandlers.append(handler)
        guard cancellable == nil else { return }
        cancellable = entityLoader(assetURL)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                self.cancellable = nil
                if case .failure(let error) = completion {
                    print("Model Error: \(self.assetFileName): \(error.localizedDescription)")
                    self.finishLoad(success: false, error: error)
                }
            }, receiveValue: { entity in
                self.modelEntity = entity
                self.cachedNormalizedHorizontalBounds = nil
                self.finishLoad(success: true, error: nil)
            })
    }

    private func finishLoad(success: Bool, error: Error?) {
        let handlers = loadHandlers
        loadHandlers.removeAll()
        handlers.forEach { $0(success, error) }
    }

    /// Normalize once in model-local axes, then compose the exact pending placement transform.
    /// Measuring after pending yaw would change size at arbitrary angles and diverge from the guide.
    func makePlacementEntity(using transform: Transform) -> ModelEntity? {
        guard let source = modelEntity, VerticalAdjustment.isFinite(transform) else { return nil }
        let prepared = source.clone(recursive: true)
        prepared.transform = .identity
        applyCatalogTransform(to: prepared)
        let measurementRoot = Entity()
        measurementRoot.addChild(prepared)
        normalizePlacementSize(of: prepared, relativeTo: measurementRoot, at: .zero)
        prepared.removeFromParent()
        prepared.transform = Transform(matrix: transform.matrix * prepared.transform.matrix)
        return prepared
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

    /// Measures the same catalog-rotated and normalized model used by placement. The result is
    /// cached in model-local axes, so pending yaw and scale can be applied without cloning per frame.
    func normalizedHorizontalVisualBounds() -> SIMD2<Float>? {
        if let cachedNormalizedHorizontalBounds { return cachedNormalizedHorizontalBounds }
        guard let prepared = makePlacementEntity(using: .identity) else { return nil }
        let measurementRoot = Entity()
        measurementRoot.addChild(prepared)
        let bounds = prepared.visualBounds(relativeTo: measurementRoot)
        let dimensions = SIMD2<Float>(bounds.extents.x, bounds.extents.z)
        guard GuideGeometry.validVisualDimensions(dimensions) else {
            print("Placement Warning: \(assetFileName) has invalid normalized horizontal bounds; hiding its visual outline.")
            return nil
        }
        cachedNormalizedHorizontalBounds = dimensions
        return dimensions
    }

    static func loadThumbnail(fileName: String, assetID: String, bundle: Bundle = .main) -> UIImage {
        let file = fileName as NSString
        if let url = bundle.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: "Thumbnails"),
           let image = UIImage(contentsOfFile: url.path) { return image }
        print("Thumbnail Error: missing or invalid Thumbnails/\(fileName) for asset \(assetID).")
        return UIImage(systemName: "photo") ?? UIImage()
    }
}
