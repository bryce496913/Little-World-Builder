import XCTest
import Combine
import UIKit
import simd
import RealityKit
@testable import Little_World_Builder

final class Little_World_BuilderTests: XCTestCase {
    private func registeredObject(id: String, name: String, in manager: WorldManager, root: Entity) -> (UUID, ModelEntity) {
        let entry = AssetManifestEntry(id: id, fileName: "\(id).usdz", displayName: name, category: id == "tree" ? .trees : (id == "whale" ? .creatures : .land), thumbnailFileName: "\(id).png", defaultScale: 1, rotationXDegrees: 0, placementRole: id == "tree" ? .tree : (id == "whale" ? .creature : .base), gridFootprint: .init(width: 1, depth: 1), snapBehavior: .ground)
        let model = Model(entry: entry, assetURL: URL(fileURLWithPath: entry.fileName))
        let entity = ModelEntity(mesh: .generateBox(size: 0.1)); root.addChild(entity)
        let instanceID = UUID(); manager.register(entity, model: model, instanceID: instanceID)
        return (instanceID, entity)
    }

    private func activeManager() -> (WorldManager, Entity) {
        let manager = WorldManager(); let root = Entity()
        let anchor = AnchorEntity(); anchor.addChild(root); manager.activate(anchor: anchor, buildRoot: root)
        return (manager, root)
    }

    func testRootAndChildMeshResolveToRegisteredBuildRootObject() throws {
        let (manager, buildRoot) = activeManager()
        let (id, root) = registeredObject(id: "tree", name: "Tree", in: manager, root: buildRoot)
        let child = ModelEntity(mesh: .generateBox(size: 0.02)); root.addChild(child)
        XCTAssertTrue(try XCTUnwrap(PlacedObjectResolver.registeredRoot(from: root, buildRoot: buildRoot)).entity === root)
        let childResult = try XCTUnwrap(PlacedObjectResolver.registeredRoot(from: child, buildRoot: buildRoot))
        XCTAssertTrue(childResult.entity === root); XCTAssertEqual(childResult.component.instanceID, id)
    }

    func testTreeIslandAndWhaleAreSelectedByStableIdentity() {
        let (manager, root) = activeManager()
        for (asset, name) in [("tree", "Tree"), ("floating_island", "Floating Island"), ("whale", "Whale")] {
            let (id, _) = registeredObject(id: asset, name: name, in: manager, root: root)
            XCTAssertTrue(manager.select(instanceID: id))
            XCTAssertEqual(manager.interactionState.selection, .init(instanceID: id, catalogAssetID: asset))
        }
    }

    func testTemporaryGridAndSelectionOutlinesAreIgnored() {
        let (_, root) = activeManager()
        for name in ["temporary-placement-guide", "build-grid-overlay", "selection-outline"] {
            let visual = Entity(); visual.name = name; visual.components.set(NonSelectableComponent()); root.addChild(visual)
            XCTAssertNil(PlacedObjectResolver.registeredRoot(from: visual, buildRoot: root))
        }
    }

    func testEntityOutsideBuildRootIsIgnored() {
        let (manager, root) = activeManager()
        let otherRoot = Entity()
        let (_, entity) = registeredObject(id: "tree", name: "Tree", in: manager, root: otherRoot)
        XCTAssertNil(PlacedObjectResolver.registeredRoot(from: entity, buildRoot: root))
    }

    func testSelectionSwitchEmptyTapAndPlacementTransitions() {
        let (manager, root) = activeManager()
        let (first, _) = registeredObject(id: "tree", name: "Tree", in: manager, root: root)
        let (second, _) = registeredObject(id: "whale", name: "Whale", in: manager, root: root)
        XCTAssertTrue(manager.select(instanceID: first)); XCTAssertTrue(manager.select(instanceID: second))
        XCTAssertEqual(manager.interactionState.selection?.instanceID, second)
        manager.clearSelection(); XCTAssertEqual(manager.interactionState, .browse)
        XCTAssertTrue(manager.select(instanceID: first)); manager.beginPlacingAsset(catalogAssetID: "whale")
        XCTAssertEqual(manager.interactionState, .placingAsset(catalogAssetID: "whale")); XCTAssertNil(manager.interactionState.selection)
    }

    func testDeleteSelectedRemovesOnlySelectionAndClearsEdit() {
        let (manager, root) = activeManager()
        let (selected, selectedEntity) = registeredObject(id: "tree", name: "Tree", in: manager, root: root)
        let (other, otherEntity) = registeredObject(id: "whale", name: "Whale", in: manager, root: root)
        manager.select(instanceID: selected)
        XCTAssertTrue(manager.removeSelected()); XCTAssertNil(selectedEntity.parent)
        XCTAssertNotNil(otherEntity.parent); XCTAssertNotNil(manager.record(for: other)); XCTAssertEqual(manager.interactionState, .browse)
        XCTAssertFalse(manager.removeSelected())
    }

    func testWorldResetClearsSelection() {
        let (manager, root) = activeManager()
        let (id, _) = registeredObject(id: "tree", name: "Tree", in: manager, root: root)
        manager.select(instanceID: id); manager.resetActiveWorld()
        XCTAssertEqual(manager.interactionState, .browse); XCTAssertNil(manager.entity(for: id)); XCTAssertNil(manager.buildRoot)
    }

    func testRotationAndScaleAffectOnlySelectedRootAndNeverChildLocalTransform() {
        let (manager, root) = activeManager()
        let (selectedID, selected) = registeredObject(id: "whale", name: "Whale", in: manager, root: root)
        let (_, other) = registeredObject(id: "tree", name: "Tree", in: manager, root: root)
        let child = Entity(); child.position = [0.02, 0.03, 0.04]; selected.addChild(child)
        let childBefore = child.transform; let otherBefore = other.transform
        manager.select(instanceID: selectedID)
        selected.transform = SelectionTransformEditor.rotated(selected.transform, radians: .pi / 4)
        selected.transform = SelectionTransformEditor.scaled(selected.transform, factor: 1.5)
        XCTAssertEqual(selected.scale, SIMD3<Float>(repeating: 1.5)); XCTAssertNotEqual(selected.orientation.vector, SIMD4<Float>(0, 0, 0, 1))
        XCTAssertEqual(other.position, otherBefore.translation); XCTAssertEqual(other.scale, otherBefore.scale); XCTAssertEqual(other.orientation.vector, otherBefore.rotation.vector)
        XCTAssertEqual(child.position, childBefore.translation); XCTAssertEqual(child.scale, childBefore.scale); XCTAssertEqual(child.orientation.vector, childBefore.rotation.vector)
    }

