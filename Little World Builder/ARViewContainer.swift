import SwiftUI
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject var placementSettings: PlacementSettings
    @EnvironmentObject var sessionSettings: SessionSettings
    @EnvironmentObject var sceneManager: SceneManager
    @EnvironmentObject var modelsViewModel: ModelsViewModel
    @EnvironmentObject var worldManager: WorldManager

    func makeUIView(context: Context) -> CustomARView {
        sceneManager.clearCurrentScene()
        worldManager.resetActiveWorld()
        placementSettings.resetPendingHeight()
        let view = CustomARView(frame:.zero,sessionSettings:sessionSettings,worldManager:worldManager)
        sceneManager.arView=view
        placementSettings.sceneObserver=view.scene.subscribe(to:SceneEvents.Update.self) { _ in self.updateScene(for:view) }
        return view
    }
    func updateUIView(_ uiView: CustomARView, context: Context) {}

    private func updateScene(for arView: CustomARView) {
        if let model = placementSettings.selectedModel {
            worldManager.beginPlacingAsset(catalogAssetID: model.id)
        } else if let world = worldManager.pendingWorldForPlacement {
            placementSettings.resetPendingHeight()
            worldManager.beginPlacingSavedWorld(id: world.id)
        } else if case .placingAsset = worldManager.interactionState {
            worldManager.finishPlacement()
        }
        // Consume the exact guide solution captured by the Place button before another frame can
        // publish a different raycast result.
        if let confirmed=placementSettings.modelConfirmedForPlacement.popLast() { place(confirmed,in:arView) }
        worldManager.setGridConfiguration(SavedGridConfiguration(cellSizeMeters: placementSettings.gridSettings.cellSizeMeters,
                                                                  rotationStepDegrees: placementSettings.gridSettings.rotationStepDegrees,
                                                                  wasEnabled: placementSettings.placementMode == .grid))
        let isPlacingWorld = worldManager.pendingWorldForPlacement != nil
        let requiresHorizontalSurface = isPlacingWorld || (placementSettings.placementMode == .grid && placementSettings.selectedModel?.snapBehavior != .free)
        arView.nativePlacementManager.update(in: arView,
                                             isPlacementActive: placementSettings.selectedModel != nil || isPlacingWorld,
                                             alignment: requiresHorizontalSurface ? .horizontal : .any,
                                             purpose: isPlacingWorld ? .savedWorldRoot : .newAsset,
                                             models: modelsViewModel.models)
        placementSettings.isPlacementAvailable=arView.nativePlacementManager.isPlacementAvailable
        placementSettings.placementStatusMessage=placementSettings.isPlacementAvailable ? "Ready to place" : "Scan a surface"
        updateGridPreview(in: arView)
        if sceneManager.shouldPlacePendingWorld, let world=worldManager.pendingWorldForPlacement, let matrix=arView.nativePlacementManager.latestPlacementTransform {
            sceneManager.shouldPlacePendingWorld=false; place(world,at:matrix,in:arView)
        }
        if sceneManager.shouldSaveSceneToFilesystem { ScenePersistenceHelper.saveWorld(using:worldManager); sceneManager.shouldSaveSceneToFilesystem=false }
    }

    private func updateGridPreview(in arView: CustomARView) {
        guard let model = placementSettings.selectedModel,
              let target = arView.nativePlacementManager.placementTarget else {
            placementSettings.publish(nil)
            arView.gridVisuals.hidePreview()
            if placementSettings.placementMode == .free { arView.gridVisuals.hideGrid() }
            return
        }
        let rawWorld = target.worldTransform
        let rootWorld = worldManager.buildRoot?.transformMatrix(relativeTo: nil) ?? rawWorld
        guard let localMatrix = WorldTransformMath.localMatrix(world: rawWorld, rootWorld: rootWorld) else {
            placementSettings.publish(nil); arView.gridVisuals.hidePreview(); return
        }
        let rawLocal = Transform(matrix: localMatrix)
        let result: GridSnapResult
        if placementSettings.placementMode == .grid {
            guard let snapped = GridSnapResolver.resolve(rawLocalTransform: rawLocal, footprint: model.gridFootprint,
                                                         snapBehavior: model.snapBehavior, settings: placementSettings.gridSettings,
                                                         requestedQuarterTurns: placementSettings.requestedQuarterTurns) else { return }
            result = snapped
            arView.gridVisuals.showGrid(settings: placementSettings.gridSettings, root: worldManager.buildRoot,
                                        candidateWorldTransform: rawWorld, in: arView)
        } else {
            result = GridSnapResult(transform: rawLocal, effectiveFootprint: model.gridFootprint, gridCoordinateX: 0, gridCoordinateZ: 0)
            arView.gridVisuals.hideGrid()
        }
        guard let finalTransform = placementSettings.transformByApplyingPendingHeight(to: result.transform) else {
            placementSettings.publish(nil); arView.gridVisuals.hidePreview(); return
        }
        let finalResult = GridSnapResult(transform: finalTransform, effectiveFootprint: result.effectiveFootprint,
                                         gridCoordinateX: result.gridCoordinateX, gridCoordinateZ: result.gridCoordinateZ)
        let solution = PendingPlacementSolution(id: UUID(), selectedAssetID: model.id,
                                                rawWorldTransform: rawWorld, rootLocalTransform: finalTransform,
                                                targetSource: target.source, supportingObjectID: target.supportingObjectID,
                                                capturedSurfaceHeight: rawLocal.translation.y,
                                                gridCoordinateX: placementSettings.placementMode == .grid ? result.gridCoordinateX : nil,
                                                gridCoordinateZ: placementSettings.placementMode == .grid ? result.gridCoordinateZ : nil,
                                                isValid: true, capturedAt: Date())
        placementSettings.publish(solution)
        arView.gridVisuals.showPreview(result: finalResult, settings: placementSettings.gridSettings,
                                       visualBounds: model.normalizedHorizontalVisualBounds(), showsFootprint: placementSettings.placementMode == .grid,
                                       root: worldManager.buildRoot, rootWorldTransform: rootWorld, in: arView)
        placementSettings.placementStatusMessage = placementSettings.placementMode == .grid && model.snapBehavior == .free ? "Free placement asset" : "Ready to place"
    }

    private func place(_ request: ConfirmedPlacement, in arView: CustomARView) {
        let model = request.model
        let solution = request.solution
        guard solution.canConfirm(assetID: model.id),
              placementSettings.pendingPlacementSolution?.id == solution.id,
              placementSettings.selectedModel?.id == model.id,
              let source=model.modelEntity else { print("Placement Error: stale or mismatched placement for \(model.id)"); return }
        let requestedWorld = solution.rawWorldTransform
        let resolved = solution.rootLocalTransform
        let root: Entity
        if let existing=worldManager.buildRoot { root=existing }
        else {
            let anchor=AnchorEntity(world:requestedWorld); anchor.name="active-world-anchor"
            root=Entity(); root.name="build-root"; anchor.addChild(root); arView.scene.addAnchor(anchor)
            worldManager.activate(anchor:anchor,buildRoot:root); sceneManager.activeAnchor=anchor
            if placementSettings.placementMode == .grid {
                arView.gridVisuals.showGrid(settings: placementSettings.gridSettings, root: root, candidateWorldTransform: requestedWorld, in: arView)
            }
        }
        let clone=source.clone(recursive:true); clone.name="placed-\(UUID().uuidString)"; clone.transform=resolved; model.applyCatalogTransform(to:clone)
        let placementPosition=resolved.translation
        root.addChild(clone); model.normalizePlacementSize(of:clone,relativeTo:root,at:placementPosition)
        configure(clone,in:arView); worldManager.register(clone,model:model)
        placementSettings.recentlyPlaced.append(model); if placementSettings.selectedModel?.id==model.id { placementSettings.selectedModel=nil }
        placementSettings.resetPendingRotation(); placementSettings.resetPendingHeight(); arView.gridVisuals.hidePreview(); worldManager.finishPlacement()
    }

    private func place(_ world: SavedWorld, at worldTransform: simd_float4x4, in arView: CustomARView) {
        let root=Entity(); root.name="build-root"; let group=DispatchGroup()
        var restored:[(ModelEntity,Model,SavedPlacedAsset)]=[]
        for saved in world.placedAssets {
            guard let model=modelsViewModel.model(matching:saved.catalogAssetID) ?? modelsViewModel.model(matching:saved.assetFileName) else { print("World Warning: missing bundled asset \(saved.assetFileName); skipped"); continue }
            let attach:(ModelEntity)->Void = { source in let clone=source.clone(recursive:true); clone.name="placed-\(saved.id.uuidString)"; clone.transform=saved.localTransform.realityKitTransform; self.configure(clone,in:arView); root.addChild(clone); restored.append((clone,model,saved)) }
            if let source=model.modelEntity { attach(source) } else { group.enter(); model.asyncLoadModelEntity { ok,error in if ok,let source=model.modelEntity { attach(source) } else { print("World Error: \(saved.assetFileName): \(error?.localizedDescription ?? "load failed")") }; group.leave() } }
        }
        group.notify(queue:.main) {
            let anchor=AnchorEntity(world:worldTransform); anchor.name="active-world-anchor"; anchor.addChild(root); arView.scene.addAnchor(anchor)
            self.worldManager.activate(anchor:anchor,buildRoot:root); self.sceneManager.activeAnchor=anchor
            self.worldManager.setGridConfiguration(world.gridConfiguration)
            if let configuration=world.gridConfiguration {
                self.placementSettings.gridSettings=configuration.validatedSettings
                self.placementSettings.setPlacementMode(configuration.wasEnabled ? .grid : .free)
            } else { self.placementSettings.setPlacementMode(.free) }
            if self.placementSettings.placementMode == .grid {
                arView.gridVisuals.showGrid(settings: self.placementSettings.gridSettings, root: root, candidateWorldTransform: worldTransform, in: arView)
            } else { arView.gridVisuals.hideGrid() }
            for (entity,model,saved) in restored { self.worldManager.register(entity,model:model,instanceID:saved.id,displayName:saved.displayName,category:saved.category) }
            self.worldManager.finishPendingWorldPlacement(); print("World: restored \(restored.count) asset(s) under one build root")
        }
    }

    private func configure(_ entity:ModelEntity,in arView:ARView) { entity.generateCollisionShapes(recursive:true) }
}

final class SceneManager: ObservableObject {
    @Published var isPersistenceAvailable=false
    weak var arView:CustomARView?
    var activeAnchor:AnchorEntity? { didSet { isPersistenceAvailable = activeAnchor != nil } }
    var shouldSaveSceneToFilesystem=false
    var shouldPlacePendingWorld=false
    func clearCurrentScene() { activeAnchor?.removeFromParent(); activeAnchor=nil }
}
