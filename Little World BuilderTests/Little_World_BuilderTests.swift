import XCTest
@testable import Little_World_Builder

final class Little_World_BuilderTests: XCTestCase {
    private let islandNames: [String: String] = [
        "floating_island.usdz": "Floating Island",
        "forest_island.usdz": "Forest Island",
        "lagoon_island.usdz": "Lagoon Island",
        "rocky_island.usdz": "Rocky Island",
        "sandy_beach_island.usdz": "Sandy Beach Island",
        "snow_island.usdz": "Snow Island",
        "volcano_island.usdz": "Volcano Island"
    ]

    func testDisplayNamesReplaceHyphensAndUnderscores() {
        XCTAssertEqual(Model.displayName(for: "beach-island"), "Beach Island")
        XCTAssertEqual(Model.displayName(for: "sandy_beach_island"), "Sandy Beach Island")
    }

    func testAllNewIslandNamesAndCategories() {
        XCTAssertEqual(islandNames.count, 7)
        for (fileName, displayName) in islandNames {
            let identifier = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
            XCTAssertEqual(Model.displayName(for: identifier), displayName)
            XCTAssertEqual(ModelsViewModel.category(for: identifier), .land)
        }
    }

    func testLookupUsesStableExactAssetFileNameAndHandlesMissingFile() {
        let fileName = "sandy_beach_island.usdz"
        let model = Model(assetURL: URL(fileURLWithPath: "/App Ready USDZ/\(fileName)"), category: .land)
        let viewModel = ModelsViewModel()
        viewModel.models = [model]

        XCTAssertEqual(model.id, "sandy_beach_island")
        XCTAssertEqual(model.assetFileName, fileName)
        XCTAssertTrue(viewModel.model(matching: fileName) === model)
        XCTAssertNil(viewModel.model(matching: "missing_island.usdz"))
    }

    func testIslandSavedWorldRoundTripPreservesGenericAssetData() throws {
        let asset = SavedPlacedAsset(
            id: UUID(), assetFileName: "floating_island.usdz", displayName: "Floating Island", category: .land,
            position: CodableVector3(x: 1, y: 2, z: 3), rotation: .identity, scale: .one
        )
        let world = SavedWorld(id: UUID(), name: "Island World", createdAt: Date(), updatedAt: Date(), placedAssets: [asset], thumbnailFileName: nil)
        let decoded = try JSONDecoder().decode(SavedWorld.self, from: JSONEncoder().encode(world))

        XCTAssertEqual(decoded.placedAssets.first?.id, asset.id)
        XCTAssertEqual(decoded.placedAssets.first?.assetFileName, "floating_island.usdz")
        XCTAssertEqual(decoded.placedAssets.first?.category, .land)
        XCTAssertEqual(decoded.placedAssets.first?.position, asset.position)
        XCTAssertEqual(decoded.placedAssets.first?.rotation, asset.rotation)
        XCTAssertEqual(decoded.placedAssets.first?.scale, asset.scale)
    }

    func testSavedWorldWithoutIslandRoundTrip() throws {
        let world = SavedWorld(id: UUID(), name: "Empty World", createdAt: Date(), updatedAt: Date(), placedAssets: [], thumbnailFileName: nil)
        let decoded = try JSONDecoder().decode(SavedWorld.self, from: JSONEncoder().encode(world))

        XCTAssertTrue(decoded.placedAssets.isEmpty)
    }
}