    func testVerticalAdjustmentUsesExactStepsAndHandlesSignedHeights() throws {
        var transform = Transform(translation: [1, -0.03, 3])
        transform = try XCTUnwrap(VerticalAdjustment.applying(.raise, to: transform))
        XCTAssertEqual(transform.translation.y, -0.01, accuracy: 0.000001)
        transform = try XCTUnwrap(VerticalAdjustment.applying(.raise, to: transform))
        XCTAssertEqual(transform.translation.y, 0.01, accuracy: 0.000001)
        transform.translation.y = 0.03
        transform = try XCTUnwrap(VerticalAdjustment.applying(.lower, to: transform))
        XCTAssertEqual(transform.translation.y, 0.01, accuracy: 0.000001)
        XCTAssertEqual(VerticalAdjustmentConfiguration.stepMeters, 0.02)
    }

    func testHeightAdjustmentChangesOnlySelectedRootYAndPreservesTransformAndChildren() throws {
        let (manager, root) = activeManager()
        let (selectedID, selected) = registeredObject(id: "tree", name: "Tree", in: manager, root: root)
        let (_, other) = registeredObject(id: "whale", name: "Whale", in: manager, root: root)
        let child = Entity(); child.transform = Transform(scale: [0.2, 0.3, 0.4], rotation: simd_quatf(angle: 0.4, axis: [1, 0, 0]), translation: [4, 5, 6]); selected.addChild(child)
        selected.transform = Transform(scale: [0.7, 0.8, 0.9], rotation: simd_quatf(angle: 0.6, axis: [0, 1, 0]), translation: [1, 2, 3])
        let selectedBefore = selected.transform; let childBefore = child.transform; let otherBefore = other.transform

        XCTAssertTrue(manager.select(instanceID: selectedID))
        XCTAssertTrue(manager.adjustSelectedHeight(.raise))
        XCTAssertEqual(selected.position.x, 1, accuracy: 0.000001)
        XCTAssertEqual(selected.position.y, 2.02, accuracy: 0.000001)
        XCTAssertEqual(selected.position.z, 3, accuracy: 0.000001)
        XCTAssertEqual(selected.orientation.vector, selectedBefore.rotation.vector)
        XCTAssertEqual(selected.scale, selectedBefore.scale)
        XCTAssertEqual(child.position, childBefore.translation)
        XCTAssertEqual(child.orientation.vector, childBefore.rotation.vector)
        XCTAssertEqual(child.scale, childBefore.scale)
        XCTAssertEqual(other.position, otherBefore.translation)
        XCTAssertEqual(other.orientation.vector, otherBefore.rotation.vector)
        XCTAssertEqual(other.scale, otherBefore.scale)
        XCTAssertTrue(child.parent === selected)
        XCTAssertTrue(selected.parent === root)
    }

    func testOneStepHeightUndoPreservesCurrentRotationAndScale() {
        let (manager, root) = activeManager()
        let (id, selected) = registeredObject(id: "tree", name: "Tree", in: manager, root: root)
        selected.position = [1, 0.4, 3]
        manager.select(instanceID: id)
        XCTAssertTrue(manager.adjustSelectedHeight(.lower))
        selected.orientation = simd_quatf(angle: 0.8, axis: [0, 1, 0])
        selected.scale = [1.2, 1.3, 1.4]
        let rotation = selected.orientation; let scale = selected.scale
        XCTAssertTrue(manager.undoSelectedHeightAdjustment())
        XCTAssertEqual(selected.position.y, 0.4, accuracy: 0.000001)
        XCTAssertEqual(selected.orientation.vector, rotation.vector)
        XCTAssertEqual(selected.scale, scale)
        XCTAssertFalse(manager.heightAdjustmentState.canUndo)
        XCTAssertFalse(manager.undoSelectedHeightAdjustment())
    }

    func testSelectingAnotherEntityAndWorldResetClearHeightUndo() {
        let (manager, root) = activeManager()
        let (first, _) = registeredObject(id: "tree", name: "Tree", in: manager, root: root)
        let (second, _) = registeredObject(id: "whale", name: "Whale", in: manager, root: root)
        manager.select(instanceID: first); manager.adjustSelectedHeight(.raise)
        XCTAssertTrue(manager.heightAdjustmentState.canUndo)
        manager.select(instanceID: second)
        XCTAssertFalse(manager.heightAdjustmentState.canUndo)
        manager.adjustSelectedHeight(.lower); manager.resetActiveWorld()
        XCTAssertEqual(manager.heightAdjustmentState, .inactive)
    }

    func testInvalidHeightAndNonDirectRegisteredRootAreRejectedSafely() {
        let (manager, root) = activeManager()
        let (id, selected) = registeredObject(id: "tree", name: "Tree", in: manager, root: root)
        selected.position.y = .nan
        manager.select(instanceID: id)
        XCTAssertFalse(manager.heightAdjustmentState.canAdjust)
        XCTAssertFalse(manager.adjustSelectedHeight(.raise))
        XCTAssertTrue(selected.position.y.isNaN)

        selected.position.y = 0
        let intermediate = Entity(); root.addChild(intermediate); intermediate.addChild(selected)
        XCTAssertFalse(manager.adjustSelectedHeight(.raise))
        XCTAssertNil(manager.interactionState.selection)
    }

    func testAdjustedHeightRoundTripsThroughSchemaV2WithoutChangingScale() throws {
        let (manager, root) = activeManager()
        let (id, selected) = registeredObject(id: "tree", name: "Tree", in: manager, root: root)
        selected.transform = Transform(scale: [0.5, 0.5, 0.5], rotation: simd_quatf(angle: 0.3, axis: [0, 1, 0]), translation: [1, 0.11, 2])
        manager.select(instanceID: id); manager.adjustSelectedHeight(.raise)
        let world = try XCTUnwrap(ScenePersistenceHelper.makeWorld(from: manager))
        let decoded = try JSONDecoder().decode(SavedWorld.self, from: JSONEncoder().encode(world))
        let saved = try XCTUnwrap(decoded.placedAssets.first)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(saved.localTransform.position.y, 0.13, accuracy: 0.000001)
        XCTAssertEqual(saved.localTransform.scale, .init(x: 0.5, y: 0.5, z: 0.5))
        XCTAssertEqual(saved.localTransform.realityKitTransform.scale, selected.scale)
        XCTAssertEqual(saved.localTransform.realityKitTransform.rotation.vector, selected.orientation.vector)
    }

