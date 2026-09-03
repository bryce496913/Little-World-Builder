import XCTest
import UIKit
import simd
import RealityKit
@testable import Little_World_Builder

final class Little_World_BuilderTests: XCTestCase {
    func testGridSettingsValidationFallsBackToSafeDefaults() throws {
        let malformed = "{\"cellSizeMeters\":-1,\"rotationStepDegrees\":45.5,\"visibleRadiusInCells\":999}".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(GridSettings.self, from: malformed), .default)
    }

    func testGridResolverUsesFootprintParityAndRotatedFootprint() throws {
        let raw = Transform(scale: .one, rotation: simd_quatf(angle: 0.3, axis: [0, 1, 0]), translation: [0.12, 0.7, 0.24])
        let result = try XCTUnwrap(GridSnapResolver.resolve(rawLocalTransform: raw, footprint: .init(width: 2, depth: 3), snapBehavior: .ground, settings: .default, requestedQuarterTurns: 1))
        XCTAssertEqual(result.effectiveFootprint, GridFootprint(width: 3, depth: 2))
        XCTAssertEqual(result.transform.translation.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(result.transform.translation.z, 0.25, accuracy: 0.0001)
        XCTAssertEqual(result.transform.translation.y, 0, accuracy: 0.0001)
    }

    func testFloatingPreservesHeightAndFreeBypassesGrid() throws {
        let raw = Transform(scale: [2, 2, 2], rotation: simd_quatf(angle: 0.37, axis: [0, 1, 0]), translation: [0.12, 0.7, 0.24])
        let floating = try XCTUnwrap(GridSnapResolver.resolve(rawLocalTransform: raw, footprint: .init(width: 1, depth: 1), snapBehavior: .floating, settings: .default, requestedQuarterTurns: 2))
        XCTAssertEqual(floating.transform.translation.y, 0.7)
        let free = try XCTUnwrap(GridSnapResolver.resolve(rawLocalTransform: raw, footprint: .init(width: 2, depth: 2), snapBehavior: .free, settings: .default, requestedQuarterTurns: 3))
        XCTAssertEqual(free.transform.translation, raw.translation)
        XCTAssertEqual(free.transform.rotation.vector, raw.rotation.vector)
        XCTAssertEqual(free.transform.scale, raw.scale)
    }

    func testSchemaV2WithoutOptionalGridConfigurationRemainsCompatible() throws {
        let json = "{\"schemaVersion\":2,\"id\":\"\(UUID().uuidString)\",\"name\":\"Old v2\",\"createdAt\":0,\"updatedAt\":0,\"placedAssets\":[]}".data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(SavedWorld.self, from: json).gridConfiguration)
    }
    private var root: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent() }
    private func manifest() throws -> [AssetManifestEntry] { try AssetManifestLoader.decode(Data(contentsOf:root.appendingPathComponent("Little World Builder/AssetManifest.json"))) }

    func testManifestIsCompleteUniqueAndValid() throws {
        let entries=try manifest(); XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(entries.count, 27)
        XCTAssertEqual(Set(entries.map(\.id)).count,entries.count); XCTAssertEqual(Set(entries.map(\.fileName)).count,entries.count)
        for entry in entries { XCTAssertTrue(entry.validationErrors.isEmpty,"\(entry.id): \(entry.validationErrors)"); XCTAssertNotNil(ModelCategory(rawValue:entry.category.rawValue)); XCTAssertTrue(entry.defaultScale.isFinite); XCTAssertNotNil(entry.rotationXDegrees,"\(entry.id): rotation must be explicit"); XCTAssertTrue(entry.rotationXDegrees?.isFinite ?? false); XCTAssertGreaterThan(entry.defaultScale,0); XCTAssertGreaterThan(entry.gridFootprint.width,0); XCTAssertGreaterThan(entry.gridFootprint.depth,0); XCTAssertEqual((entry.fileName as NSString).deletingPathExtension,(entry.thumbnailFileName as NSString).deletingPathExtension,"\(entry.id): thumbnail must match USDZ basename") }
        let bundled=try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("App Ready USDZ"),includingPropertiesForKeys:nil).filter{$0.pathExtension=="usdz"}
        XCTAssertEqual(Set(entries.map(\.fileName)),Set(bundled.map(\.lastPathComponent)))
    }

    func testCreatureManifestMetadata() throws {
        struct ExpectedCreature {
            let fileName: String
            let thumbnailFileName: String
            let footprint: GridFootprint
            let snapBehavior: SnapBehavior
            let defaultScale: Float
            let targetRange: ClosedRange<Float>
        }
        let expected: [String: ExpectedCreature] = [
            "birds": .init(fileName: "birds.usdz", thumbnailFileName: "birds.png", footprint: .init(width: 2, depth: 1), snapBehavior: .floating, defaultScale: 0.45, targetRange: 0.15...0.17),
            "crabs": .init(fileName: "crabs.usdz", thumbnailFileName: "crabs.png", footprint: .init(width: 1, depth: 1), snapBehavior: .ground, defaultScale: 0.35, targetRange: 0.05...0.07),
            "fish": .init(fileName: "fish.usdz", thumbnailFileName: "fish.png", footprint: .init(width: 2, depth: 1), snapBehavior: .floating, defaultScale: 0.45, targetRange: 0.15...0.17),
            "manta": .init(fileName: "manta.usdz", thumbnailFileName: "manta.png", footprint: .init(width: 2, depth: 2), snapBehavior: .floating, defaultScale: 0.5, targetRange: 0.17...0.19),
            "turtle": .init(fileName: "turtle.usdz", thumbnailFileName: "turtle.png", footprint: .init(width: 2, depth: 2), snapBehavior: .floating, defaultScale: 0.45, targetRange: 0.15...0.17),
            "whale": .init(fileName: "whale.usdz", thumbnailFileName: "whale.png", footprint: .init(width: 3, depth: 2), snapBehavior: .floating, defaultScale: 0.45, targetRange: 0.23...0.25)
        ]
        let creatures = Dictionary(uniqueKeysWithValues: try manifest().filter { expected[$0.id] != nil }.map { ($0.id, $0) })
        XCTAssertEqual(Set(creatures.keys), Set(expected.keys))
        for (id, metadata) in expected {
            let entry = try XCTUnwrap(creatures[id], "missing creature \(id)")
            XCTAssertEqual(entry.fileName, metadata.fileName)
            XCTAssertEqual(entry.thumbnailFileName, metadata.thumbnailFileName)
            XCTAssertEqual(entry.category, .creatures)
            XCTAssertEqual(entry.placementRole, .creature)
            XCTAssertEqual(entry.gridFootprint, metadata.footprint)
            XCTAssertEqual(entry.snapBehavior, metadata.snapBehavior)
            XCTAssertTrue(entry.defaultScale.isFinite)
            XCTAssertEqual(entry.defaultScale, metadata.defaultScale)
            let effectivePlacementSize = 0.18 * Float(max(entry.gridFootprint.width, entry.gridFootprint.depth)) * entry.defaultScale
            XCTAssertTrue(metadata.targetRange.contains(effectivePlacementSize), "\(id): \(effectivePlacementSize) is outside \(metadata.targetRange)")
            XCTAssertNotNil(entry.rotationXDegrees)
            XCTAssertTrue(entry.rotationXDegrees?.isFinite ?? false)
            XCTAssertEqual(entry.rotationXDegrees, -90.0)
        }

        let effectiveSizes = creatures.mapValues { 0.18 * Float(max($0.gridFootprint.width, $0.gridFootprint.depth)) * $0.defaultScale }
        let crabs = try XCTUnwrap(effectiveSizes["crabs"])
        let whale = try XCTUnwrap(effectiveSizes["whale"])
        XCTAssertTrue(effectiveSizes.filter { $0.key != "crabs" }.allSatisfy { crabs < $0.value })
        XCTAssertTrue(effectiveSizes.filter { $0.key != "whale" }.allSatisfy { whale > $0.value })
        XCTAssertLessThan(try XCTUnwrap(effectiveSizes["birds"]), try XCTUnwrap(effectiveSizes["manta"]))
        XCTAssertLessThan(try XCTUnwrap(effectiveSizes["fish"]), try XCTUnwrap(effectiveSizes["manta"]))
    }

    func testObjectAndDecorScalesAreCalibratedBelowIslandScale() throws {
        let expectedScales: [String: Float] = [
            "tree": 0.5, "tree_cluster": 0.5, "rock": 0.45, "rock_cluster": 0.5,
            "grass": 0.4, "flowers": 0.4, "coral": 0.45
        ]
        let entries = Dictionary(uniqueKeysWithValues: try manifest().map { ($0.id, $0) })
        let island = try XCTUnwrap(entries["floating_island"])
        XCTAssertEqual(island.defaultScale, 1.0)
        for (id, expectedScale) in expectedScales {
            let entry = try XCTUnwrap(entries[id], "missing calibrated asset \(id)")
            XCTAssertEqual(entry.defaultScale, expectedScale)
            XCTAssertLessThan(entry.defaultScale, island.defaultScale)
        }
    }

    func testWaterUsesFlatCatalogOrientation() throws {
        let expectedWaterIDs: Set<String> = [
            "calm_low_level_water", "shallow_lagoon_ripples", "high_tide_ocean_swell",
            "choppy_storm_seas", "boiling_magical_springs", "swampy_green_bubbling_water",
            "turquoise_river"
        ]
        let waterEntries = try manifest().filter { $0.category == .water }
        XCTAssertEqual(Set(waterEntries.map(\.id)), expectedWaterIDs)
        XCTAssertTrue(waterEntries.allSatisfy { $0.rotationXDegrees == 0.0 })
        XCTAssertTrue(waterEntries.allSatisfy { $0.defaultScale == 1.0 })
    }

    func testCreatureNormalizationIsUniformAndInvalidBoundsAreSafe() throws {
        let entry = try XCTUnwrap(try manifest().first { $0.id == "birds" })
        let model = Model(entry: entry, assetURL: URL(fileURLWithPath: entry.fileName))
        let parent = Entity()
        let valid = ModelEntity(mesh: .generateBox(size: [2, 1, 0.5]))
        valid.scale = [1, 1, 1]
        parent.addChild(valid)
        model.normalizePlacementSize(of: valid, relativeTo: parent, at: .zero)
        XCTAssertEqual(valid.scale.x, valid.scale.y, accuracy: 0.0001)
        XCTAssertEqual(valid.scale.y, valid.scale.z, accuracy: 0.0001)

        let empty = ModelEntity()
        empty.scale = [2, 2, 2]
        parent.addChild(empty)
        model.normalizePlacementSize(of: empty, relativeTo: parent, at: .zero)
        XCTAssertEqual(empty.scale, [2, 2, 2])
    }

    func testManifestResourcesAreResolvedAndNotPointers() throws {
        for entry in try manifest() {
            let asset=root.appendingPathComponent("App Ready USDZ").appendingPathComponent(entry.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath:asset.path),entry.fileName)
            let data=try Data(contentsOf:asset); XCTAssertGreaterThan(data.count,1024,entry.fileName)
            XCTAssertFalse(String(data:data.prefix(200),encoding:.utf8)?.hasPrefix("version https://git-lfs.github.com/spec/v1") == true,"\(entry.fileName) is an unresolved LFS pointer; run git lfs install && git lfs pull")
            let thumbnail=root.appendingPathComponent("Thumbnails").appendingPathComponent(entry.thumbnailFileName)
            XCTAssertNotNil(UIImage(contentsOfFile:thumbnail.path),"missing/invalid \(entry.thumbnailFileName) for \(entry.id)")
        }
    }

    func testMissingManifestFileProducesControlledError() { XCTAssertThrowsError(try Data(contentsOf:root.appendingPathComponent("missing.json"))) }

    func testPlacementSizeFollowsGridFootprint() throws {
        let entries=try manifest()
        let island=try XCTUnwrap(entries.first { $0.id == "floating_island" })
        XCTAssertEqual(Model(entry:island,assetURL:URL(fileURLWithPath:"floating_island.usdz")).placementSize,0.54,accuracy:0.001)
    }

    func testDefaultScaleIsExposedAsFinalSizeMultiplier() throws {
        let entry = try XCTUnwrap(try manifest().first { $0.id == "floating_island" })
        let model = Model(entry: entry, assetURL: URL(fileURLWithPath: entry.fileName))
        XCTAssertEqual(model.defaultScale, entry.defaultScale)
    }

    func testThreeObjectsKeepRootRelativeLayoutAtNewWorldLocation() throws {
        let rootA=matrix_identity_float4x4
        var rootB=matrix_identity_float4x4; rootB.columns.3=SIMD4(20,2,-7,1)
        let worlds:[SIMD3<Float>]=[[1,0,2],[4,1,-3],[-2,2,5]]
        let locals=worlds.map { point -> simd_float4x4 in var m=matrix_identity_float4x4; m.columns.3=SIMD4(point,1); return WorldTransformMath.localMatrix(world:m,rootWorld:rootA)! }
        XCTAssertEqual(locals.map{$0.columns.3.x},[1,4,-2])
        let restored=locals.map { rootB * $0 }
        for i in 1..<restored.count { XCTAssertEqual(restored[i].columns.3-restored[0].columns.3,locals[i].columns.3-locals[0].columns.3) }
    }

    func testSchemaV2RoundTripPreservesRotationScaleAndInstanceIDs() throws {
        let shared="whale"; let ids=[UUID(),UUID()]
        let scales: [CodableVector3] = [.init(x: 0.9, y: 0.9, z: 0.9), .init(x: 1.2, y: 1.2, z: 1.2)]
        let assets=ids.enumerated().map { i,id in SavedPlacedAsset(id:id,catalogAssetID:shared,assetFileName:"whale.usdz",displayName:"Whale",category:.creatures,localTransform:CodableTransform(position:.init(x:Float(i),y:2,z:3),rotation:.init(x:0,y:0.7071067,z:0,w:0.7071067),scale:scales[i])) }
        let world=SavedWorld(id:UUID(),name:"No required island",createdAt:Date(),updatedAt:Date(),placedAssets:assets,thumbnailFileName:nil)
        let decoded=try JSONDecoder().decode(SavedWorld.self,from:JSONEncoder().encode(world))
        XCTAssertEqual(decoded.schemaVersion,2); XCTAssertEqual(decoded.placedAssets.map(\.id),ids); XCTAssertEqual(decoded.placedAssets[0].localTransform.rotation,assets[0].localTransform.rotation); XCTAssertEqual(decoded.placedAssets.map(\.localTransform.scale),scales)
    }

    func testWorldWithNoIslandAndMultipleIslandsRoundTrips() throws {
        let empty=SavedWorld(id:UUID(),name:"Empty",createdAt:Date(),updatedAt:Date(),placedAssets:[],thumbnailFileName:nil)
        XCTAssertTrue(try JSONDecoder().decode(SavedWorld.self,from:JSONEncoder().encode(empty)).placedAssets.isEmpty)
        let island=SavedPlacedAsset(id:UUID(),catalogAssetID:"forest_island",assetFileName:"forest_island.usdz",displayName:"Forest Island",category:.land,localTransform:.init(position:.zero,rotation:.identity,scale:.one))
        let multi=SavedWorld(id:UUID(),name:"Multiple",createdAt:Date(),updatedAt:Date(),placedAssets:[island,SavedPlacedAsset(id:UUID(),catalogAssetID:island.catalogAssetID,assetFileName:island.assetFileName,displayName:island.displayName,category:island.category,localTransform:island.localTransform)],thumbnailFileName:nil)
        XCTAssertEqual(try JSONDecoder().decode(SavedWorld.self,from:JSONEncoder().encode(multi)).placedAssets.count,2)
    }

    func testLegacySchemaIsExplicitlyUnsupported() throws {
        let legacy = "{\"id\":\"\(UUID().uuidString)\",\"name\":\"Legacy\",\"createdAt\":0,\"updatedAt\":0,\"placedAssets\":[]}".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(SavedWorld.self,from:legacy)) { XCTAssertTrue($0 is SavedWorldCompatibilityError) }
    }

    func testNonFiniteTransformIsRejected() throws {
        let asset=SavedPlacedAsset(id:UUID(),catalogAssetID:"tree",assetFileName:"tree.usdz",displayName:"Tree",category:.trees,localTransform:.init(position:.init(x:.infinity,y:0,z:0),rotation:.identity,scale:.one))
        let world=SavedWorld(id:UUID(),name:"Bad",createdAt:Date(),updatedAt:Date(),placedAssets:[asset],thumbnailFileName:nil)
        let encoder=JSONEncoder(); encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity:"Infinity",negativeInfinity:"-Infinity",nan:"NaN")
        let decoder=JSONDecoder(); decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity:"Infinity",negativeInfinity:"-Infinity",nan:"NaN")
        XCTAssertThrowsError(try decoder.decode(SavedWorld.self,from:encoder.encode(world)))
    }
}
