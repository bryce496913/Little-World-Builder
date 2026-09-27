//
//  CustomARView.swift
//  AR Test
//
//  Created by Bryce on 6/07/21.
//

import RealityKit
import ARKit
import Combine

final class CustomARView: ARView {
    let nativePlacementManager = NativePlacementManager()
    let gridVisuals = GridVisualController()
    private let coachingOverlay = ARCoachingOverlayView()
    var sessionSettings: SessionSettings
    private let worldManager: WorldManager
    private let selectionOutline = SelectionOutlineController()
    private var selectionCancellable: AnyCancellable?
    private var rotationStartTransform: Transform?
    private var scaleStartTransform: Transform?
    
    var defaultConfiguration: ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        return config
    }
    
    private var peopleOcclusionCancellable: AnyCancellable?
    private var objectOcclusionCancellable: AnyCancellable?
    private var lidarDebugCancellable: AnyCancellable?
    private var multiuserCancellable: AnyCancellable?
    
    
    required init(frame frameRect: CGRect, sessionSettings: SessionSettings, worldManager: WorldManager) {
        self.sessionSettings = sessionSettings
        self.worldManager = worldManager
        
        super.init(frame: frameRect)
        
        self.configure()
        
        self.initializeSettings()
        
        self.setupSubscribers()
        
        self.enableObjectEditing()
    }
    
    required init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }

    deinit {
        selectionOutline.show(selection: nil, worldManager: nil)
        worldManager.clearSelection()
    }
    
    @objc required dynamic init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configure() {
        session.run(defaultConfiguration)
        nativePlacementManager.install(in: self)
        configureCoachingOverlay()
    }
    

    private func configureCoachingOverlay() {
        coachingOverlay.session = session
        coachingOverlay.goal = .anyPlane
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        coachingOverlay.backgroundColor = .clear
        addSubview(coachingOverlay)
        NSLayoutConstraint.activate([
            coachingOverlay.topAnchor.constraint(equalTo: topAnchor),
            coachingOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            coachingOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            coachingOverlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func initializeSettings() {
        self.updatePeopleOcclusion(isEnabled: sessionSettings.isPeopleOcclusionEnabled)
        self.updateObjectOcclusion(isEnabled: sessionSettings.isObjectOcclusionEnabled)
        self.updateLidarDebug(isEnabled: sessionSettings.isLidarDebugEnabled)
        self.updateMultiuser(isEnabled: sessionSettings.isMultiuserEnabled)
    }
    
    private func setupSubscribers() {
        selectionCancellable = worldManager.$interactionState.sink { [weak self] state in
            DispatchQueue.main.async {
                self?.rotationStartTransform = nil
                self?.scaleStartTransform = nil
                self?.selectionOutline.show(selection: state.selection, worldManager: self?.worldManager)
            }
        }
        self.peopleOcclusionCancellable = sessionSettings.$isPeopleOcclusionEnabled.sink { [weak self] isEnabled in
            self?.updatePeopleOcclusion(isEnabled: isEnabled)
        }
        
        self.objectOcclusionCancellable = sessionSettings.$isObjectOcclusionEnabled.sink { [weak self] isEnabled in
            self?.updateObjectOcclusion(isEnabled: isEnabled)
        }
        
        self.lidarDebugCancellable = sessionSettings.$isLidarDebugEnabled.sink { [weak self] isEnabled in
            self?.updateLidarDebug(isEnabled: isEnabled)
        }
        
        self.multiuserCancellable = sessionSettings.$isMultiuserEnabled.sink { [weak self] isEnabled in
            self?.updateMultiuser(isEnabled: isEnabled)
        }
    }
            
    private func updatePeopleOcclusion(isEnabled: Bool) {
        print("\(#file): isPeopleOcclusionEnabled is now \(isEnabled)")
        
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) else {
            return
        }
        
        guard let configuration = self.session.configuration as? ARWorldTrackingConfiguration else {
            return
        }
        
        if isEnabled {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        } else {
            configuration.frameSemantics.remove(.personSegmentationWithDepth)
        }
        
        self.session.run(configuration)
    }
    
    private func updateObjectOcclusion(isEnabled: Bool) {
        print("\(#file): isObjectOcclusionEnabled is now \(isEnabled)")
        
        if isEnabled {
            self.environment.sceneUnderstanding.options.insert(.occlusion)
        } else {
            self.environment.sceneUnderstanding.options.remove(.occlusion)
        }
    }
    
    private func updateLidarDebug(isEnabled: Bool) {
        print("\(#file): isLidarDebugEnabled is now \(isEnabled)")
        
        if isEnabled {
            self.debugOptions.insert(.showSceneUnderstanding)
        } else {
            self.debugOptions.remove(.showSceneUnderstanding)
        }
    }
    
    private func updateMultiuser(isEnabled: Bool) {
        print("\(#file): isMultiuserEnabled is now \(isEnabled)")

        guard let configuration = self.session.configuration as? ARWorldTrackingConfiguration else {
            return
        }

        configuration.isCollaborationEnabled = isEnabled
        self.session.run(configuration)
    }
}

// MARK: - Placed-object selection and editing

extension CustomARView {
    func enableObjectEditing() {
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleSelectionTap(recognizer:))))
        addGestureRecognizer(UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(recognizer:))))
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handleScale(recognizer:))))
    }

    @objc private func handleSelectionTap(recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard case .browse = worldManager.interactionState else {
            if case .editing = worldManager.interactionState {} else { return }
            return resolveSelection(at: recognizer.location(in: self))
        }
        resolveSelection(at: recognizer.location(in: self))
    }

    private func resolveSelection(at location: CGPoint) {
        guard let hit = hitTest(location, query: .nearest).first,
              let resolved = PlacedObjectResolver.registeredRoot(from: hit.entity, buildRoot: worldManager.buildRoot),
              worldManager.entity(for: resolved.component.instanceID) === resolved.entity else {
            worldManager.clearSelection(); return
        }
        worldManager.select(instanceID: resolved.component.instanceID)
    }

    @objc private func handleRotation(recognizer: UIRotationGestureRecognizer) {
        guard let entity = selectedRoot() else { rotationStartTransform = nil; return }
        if recognizer.state == .began { rotationStartTransform = entity.transform }
        guard let start = rotationStartTransform else { return }
        entity.transform = SelectionTransformEditor.rotated(start, radians: Float(recognizer.rotation))
        selectionOutline.refresh()
        if recognizer.state == .ended || recognizer.state == .cancelled { rotationStartTransform = nil }
    }

    @objc private func handleScale(recognizer: UIPinchGestureRecognizer) {
        guard let entity = selectedRoot() else { scaleStartTransform = nil; return }
        if recognizer.state == .began { scaleStartTransform = entity.transform }
        guard let start = scaleStartTransform else { return }
        entity.transform = SelectionTransformEditor.scaled(start, factor: Float(recognizer.scale))
        selectionOutline.refresh()
        if recognizer.state == .ended || recognizer.state == .cancelled { scaleStartTransform = nil }
    }

    private func selectedRoot() -> ModelEntity? {
        guard let id = worldManager.interactionState.selection?.instanceID,
              let entity = worldManager.entity(for: id),
              worldManager.belongsToActiveBuildRoot(entity) else { return nil }
        return entity
    }

}

