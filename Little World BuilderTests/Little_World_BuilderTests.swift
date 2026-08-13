import XCTest
import UIKit
import simd
@testable import Little_World_Builder

final class Little_World_BuilderTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent() }
    private func manifest() throws -> [AssetManifestEntry] { try AssetManifestLoader.decode(Data(contentsOf:root.appendingPathComponent("Little World Builder/AssetManifest.json"))) }

    func testManifestIsCompleteUniqueAndValid() throws {
        let entries=try manifest(); XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(Set(entries.map(\.id)).count,entries.count); XCTAssertEqual(Set(entries.map(\.fileName)).count,entries.count)
        for entry in entries { XCTAssertTrue(entry.validationErrors.isEmpty,"\(entry.id): \(entry.validationErrors)"); XCTAssertNotNil(ModelCategory(rawValue:entry.category.rawValue)); XCTAssertTrue(entry.defaultScale.isFinite); XCTAssertTrue(entry.rotationXDegrees?.isFinite ?? true); XCTAssertGreaterThan(entry.defaultScale,0); XCTAssertGreaterThan(entry.gridFootprint.width,0); XCTAssertGreaterThan(entry.gridFootprint.depth,0) }
        let bundled=try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("App Ready USDZ"),includingPropertiesForKeys:nil).filter{$0.pathExtension=="usdz"}
        XCTAssertEqual(Set(entries.map(\.fileName)),Set(bundled.map(\.lastPathComponent)))
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
        let shared="floating_island"; let ids=[UUID(),UUID()]
        let assets=ids.enumerated().map { i,id in SavedPlacedAsset(id:id,catalogAssetID:shared,assetFileName:"floating_island.usdz",displayName:"Floating Island",category:.land,localTransform:CodableTransform(position:.init(x:Float(i),y:2,z:3),rotation:.init(x:0,y:0.7071067,z:0,w:0.7071067),scale:.init(x:1,y:2,z:3))) }
        let world=SavedWorld(id:UUID(),name:"No required island",createdAt:Date(),updatedAt:Date(),placedAssets:assets,thumbnailFileName:nil)
        let decoded=try JSONDecoder().decode(SavedWorld.self,from:JSONEncoder().encode(world))
        XCTAssertEqual(decoded.schemaVersion,2); XCTAssertEqual(decoded.placedAssets.map(\.id),ids); XCTAssertEqual(decoded.placedAssets[0].localTransform.rotation,assets[0].localTransform.rotation); XCTAssertEqual(decoded.placedAssets[0].localTransform.scale,assets[0].localTransform.scale)
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
