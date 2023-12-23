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
    case Land
    case Island
    case Water
    case Trees
    case Creatures
    case Vehicles
    
    var label: String {
        get {
            switch self {
            case .Land:
                return "Land"
            case .Island:
                return "Island"
            case .Water:
                return "Water"
            case .Trees:
                return "Trees"
            case .Creatures:
                return "Creatures"
            case .Vehicles:
                return "Vehicles"
            }
        }
    }
}


class Model: ObservableObject, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var category: ModelCategory
    @Published var thumbnail: UIImage
    var modelEntity: ModelEntity?
    var scaleCompensation: Float
    
    private var cancellable: AnyCancellable?
    
    init(name: String, category: ModelCategory, scaleCompensation: Float = 1.0) {
        self.name = name
        self.category = category
        self.thumbnail = UIImage(systemName: "photo")!
        self.scaleCompensation = scaleCompensation
        
        FirebaseStorageHelper.asyncDownloadToFilesystem(relativePath: "thumbnails/\(self.name).png") { localUrl in
            do {
                let imageData = try Data(contentsOf: localUrl)
                self.thumbnail = UIImage(data: imageData) ?? self.thumbnail
            } catch {
                print("Error loading image: \(error.localizedDescription)")
            }
        }
    }
    
    func asyncLoadModelEntity(handler: @escaping (_ completed: Bool, _ error: Error?) -> Void) {
        FirebaseStorageHelper.asyncDownloadToFilesystem(relativePath: "models/\(self.name).usdz") { localUrl in
            self.cancellable = ModelEntity.loadModelAsync(contentsOf: localUrl)
                .sink(receiveCompletion: { loadCompletion in
                    
                    switch loadCompletion {
                    case .failure(let error): print("Unable to load modelEntity for \(self.name).Error\(error.localizedDescription)")
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

