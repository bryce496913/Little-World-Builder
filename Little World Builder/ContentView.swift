//
//  ContentView.swift
//  Little World Builder
//
//  Created by Bryce on 3/11/21.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var placementSettings: PlacementSettings
    @EnvironmentObject var modelsViewModel: ModelsViewModel
    @EnvironmentObject var modelDeletionManager: ModelDeletionManager
    @EnvironmentObject var sceneManager: SceneManager
    @EnvironmentObject var worldManager: WorldManager
    @Environment(\.dismiss) private var dismiss

    var loadSavedWorldOnAppear = false

    @State private var selectedControlMode: Int = 0
    @State private var isControlsVisible: Bool = true
    @State private var showBrowse: Bool = false
    @State private var didRequestSavedWorldLoad = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ARViewContainer()

            VStack {
                ARTopBar(onMenu: { dismiss() })
                Spacer()
            }

            if self.placementSettings.selectedModel != nil || self.worldManager.pendingWorldForPlacement != nil {
                PlacementView()
            } else if self.modelDeletionManager.entitySelectedForDeletion != nil {
                DeletionView()
            } else {
                ControlView(selectControlMode: $selectedControlMode, isControlsVisible: $isControlsVisible, showBrowse: $showBrowse)
            }
        }
        .background(AppTheme.background)
        .edgesIgnoringSafeArea(.all)
        .navigationBarHidden(true)
        .onAppear {
            self.modelsViewModel.fetchData()
            if loadSavedWorldOnAppear && !didRequestSavedWorldLoad {
                self.didRequestSavedWorldLoad = true
            }
        }
    }
}

struct ARTopBar: View {
    let onMenu: () -> Void

    var body: some View {
        HStack {
            Button(action: onMenu) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    Text("Menu").appText(.h3)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(AppTheme.surface.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.accent, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Create World").appText(.h1)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(AppTheme.surface.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.top, 48)
        .padding(.horizontal, 16)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(PlacementSettings())
            .environmentObject(SessionSettings())
            .environmentObject(SceneManager())
            .environmentObject(ModelsViewModel())
            .environmentObject(ModelDeletionManager())
            .environmentObject(WorldManager())
    }
}