    func testPlacedRootTransformsSurviveFullSaveJSONRestoreAndRegistration() throws {
        let (sourceManager, sourceRoot) = activeManager()
        let specifications: [(String, String, SIMD3<Float>, Float, SIMD3<Float>)] = [
            ("island", "Island", [0.31, 0.00, -0.27], 0.17, [0.9, 1.1, 1.0]),
            ("tree", "Tree", [-0.14, 0.18, 0.33], -0.41, [0.55, 0.62, 0.58]),
            ("birds", "Birds", [0.22, 0.42, 0.11], 0.73, [1.2, 0.8, 1.1]),
            ("fish", "Fish", [-0.37, -0.06, -0.19], -0.29, [0.7, 0.75, 0.8])
        ]
        for (id, name, position, angle, scale) in specifications {
            let (_, entity) = registeredObject(id: id, name: name, in: sourceManager, root: sourceRoot)
            entity.transform = Transform(scale: scale,
                                         rotation: simd_quatf(angle: angle, axis: simd_normalize(SIMD3<Float>(1, 2, 3))),
                                         translation: position)
        }

        let encoded = try JSONEncoder().encode(try XCTUnwrap(ScenePersistenceHelper.makeWorld(from: sourceManager)))
        let decoded = try JSONDecoder().decode(SavedWorld.self, from: encoded)
        XCTAssertEqual(decoded.schemaVersion, 2)

        let (restoredManager, restoredRoot) = activeManager()
        for saved in decoded.placedAssets {
            let clone = ModelEntity(mesh: .generateBox(size: 0.1)).clone(recursive: true)
            restoredRoot.addChild(clone)
            clone.generateCollisionShapes(recursive: true)
            XCTAssertTrue(SavedPlacedAssetRestorer.apply(saved, to: clone, under: restoredRoot))
            let model = placementModel(id: saved.catalogAssetID)
            restoredManager.register(clone, model: model, instanceID: saved.id,
                                     displayName: saved.displayName, category: saved.category)

            XCTAssertTrue(clone.parent === restoredRoot)
            XCTAssertEqual(clone.position.x, saved.localTransform.position.x, accuracy: 0.000001)
            XCTAssertEqual(clone.position.y, saved.localTransform.position.y, accuracy: 0.000001)
            XCTAssertEqual(clone.position.z, saved.localTransform.position.z, accuracy: 0.000001)
            XCTAssertEqual(clone.orientation.vector, saved.localTransform.rotation.simd.vector)
            XCTAssertEqual(clone.scale, saved.localTransform.scale.simd)
            XCTAssertEqual(try XCTUnwrap(restoredManager.entity(for: saved.id)).position.y,
                           saved.localTransform.position.y, accuracy: 0.000001)
        }
        XCTAssertEqual(Set(decoded.placedAssets.map { $0.localTransform.position.y }), Set([0.00, 0.18, 0.42, -0.06]))
    }

    func testInitialPlacementSurfaceAndPendingHeightSurviveRestore() throws {
        let settings = PlacementSettings()
        settings.selectedModel = placementModel(id: "birds", snapBehavior: .floating)
        for _ in 0..<3 { XCTAssertTrue(settings.adjustPendingHeight(.raise)) }
        let placed = try XCTUnwrap(settings.transformByApplyingPendingHeight(to: Transform(translation: [0.12, 0.20, -0.35])))
        XCTAssertEqual(try saveAndRestoreY(placed), 0.26, accuracy: 0.000001)
    }

    func testPostPlacementEditedHeightSurvivesRestore() throws {
        var edited = Transform(translation: [-0.21, 0.18, 0.43])
        edited = try XCTUnwrap(VerticalAdjustment.applying(.raise, to: edited))
        edited = try XCTUnwrap(VerticalAdjustment.applying(.raise, to: edited))
        XCTAssertEqual(try saveAndRestoreY(edited), 0.22, accuracy: 0.000001)
    }

    private func saveAndRestoreY(_ transform: Transform) throws -> Float {
        let (manager, root) = activeManager()
        let (_, entity) = registeredObject(id: "tree", name: "Tree", in: manager, root: root)
        entity.transform = transform
        let data = try JSONEncoder().encode(try XCTUnwrap(ScenePersistenceHelper.makeWorld(from: manager)))
        let saved = try XCTUnwrap(JSONDecoder().decode(SavedWorld.self, from: data).placedAssets.first)
        let restoredRoot = Entity()
        let restored = ModelEntity(mesh: .generateBox(size: 0.1))
        restoredRoot.addChild(restored)
        restored.generateCollisionShapes(recursive: true)
        XCTAssertTrue(SavedPlacedAssetRestorer.apply(saved, to: restored, under: restoredRoot))
        return restored.position.y
    }
    private func objectCandidate(normal: SIMD3<Float> = [0, 1, 0],
                                 category: ModelCategory? = .land,
                                 role: PlacementRole? = .base,
                                 id: UUID = UUID(),
                                 position: SIMD3<Float> = [1, 2, 3]) -> PlacementTargetPolicy.ObjectCandidate {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(position, 1)
        return .init(position: position, normal: normal, worldTransform: transform,
                     instanceID: id, category: category, placementRole: role)
    }

    private func planeTarget(position: SIMD3<Float> = [4, 0, 5]) -> PlacementTarget {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(position, 1)
        return .init(worldPosition: position, worldTransform: transform, surfaceNormal: [0, 1, 0],
                     source: .arPlane, supportingObjectID: nil)
    }

    func testEligibleObjectTargetReportsSourceAndSupportingID() throws {
        let id = UUID()
        let target = try XCTUnwrap(PlacementTargetPolicy.select(objectCandidate: objectCandidate(id: id), planeTarget: planeTarget()))
        XCTAssertEqual(target.source, .placedObject)
        XCTAssertEqual(target.supportingObjectID, id)
        XCTAssertEqual(target.worldPosition, [1, 2, 3])
    }

    func testPlaneFallbackHasNoStaleSupportingID() throws {
        let noHit = try XCTUnwrap(PlacementTargetPolicy.select(objectCandidate: nil, planeTarget: planeTarget()))
        XCTAssertEqual(noHit.source, .arPlane)
        XCTAssertNil(noHit.supportingObjectID)

        let ineligible = try XCTUnwrap(PlacementTargetPolicy.select(
            objectCandidate: objectCandidate(category: .trees, role: .tree), planeTarget: planeTarget()))
        XCTAssertEqual(ineligible.source, .arPlane)
        XCTAssertNil(ineligible.supportingObjectID)
    }

