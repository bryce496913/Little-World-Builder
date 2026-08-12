import Foundation
import RealityKit

enum SavedWorldCompatibilityError: LocalizedError {
    case unsupportedLegacySchema
    case unsupportedSchema(Int)
    var errorDescription: String? {
        switch self {
        case .unsupportedLegacySchema: return "This legacy saved world predates root-relative transforms and cannot be restored reliably. The file was left unchanged."
        case .unsupportedSchema(let version): return "Saved-world schema \(version) is not supported by this app."
        }
    }
}

struct SavedWorld: Codable, Identifiable {
    static let currentSchemaVersion = 2
    var schemaVersion: Int = currentSchemaVersion
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var placedAssets: [SavedPlacedAsset]
    var thumbnailFileName: String?

    init(id: UUID, name: String, createdAt: Date, updatedAt: Date, placedAssets: [SavedPlacedAsset], thumbnailFileName: String?) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.placedAssets = placedAssets; self.thumbnailFileName = thumbnailFileName
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let version = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) else { throw SavedWorldCompatibilityError.unsupportedLegacySchema }
        guard version == Self.currentSchemaVersion else { throw SavedWorldCompatibilityError.unsupportedSchema(version) }
        schemaVersion = version
        id = try values.decode(UUID.self, forKey: .id); name = try values.decode(String.self, forKey: .name)
        createdAt = try values.decode(Date.self, forKey: .createdAt); updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        placedAssets = try values.decode([SavedPlacedAsset].self, forKey: .placedAssets)
        thumbnailFileName = try values.decodeIfPresent(String.self, forKey: .thumbnailFileName)
        guard placedAssets.allSatisfy({ $0.localTransform.isFinite }) else { throw DecodingError.dataCorruptedError(forKey: .placedAssets, in: values, debugDescription: "Non-finite asset transform") }
    }
}

struct SavedPlacedAsset: Codable, Identifiable {
    var id: UUID
    var catalogAssetID: String
    var assetFileName: String
    var displayName: String
    var category: ModelCategory
    var localTransform: CodableTransform
}

struct CodableVector3: Codable, Equatable {
    var x, y, z: Float
    static let one = Self(x: 1, y: 1, z: 1), zero = Self(x: 0, y: 0, z: 0)
    init(x: Float, y: Float, z: Float) { self.x = x; self.y = y; self.z = z }
    init(_ value: SIMD3<Float>) { self.init(x: value.x, y: value.y, z: value.z) }
    var simd: SIMD3<Float> { [x, y, z] }
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

struct CodableQuaternion: Codable, Equatable {
    var x, y, z, w: Float
    static let identity = Self(x: 0, y: 0, z: 0, w: 1)
    init(x: Float, y: Float, z: Float, w: Float) { self.x=x; self.y=y; self.z=z; self.w=w }
    init(_ value: simd_quatf) { self.init(x:value.vector.x,y:value.vector.y,z:value.vector.z,w:value.vector.w) }
    var simd: simd_quatf { simd_quatf(ix:x, iy:y, iz:z, r:w) }
    var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite && w.isFinite }
}

struct CodableTransform: Codable, Equatable {
    var position: CodableVector3
    var rotation: CodableQuaternion
    var scale: CodableVector3
    init(position: CodableVector3, rotation: CodableQuaternion, scale: CodableVector3) { self.position=position; self.rotation=rotation; self.scale=scale }
    init(_ transform: Transform) { self.init(position: .init(transform.translation), rotation: .init(transform.rotation), scale: .init(transform.scale)) }
    var realityKitTransform: Transform { Transform(scale: scale.simd, rotation: rotation.simd, translation: position.simd) }
    var isFinite: Bool { position.isFinite && rotation.isFinite && scale.isFinite }
}

enum WorldTransformMath {
    static func localMatrix(world: simd_float4x4, rootWorld: simd_float4x4) -> simd_float4x4? {
        guard world.allFinite, rootWorld.allFinite, simd_determinant(rootWorld).isFinite, abs(simd_determinant(rootWorld)) > Float.ulpOfOne else { return nil }
        let result = simd_inverse(rootWorld) * world
        return result.allFinite ? result : nil
    }
}

private extension simd_float4x4 {
    var allFinite: Bool { columns.0.allFinite && columns.1.allFinite && columns.2.allFinite && columns.3.allFinite }
}
private extension SIMD4 where Scalar == Float { var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite && w.isFinite } }
