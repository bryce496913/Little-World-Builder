import SwiftUI

struct PlacementView: View {
    @EnvironmentObject var placementSettings: PlacementSettings

    var body: some View {
        VStack(spacing: 12) {
            if let selectedModel = placementSettings.selectedModel {
                Text("Place \(selectedModel.name)").appText(.h2)
                Text(placementSettings.placementStatusMessage).appText(.paragraph, color: placementSettings.isPlacementAvailable ? AppTheme.highlight : AppTheme.mutedText)
            }
            HStack(spacing: 18) {
                AppButton("Cancel", systemImage: "xmark", style: .secondary) {
                    self.placementSettings.selectedModel = nil
                }
                AppButton("Place", systemImage: "checkmark", style: .primary) {
                    guard self.placementSettings.isPlacementAvailable else {
                        print("Placement Error: Confirm placement requested before a surface was available.")
                        return
                    }
                    guard let selectedModel = self.placementSettings.selectedModel else {
                        print("Placement Error: Confirm placement requested without a selected model.")
                        return
                    }
                    print("Placement: confirmed Place for \(selectedModel.name) at \(selectedModel.assetURL.path).")
                    self.placementSettings.modelConfirmedForPlacement.append(ModelAnchor(model: selectedModel, anchor: nil))
                }
                .disabled(!placementSettings.isPlacementAvailable)
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