    func testOnlyUpwardSupportCapableSurfacesAreAccepted() {
        XCTAssertEqual(PlacementTargetPolicy.minimumUpwardNormalDot, 0.67)
        let acceptedY = PlacementTargetPolicy.minimumUpwardNormalDot + 0.01
        let rejectedY = PlacementTargetPolicy.minimumUpwardNormalDot - 0.01
        XCTAssertNotNil(PlacementTargetPolicy.objectTarget(from: objectCandidate(normal: [sqrt(1 - acceptedY * acceptedY), acceptedY, 0])))
        XCTAssertNil(PlacementTargetPolicy.objectTarget(from: objectCandidate(normal: [sqrt(1 - rejectedY * rejectedY), rejectedY, 0])))
        XCTAssertNil(PlacementTargetPolicy.objectTarget(from: objectCandidate(normal: [1, 0.1, 0])))
        XCTAssertNil(PlacementTargetPolicy.objectTarget(from: objectCandidate(normal: [0, -1, 0])))
        XCTAssertNil(PlacementTargetPolicy.objectTarget(from: objectCandidate(category: .creatures, role: .creature)))
        XCTAssertNil(PlacementTargetPolicy.objectTarget(from: objectCandidate(category: .structures, role: .structure)))
    }

    func testInvalidObjectHitDataFallsBackToPlane() throws {
        let invalids = [
            objectCandidate(normal: .zero),
            objectCandidate(normal: [.nan, 1, 0]),
            objectCandidate(position: [.infinity, 0, 0])
        ]
        for candidate in invalids {
            let target = try XCTUnwrap(PlacementTargetPolicy.select(objectCandidate: candidate, planeTarget: planeTarget()))
            XCTAssertEqual(target.source, .arPlane)
            XCTAssertNil(target.supportingObjectID)
        }
    }

    func testChildMeshResolvesToRegisteredRootAndTemporaryEntitiesAreIgnored() throws {
        let id = UUID()
        let registeredRoot = Entity()
        registeredRoot.components.set(LocalModelComponent(instanceID: id, catalogAssetID: "floating_island", assetFileName: "floating_island.usdz"))
        let intermediate = Entity()
        let visibleChild = ModelEntity(mesh: .generateBox(size: 0.1))
        registeredRoot.addChild(intermediate)
        intermediate.addChild(visibleChild)

        let resolved = try XCTUnwrap(NativePlacementManager.registeredRoot(from: visibleChild))
        XCTAssertTrue(resolved.entity === registeredRoot)
        XCTAssertEqual(resolved.component.instanceID, id)

        let grid = Entity()
        let temporaryPreview = ModelEntity(mesh: .generatePlane(width: 0.1, depth: 0.1))
        grid.addChild(temporaryPreview)
        XCTAssertNil(NativePlacementManager.registeredRoot(from: temporaryPreview))
    }

    func testSavedWorldRootIgnoresObjectCandidateAndUsesPlaneOnly() throws {
        let plane = planeTarget()
        let target = try XCTUnwrap(PlacementTargetPolicy.select(purpose: .savedWorldRoot,
                                                                objectCandidate: objectCandidate(),
                                                                planeTarget: plane))
        XCTAssertEqual(target.source, .arPlane)
        XCTAssertNil(target.supportingObjectID)
        XCTAssertNil(PlacementTargetPolicy.select(purpose: .savedWorldRoot,
                                                  objectCandidate: objectCandidate(),
                                                  planeTarget: nil))
    }

    func testSettingIdenticalGridConfigurationDoesNotPublishAgain() {
        let manager = WorldManager()
        let configuration = SavedGridConfiguration(cellSizeMeters: 0.1, rotationStepDegrees: 90, wasEnabled: true)
        var publishCount = 0
        let subscription = manager.objectWillChange.sink { publishCount += 1 }

        manager.setGridConfiguration(configuration)
        manager.setGridConfiguration(configuration)
        manager.setGridConfiguration(configuration)

        XCTAssertEqual(manager.gridConfiguration, configuration)
        XCTAssertEqual(publishCount, 1)
        withExtendedLifetime(subscription) {}
    }

    func testSavedGridConfigurationEqualityIncludesPlacementMode() {
        let grid = SavedGridConfiguration(cellSizeMeters: 0.1, rotationStepDegrees: 90, wasEnabled: true)
        XCTAssertEqual(grid, grid)
        XCTAssertNotEqual(grid, SavedGridConfiguration(cellSizeMeters: 0.1, rotationStepDegrees: 90, wasEnabled: false))
    }

    func testPlacementModeCanSwitchToGridAndRemainSelected() {
        let settings = PlacementSettings()
        XCTAssertEqual(settings.placementMode, .free)

        settings.setPlacementMode(.grid)
        XCTAssertEqual(settings.placementMode, .grid)
        settings.setPlacementMode(.free)
        XCTAssertEqual(settings.placementMode, .free)
    }

    private func placementModel(id: String, snapBehavior: SnapBehavior = .ground) -> Model {
        let entry = AssetManifestEntry(id: id, fileName: "\(id).usdz", displayName: id,
                                       category: .trees, thumbnailFileName: "\(id).png", defaultScale: 1,
                                       rotationXDegrees: 0, placementRole: .tree,
                                       gridFootprint: .init(width: 1, depth: 1), snapBehavior: snapBehavior)
        return Model(entry: entry, assetURL: URL(fileURLWithPath: entry.fileName))
    }

    func testPendingHeightDefaultsStepsResetsAndRejectsNonFiniteValues() throws {
        let settings = PlacementSettings()
        XCTAssertEqual(settings.pendingHeightOffsetMeters, 0)
        settings.selectedModel = placementModel(id: "tree")
        XCTAssertTrue(settings.adjustPendingHeight(.raise))
        XCTAssertEqual(settings.pendingHeightOffsetMeters, 0.02, accuracy: 0.000001)
        XCTAssertTrue(settings.adjustPendingHeight(.lower))
        XCTAssertEqual(settings.pendingHeightOffsetMeters, 0, accuracy: 0.000001)
        settings.adjustPendingHeight(.lower)
        XCTAssertEqual(settings.pendingHeightOffsetMeters, -0.02, accuracy: 0.000001)
        settings.resetPendingHeight()
        XCTAssertEqual(settings.pendingHeightOffsetMeters, 0)
        XCTAssertNil(VerticalAdjustment.applying(offset: .nan, to: Transform()))
        XCTAssertNil(VerticalAdjustment.applying(.raise, to: Float.infinity))
    }

