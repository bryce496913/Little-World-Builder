//
//  ModelsViewModel.swift
//  AR Test
//
//  Created by Bryce on 27/08/21.
//

import Combine
import Foundation

final class ModelsViewModel: ObservableObject {
    private static let appReadyUSDZSubdirectory = "App Ready USDZ"

    @Published var models: [Model] = []
    
    func fetchData() {
        let assetURLs = Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: Self.appReadyUSDZSubdirectory) ?? []
        let fallbackAssetURLs = Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: nil) ?? []
        let discoveredURLs = assetURLs.isEmpty ? fallbackAssetURLs : assetURLs
        
        let localModels = discoveredURLs
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { assetURL in
                Model(
                    assetURL: assetURL,
                    category: Self.category(for: assetURL.deletingPathExtension().lastPathComponent),
                    scaleCompensation: Self.scaleCompensation(for: assetURL.lastPathComponent)
                )
            }
        
        if localModels.isEmpty {
            print("Local Asset Error: No bundled USDZ files were found. Confirm the \(Self.appReadyUSDZSubdirectory) folder is included in the app target resources.")
        } else {
            print("Local Assets: Loaded \(localModels.count) bundled USDZ model definitions.")
        }
        
        self.models = localModels
    }
    
    func model(matching identifier: String) -> Model? {
        models.first { $0.id == identifier || $0.assetFileName == identifier || $0.name == identifier }
    }
    
    func clearModelEntitiesFromMemory() {
        for model in models {
            model.modelEntity = nil
        }
    }
    
    private static func scaleCompensation(for assetFileName: String) -> Float {
        // Local App Ready USDZ files are authored at app-ready scale unless a per-file override is added here.
        1.0
    }

    private static func category(for identifier: String) -> ModelCategory {
        let text = identifier.lowercased()
        if text.contains("water") { return .water }
        if text.contains("tree") { return .trees }
        if text.contains("manta") || text.contains("whale") { return .animals }
        if text.contains("plane") { return .misc }
        if text.contains("rock") { return .rocks }
        if text.contains("island") || text.contains("mount") { return .land }
        return .land
    }
}
