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
    case water = "Water"
    case trees = "Trees"
    case land = "Land"
    case rocks = "Rocks"
    case animals = "Animals"
    case buildings = "Buildings"
    case misc = "Misc"
    
    var label: String {
        rawValue
    }
}


final class Model: ObservableObject, Identifiable {
    let id: String
    let name: String
    let category: ModelCategory
    let assetURL: URL
    let assetFileName: String
    @Published var thumbnail: UIImage
    var modelEntity: ModelEntity?
    let scaleCompensation: Float
    
    private var cancellable: AnyCancellable?
    
    init(assetURL: URL, category: ModelCategory, scaleCompensation: Float = 1.0) {
        self.assetURL = assetURL
        self.assetFileName = assetURL.lastPathComponent
        self.id = assetURL.deletingPathExtension().lastPathComponent
        self.name = Self.displayName(for: self.id)
        self.category = category
        self.thumbnail = Self.loadThumbnail(for: self.id)
        self.scaleCompensation = scaleCompensation
    }
    
    func asyncLoadModelEntity(handler: @escaping (_ completed: Bool, _ error: Error?) -> Void) {
        cancellable = ModelEntity.loadModelAsync(contentsOf: assetURL)
            .sink(receiveCompletion: { loadCompletion in
                switch loadCompletion {
                case .failure(let error):
                    print("Model Error: Unable to load modelEntity for \(self.name) from \(self.assetFileName): \(error.localizedDescription)")
                    handler(false, error)
                case .finished:
                    break
                }
            }, receiveValue: { modelEntity in
                self.modelEntity = modelEntity
                self.modelEntity?.scale *= self.scaleCompensation
                handler(true, nil)
                print("modelEntity for \(self.name) has been loaded from bundled asset \(self.assetFileName).")
            })
    }
    
    private static func displayName(for identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
    
    private static func loadThumbnail(for identifier: String) -> UIImage {
        let possibleNames = [identifier, displayName(for: identifier)]
        let possibleExtensions = ["png", "jpg", "jpeg"]

        for name in possibleNames {
            if let image = UIImage(named: name) {
                return image
            }

            for fileExtension in possibleExtensions {
                if let thumbnailURL = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: "Thumbnails"),
                   let image = UIImage(contentsOfFile: thumbnailURL.path) {
                    return image
                }
            }
        }

        print("Thumbnail Error: Unable to load thumbnail for \(identifier). Confirm a matching image exists in the Thumbnails bundled resource folder.")
        return UIImage(systemName: "photo") ?? UIImage()
    }
}