    func testPendingHeightIsRelativeToChangingSurfaceAndSurvivesModeChanges() throws {
        let settings = PlacementSettings()
        settings.selectedModel = placementModel(id: "birds", snapBehavior: .floating)
        for _ in 0..<3 { settings.adjustPendingHeight(.raise) }
        let island = try XCTUnwrap(settings.transformByApplyingPendingHeight(to: Transform(translation: [1, 0.20, 2])))
        XCTAssertEqual(island.translation.y, 0.26, accuracy: 0.000001)
        settings.setPlacementMode(.grid)
        let floor = try XCTUnwrap(settings.transformByApplyingPendingHeight(to: Transform(translation: [3, 0, 4])))
        XCTAssertEqual(floor.translation.y, 0.06, accuracy: 0.000001)
        XCTAssertEqual(settings.pendingHeightOffsetMeters, 0.06, accuracy: 0.000001)
    }

    func testDifferentAssetAndCancellationResetPendingHeight() {
        let settings = PlacementSettings()
        let tree = placementModel(id: "tree")
        settings.selectedModel = tree
        settings.adjustPendingHeight(.raise)
        settings.selectedModel = tree
        XCTAssertEqual(settings.pendingHeightOffsetMeters, 0.02, accuracy: 0.000001)
        settings.selectedModel = placementModel(id: "rock")
        XCTAssertEqual(settings.pendingHeightOffsetMeters, 0)
        settings.adjustPendingHeight(.lower)
        settings.selectedModel = nil
        XCTAssertEqual(settings.pendingHeightOffsetMeters, 0)
    }

    func testFinalPendingTransformIsSharedByPreviewAndConfirmationAndAppliedOnce() throws {
        let settings = PlacementSettings()
        let model = placementModel(id: "fish", snapBehavior: .free)
        settings.selectedModel = model
        settings.adjustPendingHeight(.lower)
        settings.adjustPendingHeight(.lower)
        let base = Transform(translation: [0.13, 0.5, -0.27])
        let final = try XCTUnwrap(settings.transformByApplyingPendingHeight(to: base))
        let solution = PendingPlacementSolution(id: UUID(), selectedAssetID: model.id,
                                                rawWorldTransform: matrix_identity_float4x4,
                                                rootLocalTransform: final, targetSource: .arPlane,
                                                supportingObjectID: nil, capturedSurfaceHeight: base.translation.y,
                                                gridCoordinateX: nil, gridCoordinateZ: nil, isValid: true, capturedAt: Date())
        settings.publish(solution)
        let confirmed = try XCTUnwrap(settings.capturePlacement(for: model))
        XCTAssertEqual(confirmed.solution.rootLocalTransform.translation, final.translation)
        XCTAssertEqual(final.translation.y, 0.46, accuracy: 0.000001)
        XCTAssertEqual(final.translation.x, base.translation.x)
        XCTAssertEqual(final.translation.z, base.translation.z)
    }

    func testFirstPlacementKeepsAnchorAtSurfaceAndStoresOffsetInAssetLocalY() throws {
        let settings = PlacementSettings()
        settings.selectedModel = placementModel(id: "birds", snapBehavior: .floating)
        for _ in 0..<5 { settings.adjustPendingHeight(.raise) }
        var nativeSurface = matrix_identity_float4x4
        nativeSurface.columns.3 = SIMD4(2, 1.25, -3, 1)
        let rootWorld = nativeSurface
        let baseLocal = Transform(matrix: try XCTUnwrap(WorldTransformMath.localMatrix(world: nativeSurface, rootWorld: rootWorld)))
        let assetLocal = try XCTUnwrap(settings.transformByApplyingPendingHeight(to: baseLocal))
        XCTAssertEqual(rootWorld.columns.3.y, nativeSurface.columns.3.y)
        XCTAssertEqual(assetLocal.translation.y, 0.10, accuracy: 0.000001)
    }

    func testFreeAssetAcceptsHeightWithoutXZOrYawSnapping() throws {
        let raw = Transform(scale: .one, rotation: simd_quatf(angle: 0.37, axis: [0, 1, 0]), translation: [0.13, 0.2, -0.27])
        let base = try XCTUnwrap(GridSnapResolver.resolve(rawLocalTransform: raw, footprint: .init(width: 2, depth: 1),
                                                         snapBehavior: .free, settings: .default, requestedQuarterTurns: 3))
        let adjusted = try XCTUnwrap(VerticalAdjustment.applying(offset: 0.02, to: base.transform))
        XCTAssertEqual(adjusted.translation, [0.13, 0.22, -0.27])
        XCTAssertEqual(adjusted.rotation.vector, raw.rotation.vector)
    }

