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
        VStack(spacing: 8) {
            Text(placementSettings.placementStatusMessage)
                .font(.caption)
                .foregroundColor(placementSettings.isPlacementAvailable ? .green : .white)
            HStack {
            
            Spacer()
            
            PlacementButton(systemIconName: "xmark.circle.fill") {
                print("Canel Placement button pressed.")
                self.placementSettings.selectedModel = nil
            }
            
            Spacer()
            
            PlacementButton(systemIconName: "checkmark.circle.fill", isEnabled: placementSettings.isPlacementAvailable) {
                print("Confirm Placement button pressed.")

                guard self.placementSettings.isPlacementAvailable else {
                    print("Placement Error: Confirm placement requested before a surface was available.")
                    return
                }

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
        }
        .padding(.bottom, 30)
    }
}

struct PlacementButton: View {
    let systemIconName: String
    var isEnabled: Bool = true
    let action: () -> Void
    
    var body: some View {
        
        Button(action: {
            self.action()
        }) {
            Image(systemName: systemIconName)
                .font(.system(size: 50, weight: .light, design: .default))
                .foregroundColor(isEnabled ? .white : .gray)
                .buttonStyle(PlainButtonStyle())
        }
        .frame(width: 75, height: 75)
        .disabled(!isEnabled)
    }
}
