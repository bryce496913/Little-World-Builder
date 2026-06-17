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
    
    @State private var selectedControlMode: Int = 0
    @State private var isControlsVisible: Bool = true
    @State private var showBrowse: Bool = false
    @State private var showSettings: Bool = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            
            ARViewContainer()
            
            if self.placementSettings.selectedModel != nil {
                PlacementView()
            } else if self.modelDeletionManager.entitySelectedForDeletion != nil {
                DeletionView()
            } else {
                ControlView(selectControlMode: $selectedControlMode, isControlsVisible: $isControlsVisible, showBrowse: $showBrowse, showSettings: $showSettings)
            }
        }
        .edgesIgnoringSafeArea(/*@START_MENU_TOKEN@*/.all/*@END_MENU_TOKEN@*/)
        .onAppear() {
            self.modelsViewModel.fetchDatat()
        }
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
    }
}