    func testSettingIdenticalPlacementModeDoesNotPublishAgain() {
        let settings = PlacementSettings()
        var publishCount = 0
        let subscription = settings.objectWillChange.sink { publishCount += 1 }

        settings.setPlacementMode(.grid)
        settings.setPlacementMode(.grid)
        settings.setPlacementMode(.grid)

        XCTAssertEqual(settings.placementMode, .grid)
        XCTAssertEqual(publishCount, 1)
        withExtendedLifetime(subscription) {}
    }

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
        XCTAssertEqual(result.transform.translation.y, 0.7, accuracy: 0.0001)
    }

    func testGroundAndWaterPreserveSupportHeightWhileSnappingXZ() throws {
        let raw = Transform(scale: .one, rotation: simd_quatf(angle: 0.2, axis: [0, 1, 0]), translation: [0.14, 1.25, -0.16])
        for behavior in [SnapBehavior.ground, .water] {
            let result = try XCTUnwrap(GridSnapResolver.resolve(rawLocalTransform: raw, footprint: .init(width: 1, depth: 1), snapBehavior: behavior, settings: .default, requestedQuarterTurns: 0))
            XCTAssertEqual(result.transform.translation.x, 0.1, accuracy: 0.0001)
            XCTAssertEqual(result.transform.translation.y, 1.25, accuracy: 0.0001)
            XCTAssertEqual(result.transform.translation.z, -0.2, accuracy: 0.0001)
        }
    }

    func testObjectAndPlaneWorldHeightsConvertToRootLocalY() throws {
        var root = matrix_identity_float4x4
        root.columns.3 = SIMD4(5, 2, -3, 1)
        for (source, worldY, expectedY) in [(PlacementTargetSource.placedObject, Float(3.4), Float(1.4)), (.arPlane, Float(2), Float(0))] {
            var world = matrix_identity_float4x4
            world.columns.3 = SIMD4(7, worldY, 1, 1)
            let local = try XCTUnwrap(WorldTransformMath.localMatrix(world: world, rootWorld: root))
            XCTAssertEqual(local.columns.3.y, expectedY, accuracy: 0.0001, "\(source)")
        }
    }

    func testRotatedBuildRootConversionUsesInverseRootTransform() throws {
        var root = simd_float4x4(simd_quatf(angle: .pi / 2, axis: [0, 1, 0]))
        root.columns.3 = SIMD4(10, 1, -4, 1)
        var expectedLocal = matrix_identity_float4x4
        expectedLocal.columns.3 = SIMD4(2, 0.75, -3, 1)
        let local = try XCTUnwrap(WorldTransformMath.localMatrix(world: root * expectedLocal, rootWorld: root))
        XCTAssertEqual(local.columns.3.x, 2, accuracy: 0.0001)
        XCTAssertEqual(local.columns.3.y, 0.75, accuracy: 0.0001)
        XCTAssertEqual(local.columns.3.z, -3, accuracy: 0.0001)
    }

    func testPendingSolutionRejectsStaleAndMismatchedAssets() {
        let solution = PendingPlacementSolution(id: UUID(), selectedAssetID: "tree", rawWorldTransform: matrix_identity_float4x4,
                                                rootLocalTransform: Transform(translation: [1, 2, 3]), targetSource: .placedObject,
                                                supportingObjectID: UUID(), capturedSurfaceHeight: 2,
                                                gridCoordinateX: 10, gridCoordinateZ: 30, isValid: true,
                                                capturedAt: Date(timeIntervalSinceReferenceDate: 100))
        XCTAssertTrue(solution.canConfirm(assetID: "tree", now: Date(timeIntervalSinceReferenceDate: 100.5)))
        XCTAssertFalse(solution.canConfirm(assetID: "rock", now: Date(timeIntervalSinceReferenceDate: 100.5)))
        XCTAssertFalse(solution.canConfirm(assetID: "tree", now: Date(timeIntervalSinceReferenceDate: 102)))
        XCTAssertEqual(solution.rootLocalTransform.translation, [1, 2, 3])
    }

    func testRestoreKeepsSavedHeightAndPlacedAssetsRemainDirectRootChildren() {
        let root = Entity()
        let island = ModelEntity()
        let tree = ModelEntity()
        island.transform = Transform(translation: [0, 0, 0])
        tree.transform = CodableTransform(position: .init(x: 0.4, y: 1.75, z: -0.2),
                                           rotation: .identity, scale: .one).realityKitTransform
        root.addChild(island)
        root.addChild(tree)

        XCTAssertTrue(island.parent === root)
        XCTAssertTrue(tree.parent === root)
        XCTAssertFalse(tree.parent === island)
        XCTAssertEqual(tree.transform.translation.y, 1.75, accuracy: 0.0001)
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
        let expectedFootprints: [String: (width: Int, depth: Int)] = [
            "calm_low_level_water": (6, 6),
            "shallow_lagoon_ripples": (6, 6),
            "high_tide_ocean_swell": (6, 4),
            "choppy_storm_seas": (4, 4),
            "boiling_magical_springs": (4, 4),
            "swampy_green_bubbling_water": (4, 4),
            "turquoise_river": (6, 2)
        ]
        let waterEntries = try manifest().filter { $0.category == .water }
        XCTAssertEqual(Set(waterEntries.map(\.id)), Set(expectedFootprints.keys))
        XCTAssertTrue(waterEntries.allSatisfy { $0.rotationXDegrees == 0.0 })
        XCTAssertTrue(waterEntries.allSatisfy { $0.defaultScale == 1.0 })
        XCTAssertTrue(waterEntries.allSatisfy { $0.snapBehavior == .water })
        XCTAssertTrue(waterEntries.allSatisfy { $0.placementRole == .water })
        for entry in waterEntries {
            let footprint = try XCTUnwrap(expectedFootprints[entry.id])
            XCTAssertEqual(entry.gridFootprint.width, footprint.width, "\(entry.id) width")
            XCTAssertEqual(entry.gridFootprint.depth, footprint.depth, "\(entry.id) depth")
        }
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

    func testGuideGridMarkerUsesConfiguredCellSize() throws {
        let dimensions = try XCTUnwrap(GuideGeometry.gridMarkerDimensions(footprint: .init(width: 2, depth: 3), cellSizeMeters: 0.125))
        XCTAssertEqual(dimensions.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(dimensions.y, 0.375, accuracy: 0.0001)
    }

    func testThreeByThreeGuideMarkerIsThirtyCentimetersAtDefaultGridSize() throws {
        let dimensions = try XCTUnwrap(GuideGeometry.gridMarkerDimensions(footprint: .init(width: 3, depth: 3), cellSizeMeters: GridSettings.default.cellSizeMeters))
        XCTAssertEqual(dimensions, SIMD2<Float>(0.30, 0.30))
    }

    func testNormalizedVisualOutlineDoesNotUseGridDimensionsAndPreservesAspectRatio() throws {
        let entry = AssetManifestEntry(id: "outline", fileName: "outline.usdz", displayName: "Outline", category: .decor,
                                       thumbnailFileName: "outline.png", defaultScale: 1, rotationXDegrees: 0,
                                       placementRole: .decor, gridFootprint: .init(width: 1, depth: 1), snapBehavior: .ground)
        let model = Model(entry: entry, assetURL: URL(fileURLWithPath: entry.fileName))
        model.modelEntity = ModelEntity(mesh: .generateBox(size: [4, 2, 1]))
        let bounds = try XCTUnwrap(model.normalizedHorizontalVisualBounds())
        XCTAssertEqual(bounds.x, model.placementSize, accuracy: 0.0001)
        XCTAssertEqual(bounds.x / bounds.y, 4, accuracy: 0.001)
        XCTAssertNotEqual(bounds, SIMD2<Float>(0.1, 0.1))
    }

    func testCatalogRotationIsAppliedBeforeHorizontalBoundsMeasurement() throws {
        let entry = AssetManifestEntry(id: "rotated", fileName: "rotated.usdz", displayName: "Rotated", category: .decor,
                                       thumbnailFileName: "rotated.png", defaultScale: 1, rotationXDegrees: 90,
                                       placementRole: .decor, gridFootprint: .init(width: 1, depth: 1), snapBehavior: .ground)
        let model = Model(entry: entry, assetURL: URL(fileURLWithPath: entry.fileName))
        model.modelEntity = ModelEntity(mesh: .generateBox(size: [4, 2, 1]))
        let bounds = try XCTUnwrap(model.normalizedHorizontalVisualBounds())
        XCTAssertEqual(bounds.x / bounds.y, 2, accuracy: 0.001)
    }

    func testGuideYawSwapsRectangularPresentationAtNinetyDegrees() {
        let dimensions = SIMD2<Float>(0.36, 0.12)
        XCTAssertEqual(GuideGeometry.presentedDimensions(dimensions, quarterTurns: 0), dimensions)
        XCTAssertEqual(GuideGeometry.presentedDimensions(dimensions, quarterTurns: 1), SIMD2<Float>(0.12, 0.36))
        XCTAssertEqual(GuideGeometry.presentedDimensions(dimensions, quarterTurns: 2), dimensions)
    }

    func testGuideScaleUpdatesOutlineWithoutChangingPlacementTransform() throws {
        let transform = Transform(scale: [2, 1, 0.5], rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0]), translation: [1, 2, 3])
        let original = transform
        let scaled = try XCTUnwrap(GuideGeometry.scaledVisualDimensions([0.3, 0.2], scale: transform.scale))
        XCTAssertEqual(scaled, SIMD2<Float>(0.6, 0.1))
        XCTAssertEqual(transform.translation, original.translation)
        XCTAssertEqual(transform.rotation.vector, original.rotation.vector)
        XCTAssertEqual(transform.scale, original.scale)
    }

    func testInvalidGuideBoundsFallBackSafely() {
        XCTAssertFalse(GuideGeometry.validVisualDimensions([0, 1]))
        XCTAssertFalse(GuideGeometry.validVisualDimensions([.nan, 1]))
        XCTAssertFalse(GuideGeometry.validVisualDimensions([1, .infinity]))
        XCTAssertNil(GuideGeometry.scaledVisualDimensions([1, 1], scale: [.infinity, 1, 1]))
    }

    func testNormalizedBoundsCacheDoesNotCrossContaminateAssets() throws {
        func makeModel(id: String, width: Float) -> Model {
            let entry = AssetManifestEntry(id: id, fileName: "\(id).usdz", displayName: id, category: .decor,
                                           thumbnailFileName: "\(id).png", defaultScale: 1, rotationXDegrees: 0,
                                           placementRole: .decor, gridFootprint: .init(width: 1, depth: 1), snapBehavior: .ground)
            let model = Model(entry: entry, assetURL: URL(fileURLWithPath: entry.fileName))
            model.modelEntity = ModelEntity(mesh: .generateBox(size: [width, 1, 1]))
            return model
        }
        let wide = try XCTUnwrap(makeModel(id: "wide", width: 4).normalizedHorizontalVisualBounds())
        let square = try XCTUnwrap(makeModel(id: "square", width: 1).normalizedHorizontalVisualBounds())
        XCTAssertEqual(wide.x / wide.y, 4, accuracy: 0.001)
        XCTAssertEqual(square.x / square.y, 1, accuracy: 0.001)
    }

    func testTemporaryGuideEntitiesAreExcludedFromPersistence() throws {
        let manager = WorldManager()
        let root = Entity(); manager.activate(anchor: AnchorEntity(), buildRoot: root)
        let temporaryGuide = Entity(); temporaryGuide.name = "temporary-asset-size-outline"; root.addChild(temporaryGuide)
        let world = try XCTUnwrap(ScenePersistenceHelper.makeWorld(from: manager))
        XCTAssertTrue(world.placedAssets.isEmpty)
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

    func testPlacementNormalizationMatchesGuideAtArbitraryYawAndKeepsHeight() throws {
        let entry = AssetManifestEntry(id: "yaw", fileName: "yaw.usdz", displayName: "Yaw", category: .decor,
                                       thumbnailFileName: "yaw.png", defaultScale: 0.5, rotationXDegrees: 90,
                                       placementRole: .decor, gridFootprint: .init(width: 2, depth: 1), snapBehavior: .ground)
        let model = Model(entry: entry, assetURL: URL(fileURLWithPath: entry.fileName))
        model.modelEntity = ModelEntity(mesh: .generateBox(size: [4, 2, 1]))
        let guide = try XCTUnwrap(model.normalizedHorizontalVisualBounds())
        let parent = Entity()
        let baseline = try XCTUnwrap(model.makePlacementEntity(using: .identity))
        parent.addChild(baseline)
        for angle in [Float(0), .pi / 4, .pi / 2] {
            let pending = Transform(scale: .one, rotation: simd_quatf(angle: angle, axis: [0, 1, 0]), translation: [1, 0.26, -2])
            let placed = try XCTUnwrap(model.makePlacementEntity(using: pending))
            parent.addChild(placed)
            XCTAssertEqual(placed.scale.x, baseline.scale.x, accuracy: 0.00001)
            XCTAssertEqual(placed.scale.y, baseline.scale.y, accuracy: 0.00001)
            XCTAssertEqual(placed.scale.z, baseline.scale.z, accuracy: 0.00001)
            let bounds = placed.visualBounds(relativeTo: parent)
            let expectedX = abs(cos(angle)) * guide.x + abs(sin(angle)) * guide.y
            let expectedZ = abs(sin(angle)) * guide.x + abs(cos(angle)) * guide.y
            XCTAssertEqual(bounds.extents.x, expectedX, accuracy: 0.0001)
            XCTAssertEqual(bounds.extents.z, expectedZ, accuracy: 0.0001)
            XCTAssertEqual(bounds.center.x, pending.translation.x, accuracy: 0.0001)
            XCTAssertEqual(bounds.center.z, pending.translation.z, accuracy: 0.0001)
            XCTAssertEqual(bounds.min.y, pending.translation.y, accuracy: 0.0001)
        }
        XCTAssertEqual(model.modelEntity?.scale, SIMD3<Float>.one)
    }

    func testRenderedRectangularFootprintRotatesExactlyOnce() throws {
        let root = Entity()
        let visuals = GridVisualController()
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        let footprint = GridFootprint(width: 2, depth: 3)
        for turns in 0..<4 {
            let result = try XCTUnwrap(GridSnapResolver.resolve(rawLocalTransform: .identity, footprint: footprint,
                                                              snapBehavior: .ground, settings: .default, requestedQuarterTurns: turns))
            visuals.showPreview(result: result, settings: .default, visualBounds: nil, footprint: footprint,
                                showsFootprint: true, root: root, rootWorldTransform: matrix_identity_float4x4, in: view)
            let marker = try XCTUnwrap(root.children.first { $0.name == "temporary-grid-footprint-marker" })
            let bounds = marker.visualBounds(relativeTo: root)
            XCTAssertEqual(bounds.extents.x, Float(result.effectiveFootprint.width) * GridSettings.default.cellSizeMeters, accuracy: 0.0001)
            XCTAssertEqual(bounds.extents.z, Float(result.effectiveFootprint.depth) * GridSettings.default.cellSizeMeters, accuracy: 0.0001)
        }
    }

    func testLatestCatalogRequestWinsAndDismissalRejectsCompletion() {
        let settings = PlacementSettings()
        let older = settings.beginModelSelection()
        let newer = settings.beginModelSelection()
        let tree = placementModel(id: "tree")
        let rock = placementModel(id: "rock")
        XCTAssertFalse(settings.completeModelSelection(tree, requestID: older))
        XCTAssertTrue(settings.completeModelSelection(rock, requestID: newer))
        XCTAssertFalse(settings.completeModelSelection(tree, requestID: older))
        XCTAssertTrue(settings.selectedModel === rock)
        let dismissed = settings.beginModelSelection()
        settings.cancelModelSelection()
        XCTAssertFalse(settings.completeModelSelection(tree, requestID: dismissed))
        XCTAssertTrue(settings.selectedModel === rock)
    }

    func testRepeatedModelLoadsSharePublisherAndCompleteEveryWaiterOnMainThread() {
        let entry = AssetManifestEntry(id: "shared", fileName: "shared.usdz", displayName: "Shared", category: .decor,
                                       thumbnailFileName: "shared.png", defaultScale: 1, rotationXDegrees: 0,
                                       placementRole: .decor, gridFootprint: .init(width: 1, depth: 1), snapBehavior: .ground)
        let publisher = PassthroughSubject<ModelEntity, Error>()
        var loadCount = 0
        let model = Model(entry: entry, assetURL: URL(fileURLWithPath: entry.fileName), entityLoader: { _ in
            loadCount += 1
            return publisher.eraseToAnyPublisher()
        })
        let loaded = expectation(description: "Both saved instances finish loading")
        loaded.expectedFulfillmentCount = 2
        for _ in 0..<2 {
            model.asyncLoadModelEntity { success, error in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertTrue(success)
                XCTAssertNil(error)
                loaded.fulfill()
            }
        }
        XCTAssertEqual(loadCount, 1)
        let source = ModelEntity(mesh: .generateBox(size: 0.1))
        DispatchQueue.global().async {
            publisher.send(source)
            publisher.send(completion: .finished)
        }
        wait(for: [loaded], timeout: 2)
        XCTAssertTrue(model.modelEntity === source)
        model.asyncLoadModelEntity { success, _ in XCTAssertTrue(success) }
        XCTAssertEqual(loadCount, 1)
    }

    func testFailedSharedModelLoadCompletesEveryWaiterAndCanRetry() {
        let entry = AssetManifestEntry(id: "failed", fileName: "failed.usdz", displayName: "Failed", category: .decor,
                                       thumbnailFileName: "failed.png", defaultScale: 1, rotationXDegrees: 0,
                                       placementRole: .decor, gridFootprint: .init(width: 1, depth: 1), snapBehavior: .ground)
        var loadCount = 0
        let model = Model(entry: entry, assetURL: URL(fileURLWithPath: entry.fileName), entityLoader: { _ in
            loadCount += 1
            return Fail<ModelEntity, Error>(error: NSError(domain: "ModelLoad", code: 1)).eraseToAnyPublisher()
        })
        let failed = expectation(description: "All waiters observe failure")
        failed.expectedFulfillmentCount = 2
        for _ in 0..<2 {
            model.asyncLoadModelEntity { success, error in
                XCTAssertFalse(success)
                XCTAssertNotNil(error)
                XCTAssertTrue(Thread.isMainThread)
                failed.fulfill()
            }
        }
        wait(for: [failed], timeout: 2)
        XCTAssertEqual(loadCount, 1)
        let retried = expectation(description: "Failure permits another load")
        model.asyncLoadModelEntity { success, error in
            XCTAssertFalse(success); XCTAssertNotNil(error); retried.fulfill()
        }
        wait(for: [retried], timeout: 2)
        XCTAssertEqual(loadCount, 2)
    }

    func testSavedWorldRestoreRejectsDuplicateCancelledResetAndReplacedRequests() throws {
        let manager = WorldManager()
        let world = SavedWorld(id: UUID(), name: "World", createdAt: Date(), updatedAt: Date(), placedAssets: [], thumbnailFileName: nil)
        manager.loadWorld(world)
        let first = try XCTUnwrap(manager.beginPendingWorldRestore(worldID: world.id))
        XCTAssertNil(manager.beginPendingWorldRestore(worldID: world.id))
        XCTAssertTrue(manager.isPendingWorldRestoreCurrent(first, worldID: world.id))
        manager.cancelPendingWorldPlacement()
        XCTAssertFalse(manager.isPendingWorldRestoreCurrent(first, worldID: world.id))
        manager.loadWorld(world)
        let second = try XCTUnwrap(manager.beginPendingWorldRestore(worldID: world.id))
        manager.loadWorld(world)
        XCTAssertFalse(manager.isPendingWorldRestoreCurrent(second, worldID: world.id))
        let third = try XCTUnwrap(manager.beginPendingWorldRestore(worldID: world.id))
        manager.resetActiveWorld()
        XCTAssertFalse(manager.isPendingWorldRestoreCurrent(third, worldID: world.id))
        XCTAssertNotNil(manager.pendingWorldForPlacement) // Opening a new AR view preserves the pending world.
    }


    func testGridCoordinateOverflowFromSavedSettingsFailsSafely() throws {
        let saved = SavedGridConfiguration(cellSizeMeters: Float.leastNonzeroMagnitude, rotationStepDegrees: 90, wasEnabled: true)
        let decoded = try JSONDecoder().decode(SavedGridConfiguration.self, from: JSONEncoder().encode(saved))
        XCTAssertNil(GridSnapResolver.resolve(rawLocalTransform: Transform(translation: [1, 0, 1]),
                                             footprint: .init(width: 1, depth: 1), snapBehavior: .ground,
                                             settings: decoded.validatedSettings, requestedQuarterTurns: 0))
        XCTAssertNil(GridSnapResolver.resolve(rawLocalTransform: Transform(translation: [.greatestFiniteMagnitude, 0, 1]),
                                             footprint: .init(width: 1, depth: 1), snapBehavior: .ground,
                                             settings: .default, requestedQuarterTurns: 0))
        let normal = try XCTUnwrap(GridSnapResolver.resolve(rawLocalTransform: Transform(translation: [0.12, 0.7, -0.24]),
                                                          footprint: .init(width: 1, depth: 1), snapBehavior: .ground,
                                                          settings: .default, requestedQuarterTurns: 0))
        XCTAssertEqual(normal.transform.translation.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(normal.transform.translation.y, 0.7, accuracy: 0.0001)
        XCTAssertEqual(normal.transform.translation.z, -0.2, accuracy: 0.0001)
    }

}
