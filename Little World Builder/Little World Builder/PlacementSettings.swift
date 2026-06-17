//
//  PlacementSettings.swift
//  AR Test
//
//  Created by Bryce on 6/07/21.
//

import SwiftUI
import RealityKit
import Combine
import ARKit

struct ModelAnchor {
    var model: Model
    var anchor: ARAnchor?
}

class PlacementSettings: ObservableObject {
    
    // When the user selects a model in BrowseView, this property is set.
    @Published var selectedModel: Model? {
        willSet(newValue) {
            print("Setting selectedModel to \(String(describing: newValue?.name))")
        }
    }
    
    //  This property retains a record of placed models in the scene. The last element in the array is the most recently placed model.
    @Published var recentlyPlaced: [Model] = []
    
    // This property will keep track of all the content that has been confirmed for placement in the scene.
    var modelConfirmedForPlacement: [ModelAnchor] = []
    
    // THis property retains the cancellable objuect for our SceneEvents.Update subscriber
    var sceneObserver: Cancellable?
}
