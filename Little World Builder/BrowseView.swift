//
//  BrowseView.swift
//  AR Test
//
//  Created by Bryce on 1/07/21.
//

import SwiftUI

struct BrowseView: View {
    @EnvironmentObject var modelsViewModel: ModelsViewModel
    @Binding var showBrowse: Bool
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        AppScreenHeader("Select Model", subtitle: "Local USDZ assets are loaded from App Ready USDZ.")
                        if let errorMessage = errorMessage {
                            Text(errorMessage).appText(.paragraph, color: AppTheme.highlight)
                        }
                        if modelsViewModel.models.isEmpty {
                            AppSurface(borderColor: AppTheme.highlight) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("No models found").appText(.h2)
                                    Text("No bundled USDZ files were found in App Ready USDZ.").appText(.paragraph, color: AppTheme.mutedText)
                                }
                            }
                        } else {
                            RecentsGrid(showBrowse: $showBrowse, errorMessage: $errorMessage)
                            ModelsByCategoryGrid(showBrowse: $showBrowse, errorMessage: $errorMessage)
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { self.showBrowse = false }.foregroundColor(AppTheme.text)
                }
            }
        }
    }
}

struct RecentsGrid: View {
    @EnvironmentObject var placementSettings: PlacementSettings
    @Binding var showBrowse: Bool
    @Binding var errorMessage: String?

    var body: some View {
        if !self.placementSettings.recentlyPlaced.isEmpty {
            HorizontalGrid(showBrowse: $showBrowse, errorMessage: $errorMessage, title: "Recent", items: getRecentsUniqueOrder())
        }
    }

    func getRecentsUniqueOrder() -> [Model] {
        var recentsUniqueOrderedArray: [Model] = []
        var modelNameSet: Set<String> = []
        for model in self.placementSettings.recentlyPlaced.reversed() where !modelNameSet.contains(model.name) {
            recentsUniqueOrderedArray.append(model)
            modelNameSet.insert(model.name)
        }
        return recentsUniqueOrderedArray
    }
}

struct ModelsByCategoryGrid: View {
    @EnvironmentObject var modelsViewModel: ModelsViewModel
    @Binding var showBrowse: Bool
    @Binding var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            ForEach(ModelCategory.allCases, id: \.self) { category in
                let modelsByCategory = self.modelsViewModel.models.filter { $0.category == category }
                if !modelsByCategory.isEmpty {
                    HorizontalGrid(showBrowse: $showBrowse, errorMessage: $errorMessage, title: category.label, items: modelsByCategory)
                }
            }
        }
    }
}

struct HorizontalGrid: View {
    @EnvironmentObject var placementSettings: PlacementSettings
    @Binding var showBrowse: Bool
    @Binding var errorMessage: String?
    var title: String
    var items: [Model]
    private let gridItemLayout = [GridItem(.fixed(136))]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).appText(.h2)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: gridItemLayout, spacing: 14) {
                    ForEach(items) { model in
                        ItemButton(model: model, isSelected: placementSettings.selectedModel?.id == model.id) {
                            model.asyncLoadModelEntity { completed, error in
                                if completed {
                                    self.errorMessage = nil
                                    self.placementSettings.selectedModel = model
                                    self.showBrowse = false
                                } else {
                                    self.errorMessage = "Could not load that model. Try another one."
                                    if let error = error { print("Browse Error: Unable to load \(model.name): \(error.localizedDescription)") }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct ItemButton: View {
    @ObservedObject var model: Model
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppSurface(borderColor: isSelected ? AppTheme.highlight : AppTheme.accent.opacity(0.45)) {
                VStack(spacing: 10) {
                    Image(uiImage: self.model.thumbnail)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: 92, height: 92)
                    Text(self.model.name).appText(.h3).lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(width: 112, height: 136)
            }
        }
        .buttonStyle(.plain)
    }
}
