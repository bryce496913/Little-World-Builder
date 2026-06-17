import SwiftUI

struct PlacementView: View {
    @EnvironmentObject var placementSettings: PlacementSettings

    var body: some View {
        VStack(spacing: 12) {
            if let selectedModel = placementSettings.selectedModel {
                Text("Place \(selectedModel.name)").appText(.h2)
                Text("Aim at a surface, then confirm.").appText(.paragraph, color: AppTheme.mutedText)
            }
            HStack(spacing: 18) {
                AppButton("Cancel", systemImage: "xmark", style: .secondary) {
                    self.placementSettings.selectedModel = nil
                }
                AppButton("Place", systemImage: "checkmark", style: .primary) {
                    guard let selectedModel = self.placementSettings.selectedModel else {
                        print("Placement Error: Confirm placement requested without a selected model.")
                        return
                    }
                    self.placementSettings.modelConfirmedForPlacement.append(ModelAnchor(model: selectedModel, anchor: nil))
                    self.placementSettings.selectedModel = nil
                }
            }
        }
        .padding(16)
        .background(AppTheme.surface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.highlight, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }
}
