//
//  PlacementSettings.swift
//  AR Test
//
//  Created by Bryce on 6/07/21.
//

import Combine
import ARKit
import RealityKit

struct ModelAnchor {
    var model: Model
    var anchor: ARAnchor?
    var modelTransform: Transform? = nil
}

final class PlacementSettings: ObservableObject {

    // When the user selects a model in BrowseView, this property is set.
    @Published var selectedModel: Model? {
        willSet(newValue) {
            print("Setting selectedModel to \(String(describing: newValue?.name))")
        }
    }

    @Published var isPlacementAvailable: Bool = false
    @Published var placementStatusMessage: String = "Scan a surface"

    //  This property retains a record of placed models in the scene. The last element in the array is the most recently placed model.
    @Published var recentlyPlaced: [Model] = []

    // This property will keep track of all the content that has been confirmed for placement in the scene.
    @Published var shouldPlaceIslandRoot: Bool = false

    var modelConfirmedForPlacement: [ModelAnchor] = []

    // This property retains the cancellable object for our SceneEvents.Update subscriber.
    var sceneObserver: Cancellable?
}
