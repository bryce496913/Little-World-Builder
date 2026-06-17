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
        
        arView.nativePlacementManager.update(in: arView, isPlacementActive: self.placementSettings.selectedModel != nil)
        self.placementSettings.isPlacementAvailable = arView.nativePlacementManager.isPlacementAvailable
        self.placementSettings.placementStatusMessage = arView.nativePlacementManager.isPlacementAvailable ? "Ready to place" : "Scan a surface"
        
        // Add model(s) to scene if confirmed for placement.
        // Keep this after the native placement update so a Place tap uses the freshest
        // center-screen raycast transform while the selected model is still active.
        if let modelAnchor = self.placementSettings.modelConfirmedForPlacement.popLast() {
            self.placeConfirmed(modelAnchor, in: arView)
        }
    }
    
    private func placeConfirmed(_ modelAnchor: ModelAnchor, in arView: CustomARView) {
        guard let modelEntity = modelAnchor.model.modelEntity else {
            print("Placement Error: Model entity for \(modelAnchor.model.name) is not loaded from \(modelAnchor.model.assetURL.path).")
            return
        }

        if let anchor = modelAnchor.anchor {
            // Anchor is being loaded from persisted scene.
            self.place(modelEntity, for: modelAnchor.model, anchor: anchor, modelTransform: modelAnchor.modelTransform, in: arView)
            return
        }

        guard let anchorEntity = arView.nativePlacementManager.makeAnchorEntity() else {
            print("Placement Error: No valid surface transform is available for \(modelAnchor.model.name).")
            return
        }

        anchorEntity.name = anchorNamePrefix + modelAnchor.model.id
        print("Placement: placing \(modelAnchor.model.name) from \(modelAnchor.model.assetURL.lastPathComponent).")
        self.place(modelEntity, for: modelAnchor.model, anchorEntity: anchorEntity, modelTransform: nil, in: arView)
        self.placementSettings.recentlyPlaced.append(modelAnchor.model)

        if self.placementSettings.selectedModel?.id == modelAnchor.model.id {
            self.placementSettings.selectedModel = nil
        }
    }

    private func place(_ modelEntity: ModelEntity, for model: Model, anchor: ARAnchor, modelTransform: Transform?, in arView: ARView) {
        let anchorEntity = AnchorEntity(world: anchor.transform)
        anchorEntity.name = anchor.name ?? anchorNamePrefix + model.id
        self.place(modelEntity, for: model, anchorEntity: anchorEntity, modelTransform: modelTransform, in: arView)
    }

    private func place(_ modelEntity: ModelEntity, for model: Model, anchorEntity: AnchorEntity, modelTransform: Transform?, in arView: ARView) {
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
        
        //3. Add clonedEntity to the provided native anchorEntity.
        anchorEntity.addChild(clonedEntity)
        
        //4. Add the anchorEntity to the arView.scene
        arView.scene.addAnchor(anchorEntity)
        
        self.sceneManager.anchorEntities.append(anchorEntity)
        
        print("Placement: added \(model.name) to scene. Scene anchor count: \(arView.scene.anchors.count).")
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
