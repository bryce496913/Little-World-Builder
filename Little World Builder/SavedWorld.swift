import Foundation
import RealityKit

struct SavedWorld: Codable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var placedAssets: [SavedPlacedAsset]
    var thumbnailFileName: String?
}

struct SavedPlacedAsset: Codable, Identifiable {
    var id: UUID
    var assetFileName: String
    var displayName: String
    var category: ModelCategory
    var position: CodableVector3
    var rotation: CodableQuaternion
    var scale: CodableVector3
}

struct CodableVector3: Codable, Equatable {
    var x: Float
    var y: Float
    var z: Float

    static let one = CodableVector3(x: 1, y: 1, z: 1)
    static let zero = CodableVector3(x: 0, y: 0, z: 0)

    init(x: Float, y: Float, z: Float) { self.x = x; self.y = y; self.z = z }
    init(_ value: SIMD3<Float>) { self.init(x: value.x, y: value.y, z: value.z) }
    var simd: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}

struct CodableQuaternion: Codable, Equatable {
    var x: Float
    var y: Float
    var z: Float
    var w: Float

    static let identity = CodableQuaternion(x: 0, y: 0, z: 0, w: 1)

    init(x: Float, y: Float, z: Float, w: Float) { self.x = x; self.y = y; self.z = z; self.w = w }
    init(_ value: simd_quatf) { self.init(x: value.vector.x, y: value.vector.y, z: value.vector.z, w: value.vector.w) }
    var simd: simd_quatf { simd_quatf(ix: x, iy: y, iz: z, r: w) }
}

struct CodableTransform: Codable, Equatable {
    var position: CodableVector3
    var rotation: CodableQuaternion
    var scale: CodableVector3

    init(position: CodableVector3, rotation: CodableQuaternion, scale: CodableVector3) {
        self.position = position; self.rotation = rotation; self.scale = scale
    }

    init(_ transform: Transform) {
        self.init(position: CodableVector3(transform.translation), rotation: CodableQuaternion(transform.rotation), scale: CodableVector3(transform.scale))
    }

    var realityKitTransform: Transform { Transform(scale: scale.simd, rotation: rotation.simd, translation: position.simd) }
}
