import Foundation

enum PlacementRole: String, Codable, CaseIterable { case base, water, decor, tree, plant, creature, structure, vehicle, misc }
enum SnapBehavior: String, Codable, CaseIterable { case ground, water, floating, free }

struct GridFootprint: Codable, Equatable {
    let width: Int
    let depth: Int
    var isValid: Bool { width > 0 && depth > 0 }
}

struct AssetManifestEntry: Codable, Identifiable, Equatable {
    let id: String
    let fileName: String
    let displayName: String
    let category: ModelCategory
    let thumbnailFileName: String
    let defaultScale: Float
    let placementRole: PlacementRole
    let gridFootprint: GridFootprint
    let snapBehavior: SnapBehavior

    var validationErrors: [String] {
        var errors: [String] = []
        if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("empty id") }
        if fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("empty fileName") }
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("empty displayName") }
        if thumbnailFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("empty thumbnailFileName") }
        if !defaultScale.isFinite || defaultScale <= 0 { errors.append("defaultScale must be finite and positive") }
        if !gridFootprint.isValid { errors.append("gridFootprint dimensions must be positive") }
        return errors
    }
}

enum AssetManifestLoader {
    static func decode(_ data: Data) throws -> [AssetManifestEntry] { try JSONDecoder().decode([AssetManifestEntry].self, from: data) }
}
