//
//  Model.swift
//  AR Test
//
//  Created by Bryce on 1/07/21.
//

import SwiftUI
import RealityKit
import Combine

enum ModelCategory: String, CaseIterable {
    case land = "Land"
    case island = "Island"
    case water = "Water"
    case trees = "Trees"
    case creatures = "Creatures"
    case vehicles = "Vehicles"
    
    var label: String {
        rawValue
    }
}


final class Model: ObservableObject, Identifiable {
    let id: String = UUID().uuidString
    let name: String
    let category: ModelCategory
    @Published var thumbnail: UIImage
    var modelEntity: ModelEntity?
    let scaleCompensation: Float
    
    private var cancellable: AnyCancellable?
    
    init(name: String, category: ModelCategory, scaleCompensation: Float = 1.0) {
        self.name = name
        self.category = category
        self.thumbnail = UIImage(systemName: "photo") ?? UIImage()
        self.scaleCompensation = scaleCompensation
        
        FirebaseStorageHelper.asyncDownloadToFilesystem(relativePath: "thumbnails/\(self.name).png") { localUrl in
            do {
                let imageData = try Data(contentsOf: localUrl)
                self.thumbnail = UIImage(data: imageData) ?? self.thumbnail
            } catch {
                print("Thumbnail Error: Unable to load image for \(self.name): \(error.localizedDescription)")
            }
        }
    }
    
    func asyncLoadModelEntity(handler: @escaping (_ completed: Bool, _ error: Error?) -> Void) {
        FirebaseStorageHelper.asyncDownloadToFilesystem(relativePath: "models/\(self.name).usdz") { localUrl in
            self.cancellable = ModelEntity.loadModelAsync(contentsOf: localUrl)
                .sink(receiveCompletion: { loadCompletion in
                    
                    switch loadCompletion {
                    case .failure(let error):
                        print("Model Error: Unable to load modelEntity for \(self.name): \(error.localizedDescription)")
                        handler(false, error)
                    case .finished:
                        break
                    }
                    
                }, receiveValue: { modelEntity in
                    
                    self.modelEntity = modelEntity
                    self.modelEntity?.scale *= self.scaleCompensation
                    
                    handler(true, nil)
                    
                    print("modelEntity for \(self.name) has been loaded.")
                    
                })
        }
    }
}
