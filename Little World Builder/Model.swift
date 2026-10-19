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
    var modelEntity: ModelEntity? {
        didSet { cachedPlacementGeometry = nil; didPrepareGeometry = false }
    }
    /// Final size multiplier applied once, after normalizing the asset to its footprint size.
    let defaultScale: Float
    let rotationXDegrees: Float
    private var cancellable: AnyCancellable?
    private var loadHandlers: [(Bool, Error?) -> Void] = []
    private let entityLoader: (URL) -> AnyPublisher<ModelEntity, Error>
    private var cachedPlacementGeometry: PreparedPlacementGeometry?
    private var didPrepareGeometry = false

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
                self.finishLoad(success: true, error: nil)
            })
    }

    private func finishLoad(success: Bool, error: Error?) {
        let handlers = loadHandlers
        loadHandlers.removeAll()
        handlers.forEach { $0(success, error) }
    }

    /// Catalog orientation, normalization, and manifest scale are evaluated once per load.
    /// The cache contains only geometry metadata; child geometry is never moved to fix contact.
    func preparedPlacementGeometry() -> PreparedPlacementGeometry? {
        if didPrepareGeometry { return cachedPlacementGeometry }
        didPrepareGeometry = true
        guard let source = modelEntity, defaultScale.isFinite, defaultScale > 0 else { return nil }
        let prepared = source.clone(recursive: true)
        prepared.transform = .identity
        applyCatalogTransform(to: prepared)
        let measurementRoot = Entity(); measurementRoot.addChild(prepared)
        guard PreparedPlacementGeometry.valid(prepared.visualBounds(relativeTo: measurementRoot)) else { return nil }
        normalizePlacementSize(of: prepared, relativeTo: measurementRoot, at: .zero)
        let bounds = prepared.visualBounds(relativeTo: measurementRoot)
        guard PreparedPlacementGeometry.valid(bounds), VerticalAdjustment.isFinite(prepared.transform) else { return nil }
        let geometry = PreparedPlacementGeometry(id: UUID(), normalizedTransform: prepared.transform, normalizedBounds: bounds)
        cachedPlacementGeometry = geometry
        return geometry
    }

    func makePlacementEntity(using transform: Transform) -> ModelEntity? {
        guard let geometry = preparedPlacementGeometry(),
              let resolved = geometry.rootTransform(for: transform) else { return nil }
        return makePlacementEntity(resolvedTransform: resolved, preparationID: geometry.id)
    }

    /// Confirmation consumes the captured root transform, with no second alignment/normalization.
    func makePlacementEntity(resolvedTransform: Transform, preparationID: UUID) -> ModelEntity? {
        guard let geometry = preparedPlacementGeometry(), geometry.id == preparationID,
              let source = modelEntity, VerticalAdjustment.isFinite(resolvedTransform) else { return nil }
        let clone = source.clone(recursive: true)
        clone.transform = resolvedTransform
        return clone
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
        guard let geometry = preparedPlacementGeometry() else { return nil }
        return SIMD2(geometry.normalizedBounds.extents.x, geometry.normalizedBounds.extents.z)
    }

    static func loadThumbnail(fileName: String, assetID: String, bundle: Bundle = .main) -> UIImage {
        let file = fileName as NSString
        if let url = bundle.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: "Thumbnails"),
           let image = UIImage(contentsOfFile: url.path) { return image }
        print("Thumbnail Error: missing or invalid Thumbnails/\(fileName) for asset \(assetID).")
        return UIImage(systemName: "photo") ?? UIImage()
    }
}

/// The captured surface controls contact. Bounds belong exclusively to the selected asset.
struct PreparedPlacementGeometry {
    let id: UUID
    let normalizedTransform: Transform
    let normalizedBounds: BoundingBox

    static func valid(_ bounds: BoundingBox) -> Bool {
        let values = [bounds.min, bounds.max, bounds.extents]
        return values.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
            && bounds.extents.x > 0 && bounds.extents.z > 0 && bounds.extents.y >= 0
    }

    func rootTransform(for contact: Transform) -> Transform? {
        guard Self.valid(normalizedBounds), VerticalAdjustment.isFinite(normalizedTransform),
              VerticalAdjustment.isFinite(contact),
              contact.scale.x > 0, contact.scale.y > 0, contact.scale.z > 0 else { return nil }
        // Upright object placement has yaw only. Transforming these prepared bounds also handles
        // finite user scale and authored pivots without repeating catalog scale or normalization.
        let orientationAndScale = Transform(scale: contact.scale, rotation: contact.rotation, translation: .zero).matrix
        var bottom = Float.infinity
        for x in [normalizedBounds.min.x, normalizedBounds.max.x] {
            for y in [normalizedBounds.min.y, normalizedBounds.max.y] {
                for z in [normalizedBounds.min.z, normalizedBounds.max.z] {
                    bottom = min(bottom, (orientationAndScale * SIMD4<Float>(x, y, z, 1)).y)
                }
            }
        }
        guard bottom.isFinite else { return nil }
        var matrix = contact.matrix * normalizedTransform.matrix
        // contact.Y already contains captured surface Y plus the pending offset. Subtract the
        // selected asset's prepared bottom once; support bounds never participate.
        matrix.columns.3.y -= bottom
        let result = Transform(matrix: matrix)
        return VerticalAdjustment.isFinite(result) ? result : nil
    }
}