enum SelectionTransformEditor {
    static func rotated(_ transform: Transform, radians: Float) -> Transform {
        var result = transform
        result.rotation = simd_quatf(angle: radians, axis: [0, 1, 0]) * transform.rotation
        return result
    }

    static func scaled(_ transform: Transform, factor: Float) -> Transform {
        var result = transform
        let safeFactor = min(max(factor, 0.1), 10)
        result.scale = transform.scale * safeFactor
        return result
    }
}

final class SelectionOutlineController {
    private let outline = Entity()
    private weak var selectedRoot: Entity?

    init() {
        outline.name = "selection-outline"
        outline.components.set(NonSelectableComponent())
    }

    func show(selection: PlacedObjectSelection?, worldManager: WorldManager?) {
        outline.removeFromParent(); selectedRoot = nil
        guard let selection, let root = worldManager?.entity(for: selection.instanceID) else { return }
        selectedRoot = root
        rebuild(for: root)
        root.addChild(outline)
    }

    func refresh() {
        guard let selectedRoot else { outline.removeFromParent(); return }
        rebuild(for: selectedRoot)
    }

    private func rebuild(for root: Entity) {
        for child in outline.children { child.removeFromParent() }
        let bounds = root.visualBounds(relativeTo: root)
        let size = bounds.extents
        guard size.x.isFinite, size.y.isFinite, size.z.isFinite, min(size.x, min(size.y, size.z)) > 0 else { return }
        let thickness = max(max(size.x, max(size.y, size.z)) * 0.008, 0.001)
        let material = UnlitMaterial(color: UIColor.systemYellow.withAlphaComponent(0.9))
        func edge(_ dimensions: SIMD3<Float>, _ position: SIMD3<Float>) {
            let entity = ModelEntity(mesh: .generateBox(size: dimensions), materials: [material])
            entity.position = position; entity.components.set(NonSelectableComponent()); outline.addChild(entity)
        }
        for y in [-size.y / 2, size.y / 2] { for z in [-size.z / 2, size.z / 2] { edge([size.x, thickness, thickness], [0, y, z]) } }
        for x in [-size.x / 2, size.x / 2] { for z in [-size.z / 2, size.z / 2] { edge([thickness, size.y, thickness], [x, 0, z]) } }
        for x in [-size.x / 2, size.x / 2] { for y in [-size.y / 2, size.y / 2] { edge([thickness, thickness, size.z], [x, y, 0]) } }
        outline.position = bounds.center
        outline.transform.rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        outline.scale = .one
    }
}
