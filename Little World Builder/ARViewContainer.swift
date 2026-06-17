//
//  ARViewContainer.swift
//  AR Test
//
//  Created by Bryce on 3/11/21.
//

import SwiftUI
import RealityKit
import ARKit

let anchorNamePrefix = "model-"

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject var placementSettings: PlacementSettings
    @EnvironmentObject var sessionSettings: SessionSettings
    @EnvironmentObject var sceneManager: SceneManager
    @EnvironmentObject var modelsViewModel: ModelsViewModel
    @EnvironmentObject var modelDeletionManager: ModelDeletionManager
    
    func makeUIView(context: Context) -> CustomARView {
        let arView = CustomARView(frame: .zero, sessionSettings: sessionSettings, modelDeletionManager: modelDeletionManager)
        
        arView.session.delegate = context.coordinator
        
        // Subscribe to SceneEvents.Update
        self.placementSettings.sceneObserver = arView.scene.subscribe(to: SceneEvents.Update.self, { _ in
            self.updateScene(for: arView)
            self.updatePersistenceAvailability(for: arView)
            self.handlePersistence(for: arView)
        })
        
        return arView
    }
    
    func updateUIView(_ uiView: CustomARView, context: Context) {}
    
    private func updateScene(for arView: CustomARView) {
        
        // Only display focusEntity when the user has selected a model for placement
        arView.focusEntity?.isEnabled = self.placementSettings.selectedModel != nil
        
        // Add model(s) to scene if confirmed for placement
        if let modelAnchor = self.placementSettings.modelConfirmedForPlacement.popLast(), let modelEntity = modelAnchor.model.modelEntity {
            
            if let anchor = modelAnchor.anchor {
                // Anchor is being loaded from persisted scene
                self.place(modelEntity, for: modelAnchor.model, anchor: anchor, modelTransform: modelAnchor.modelTransform, in: arView)
            } else if let transform = getTransformForPlacement(in: arView) {
                // Anchor needs to be created for placement
                let anchorName = anchorNamePrefix + modelAnchor.model.id
                let anchor = ARAnchor(name: anchorName, transform: transform)
                
                self.place(modelEntity, for: modelAnchor.model, anchor: anchor, modelTransform: nil, in: arView)
                
                arView.session.add(anchor: anchor)
                
                self.placementSettings.recentlyPlaced.append(modelAnchor.model)
            }
        }
    }
    
    private func place(_ modelEntity: ModelEntity, for model: Model, anchor: ARAnchor, modelTransform: Transform?, in arView: ARView) {
        //1. Clone modelEntity. This creates an identical copy of modelEntity and references the same model. This also allows us to have multiple models of the same asset in our scene.
        let clonedEntity = modelEntity.clone(recursive: true)
        clonedEntity.name = model.id
        clonedEntity.components.set(LocalModelComponent(modelIdentifier: model.id, assetFileName: model.assetFileName))
        if let modelTransform = modelTransform {
            clonedEntity.transform = modelTransform
        }
        
        //2. Enable translation and rotation gestures.
        clonedEntity.generateCollisionShapes(recursive: true)
        arView.installGestures([.translation, .rotation, .scale], for: clonedEntity)
        
        //3. Create an anchorEntity and add clonedEntity to the anchorEntity.
        let anchorEntity = AnchorEntity(plane: .any)
        anchorEntity.addChild(clonedEntity)
        
        anchorEntity.anchoring = AnchoringComponent(anchor)
        
        //4. Add the anchorEntity to the arView.scene
        arView.scene.addAnchor(anchorEntity)
        
        self.sceneManager.anchorEntities.append(anchorEntity)
        
        print("Added modelEntity to scene")
    }
    
    private func getTransformForPlacement(in arView: ARView) -> simd_float4x4? {
        guard let query = arView.makeRaycastQuery(from: arView.center, allowing: .estimatedPlane, alignment: .any) else {
            return nil
        }
        guard let raycastResult = arView.session.raycast(query).first else { return nil }
        
        return raycastResult.worldTransform
    }
}

// MARK: - Persistence

