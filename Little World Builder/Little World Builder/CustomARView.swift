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
    private let coachingOverlay = ARCoachingOverlayView()
    var sessionSettings: SessionSettings
    var modelDeletionManager: ModelDeletionManager
    
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
    
    
    required init(frame frameRect: CGRect, sessionSettings: SessionSettings, modelDeletionManager: ModelDeletionManager) {
        self.sessionSettings = sessionSettings
        self.modelDeletionManager = modelDeletionManager
        
        super.init(frame: frameRect)
        
        self.configure()
        
        self.initializeSettings()
        
        self.setupSubscribers()
        
        self.enableObjectDeletion()
    }
    
    required init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
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


// MARK: - Object Deletion Methods

extension CustomARView {
    func enableObjectDeletion() {
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(recognizer:)))
        self.addGestureRecognizer(longPressGesture)
    }
    
    @objc func handleLongPress(recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)
        
        if let entity = self.entity(at: location) as? ModelEntity {
            modelDeletionManager.entitySelectedForDeletion = entity
        }
    }
}
