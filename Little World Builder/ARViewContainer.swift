import SwiftUI
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject var placementSettings: PlacementSettings
    @EnvironmentObject var sessionSettings: SessionSettings
    @EnvironmentObject var sceneManager: SceneManager
    @EnvironmentObject var modelsViewModel: ModelsViewModel
    @EnvironmentObject var modelDeletionManager: ModelDeletionManager
    @EnvironmentObject var worldManager: WorldManager

    func makeUIView(context: Context) -> CustomARView {
        sceneManager.clearCurrentScene()
        worldManager.resetActiveWorld()
        let view = CustomARView(frame:.zero,sessionSettings:sessionSettings,modelDeletionManager:modelDeletionManager)
        sceneManager.arView=view
        placementSettings.sceneObserver=view.scene.subscribe(to:SceneEvents.Update.self) { _ in self.updateScene(for:view) }
        return view
    }
    func updateUIView(_ uiView: CustomARView, context: Context) {}

    private func updateScene(for arView: CustomARView) {
        worldManager.setGridConfiguration(SavedGridConfiguration(cellSizeMeters: placementSettings.gridSettings.cellSizeMeters,
                                                                  rotationStepDegrees: placementSettings.gridSettings.rotationStepDegrees,
                                                                  wasEnabled: placementSettings.placementMode == .grid))
        arView.nativePlacementManager.update(in:arView,isPlacementActive:placementSettings.selectedModel != nil || worldManager.pendingWorldForPlacement != nil)
        placementSettings.isPlacementAvailable=arView.nativePlacementManager.isPlacementAvailable
        placementSettings.placementStatusMessage=placementSettings.isPlacementAvailable ? "Ready to place" : "Scan a surface"
        updateGridPreview(in: arView)
        if sceneManager.shouldPlacePendingWorld, let world=worldManager.pendingWorldForPlacement, let matrix=arView.nativePlacementManager.latestPlacementTransform {
            sceneManager.shouldPlacePendingWorld=false; place(world,at:matrix,in:arView)
        }
        if let confirmed=placementSettings.modelConfirmedForPlacement.popLast() { place(confirmed.model,rawWorldTransform:confirmed.anchor?.transform,resolvedTransform:confirmed.modelTransform,in:arView) }
        if sceneManager.shouldSaveSceneToFilesystem { ScenePersistenceHelper.saveWorld(using:worldManager); sceneManager.shouldSaveSceneToFilesystem=false }
    }

    private func updateGridPreview(in arView: CustomARView) {
        guard let model = placementSettings.selectedModel,
              let rawWorld = arView.nativePlacementManager.latestPlacementTransform else {
            placementSettings.latestResolvedTransform = nil
            placementSettings.latestRawWorldTransform = nil
            arView.gridVisuals.hidePreview()
            if placementSettings.placementMode == .free { arView.gridVisuals.hideGrid() }
            return
        }
        let rootWorld = worldManager.buildRoot?.transformMatrix(relativeTo: nil) ?? rawWorld
        guard let localMatrix = WorldTransformMath.localMatrix(world: rawWorld, rootWorld: rootWorld) else {
            placementSettings.latestResolvedTransform = nil; arView.gridVisuals.hidePreview(); return
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
        placementSettings.latestResolvedTransform = result.transform
        placementSettings.latestRawWorldTransform = rawWorld
        arView.gridVisuals.showPreview(result: result, settings: placementSettings.gridSettings,
                                       root: worldManager.buildRoot, rootWorldTransform: rootWorld, in: arView)
        placementSettings.placementStatusMessage = placementSettings.placementMode == .grid && model.snapBehavior == .free ? "Free placement asset" : "Ready to place"
    }

    private func place(_ model: Model, rawWorldTransform: simd_float4x4?, resolvedTransform: Transform?, in arView: CustomARView) {
        guard let source=model.modelEntity, let requestedWorld=rawWorldTransform,
              let resolved = resolvedTransform else { print("Placement Error: model or surface unavailable for \(model.id)"); return }
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
        placementSettings.resetPendingRotation(); arView.gridVisuals.hidePreview()
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
                self.placementSettings.placementMode=configuration.wasEnabled ? .grid : .free
            } else { self.placementSettings.placementMode = .free }
            if self.placementSettings.placementMode == .grid {
                arView.gridVisuals.showGrid(settings: self.placementSettings.gridSettings, root: root, candidateWorldTransform: worldTransform, in: arView)
            } else { arView.gridVisuals.hideGrid() }
            for (entity,model,saved) in restored { self.worldManager.register(entity,model:model,instanceID:saved.id,displayName:saved.displayName,category:saved.category) }
            self.worldManager.finishPendingWorldPlacement(); print("World: restored \(restored.count) asset(s) under one build root")
        }
    }

    private func configure(_ entity:ModelEntity,in arView:ARView) { entity.generateCollisionShapes(recursive:true); arView.installGestures([.translation,.rotation,.scale],for:entity) }
}

final class SceneManager: ObservableObject {
    @Published var isPersistenceAvailable=false
    weak var arView:CustomARView?
    var activeAnchor:AnchorEntity? { didSet { isPersistenceAvailable = activeAnchor != nil } }
    var shouldSaveSceneToFilesystem=false
    var shouldPlacePendingWorld=false
    func clearCurrentScene() { activeAnchor?.removeFromParent(); activeAnchor=nil }
}
