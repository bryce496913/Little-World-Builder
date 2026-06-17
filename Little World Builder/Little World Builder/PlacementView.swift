//
//  PlacementView.swift
//  AR Test
//
//  Created by Bryce on 6/07/21.
//

import SwiftUI

struct PlacementView: View {
    @EnvironmentObject var placementSettings: PlacementSettings
    
    var body: some View {
        HStack {
            
            Spacer()
            
            PlacementButton(systemIconName: "xmark.circle.fill") {
                print("Canel Placement button pressed.")
                self.placementSettings.selectedModel = nil
            }
            
            Spacer()
            
            PlacementButton(systemIconName: "checkmark.circle.fill") {
                print("Confirm Placement button pressed.")

                guard let selectedModel = self.placementSettings.selectedModel else {
                    print("Placement Error: Confirm placement requested without a selected model.")
                    return
                }

                let modelAnchor = ModelAnchor(model: selectedModel, anchor: nil)
                self.placementSettings.modelConfirmedForPlacement.append(modelAnchor)
                
                self.placementSettings.selectedModel = nil
            }
            
            Spacer()
        }
        .padding(.bottom, 30)
    }
}

struct PlacementButton: View {
    let systemIconName: String
    let action: () -> Void
    
    var body: some View {
        
        Button(action: {
            self.action()
        }) {
            Image(systemName: systemIconName)
                .font(.system(size: 50, weight: .light, design: .default))
                .foregroundColor(.white)
                .buttonStyle(PlainButtonStyle())
        }
        .frame(width: 75, height: 75)
    }
}