class SceneManager: ObservableObject {
    @Published var isPersistenceAvailable: Bool = false
    @Published var anchorEntities: [AnchorEntity] = [] // Keeps track of anchorEntities (w/ modelEntities) in the scene
    
    var shouldSaveSceneToFilesystem: Bool = false // Flag to trigger save scene to filesystem function
    var shouldLoadSceneFromFilesystem: Bool = false // Flag to trigger load scene from filesystem function
    
    lazy var persistenceUrl: URL = {
        do {
            return try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("SavedScene.json")
        } catch {
            fatalError("Unable to get persistenceUrl: \(error.localizedDescription)")
        }
    }()
    
    var scenePersistenceData: Data? {
        return try? Data(contentsOf: persistenceUrl)
    }

    func deleteSavedScene() {
        guard FileManager.default.fileExists(atPath: persistenceUrl.path) else { return }
        do {
            try FileManager.default.removeItem(at: persistenceUrl)
            print("Persistence: Deleted saved scene at \(persistenceUrl.path).")
        } catch {
            print("Persistence Error: Unable to delete saved scene: \(error.localizedDescription)")
        }
    }

    func clearCurrentScene() {
        for anchorEntity in anchorEntities {
            print("Removing anchorEntity with id: \(String(describing: anchorEntity.anchorIdentifier))")
            anchorEntity.removeFromParent()
        }
        anchorEntities.removeAll(keepingCapacity: true)
    }
}

extension ARViewContainer {
    private func updatePersistenceAvailability(for arView: ARView) {
        guard let currentFrame = arView.session.currentFrame else {
            print("ARFrame not available.")
            return
        }
        
        switch currentFrame.worldMappingStatus {
        case .mapped, .extending:
            self.sceneManager.isPersistenceAvailable = !self.sceneManager.anchorEntities.isEmpty
        default:
            self.sceneManager.isPersistenceAvailable = false
        }
    }
    
    private func handlePersistence(for arView: CustomARView) {
        if self.sceneManager.shouldSaveSceneToFilesystem {
            ScenePersistenceHelper.saveScene(for: arView, sceneManager: self.sceneManager, at: self.sceneManager.persistenceUrl)
            
            self.sceneManager.shouldSaveSceneToFilesystem = false
        } else if self.sceneManager.shouldLoadSceneFromFilesystem {
            
            guard let scenePersistenceData = self.sceneManager.scenePersistenceData else {
                print("Persistence Error: Unable to retrieve scenePersistenceData. Canceled loadScene operation.")
                
                self.sceneManager.shouldLoadSceneFromFilesystem = false
                
                return
            }
            
            self.modelsViewModel.clearModelEntitiesFromMemory()
            
            self.sceneManager.anchorEntities.removeAll(keepingCapacity: true)

            ScenePersistenceHelper.loadScene(from: scenePersistenceData, modelsViewModel: self.modelsViewModel, placementSettings: self.placementSettings)
                        
            self.sceneManager.shouldLoadSceneFromFilesystem = false
        }
    }
}

// MARK: - ARSessionDelegate + Coordinator

extension ARViewContainer {
    class Coordinator: NSObject, ARSessionDelegate {
        var parent: ARViewContainer
        
        init(_ parent: ARViewContainer) {
            self.parent = parent
        }
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                if let anchorName = anchor.name, anchorName.hasPrefix(anchorNamePrefix) {
                    let modelName = String(anchorName.dropFirst(anchorNamePrefix.count))
                    
                    print("ARSession: didAdd anchor for modelName: \(modelName)")
                    
                    guard let model = self.parent.modelsViewModel.model(matching: modelName) else {
                        print("Persistence Error: Unable to retrieve model named \(modelName) from modelsViewModel.")
                        return
                    }
                    
                    if model.modelEntity == nil {
                        model.asyncLoadModelEntity { completed, error in
                            if completed {
                                let modelAnchor = ModelAnchor(model: model, anchor: anchor)
                                self.parent.placementSettings.modelConfirmedForPlacement.append(modelAnchor)
                                print("Adding modelAnchor with name: \(model.name)")
                            } else if let error = error {
                                print("Persistence Error: Unable to load model \(model.name): \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
}
