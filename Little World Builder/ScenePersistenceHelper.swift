//
//  ScenePersistenceHelper.swift
//  Little World Builder
//
//  Created by Bryce on 17/02/22.
//

import Foundation
import RealityKit
import ARKit

final class ScenePersistenceHelper {
    static func saveScene(for arView: CustomARView, at persistenceUrl: URL) {
        print("Save scene to local filesystem.")
        
        // 1. Get current worldMap from arView.session
        arView.session.getCurrentWorldMap { worldMap, error in
            
            // 2. Safely unwrap worldMap
            guard let map = worldMap else {
                print("Persistence Error: Unable to get worldMap: \(error?.localizedDescription ?? "No world map returned.")")
                return
            }
            
            // 3. Archive data and write to filesystem
            do {
                let sceneData = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                
                try sceneData.write(to: persistenceUrl, options: [.atomic])
                print("Persistence: Scene saved to \(persistenceUrl.path).")
            } catch {
                print("Persistence Error: Can't save scene to local filesystem: \(error.localizedDescription)")
            }
        }
    }
    
    static func loadScene(for arView: CustomARView, with scenePersistenceData: Data) {
        print("Load scene from local filesystem.")
        
        // 1, Unarchive the scenePersistenceData and retrieve ARWorldMap
        let worldMap: ARWorldMap

        do {
            guard let unarchivedWorldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: scenePersistenceData) else {
                print("Persistence Error: No ARWorldMap in archive.")
                return
            }

            worldMap = unarchivedWorldMap
        } catch {
            print("Persistence Error: Unable to unarchive ARWorldMap from scenePersistenceData: \(error.localizedDescription)")
            return
        }
        
        // 2. Reset configuration and load worldMap as initialWorldMap
        let newConfig = arView.defaultConfiguration
        newConfig.initialWorldMap = worldMap
        arView.session.run(newConfig, options: [.resetTracking, .removeExistingAnchors])
    }
}
