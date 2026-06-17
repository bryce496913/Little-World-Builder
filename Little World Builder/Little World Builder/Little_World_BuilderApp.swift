//
//  Little_World_BuilderApp.swift
//  Little World Builder
//
//  Created by Bryce on 3/11/21.
//

import SwiftUI
import Firebase

@main
struct Little_World_BuilderApp: App {
    @StateObject var placementSettings = PlacementSettings()
    @StateObject var sessionSettings = SessionSettings()
    @StateObject var sceneManager = SceneManager()
    @StateObject var modelsViewModel = ModelsViewModel()
    @StateObject var modelDeletionManager = ModelDeletionManager()
    
    init() {
        FirebaseApp.configure()
        
        // Anonymous authentication with Firebase
        Auth.auth().signInAnonymously { authResult, error in
            guard let user = authResult?.user else {
            print("FAILED: Anonymous Authenticationwith Firebase.")
                return
            }
            
            let uid = user.uid
            print("Firebase: Anonymous user authentication with uid: \(uid).")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(placementSettings)
                .environmentObject(sessionSettings)
                .environmentObject(sceneManager)
                .environmentObject(modelsViewModel)
                .environmentObject(modelDeletionManager)
        }
    }
}
