import SwiftUI

struct PlacementView: View {
    @EnvironmentObject var placementSettings: PlacementSettings
    @EnvironmentObject var worldManager: WorldManager
    @EnvironmentObject var sceneManager: SceneManager

    var body: some View {
        VStack(spacing: 12) {
            if let selectedModel = placementSettings.selectedModel {
                Text("Place \(selectedModel.name)").appText(.h2)
            } else if let pendingWorld = worldManager.pendingWorldForPlacement {
                Text("Place \(pendingWorld.name)").appText(.h2)
            }
            Text(placementSettings.placementStatusMessage).appText(.paragraph, color: placementSettings.isPlacementAvailable ? AppTheme.highlight : AppTheme.mutedText)
            HStack(spacing: 18) {
                AppButton("Cancel", systemImage: "xmark", style: .secondary) {
                    self.placementSettings.selectedModel = nil
                    self.worldManager.cancelPendingWorldPlacement()
                }
                AppButton("Place", systemImage: "checkmark", style: .primary) {
                    guard self.placementSettings.isPlacementAvailable else {
                        print("Placement Error: Confirm placement requested before a surface was available.")
                        return
                    }
                    if let selectedModel = self.placementSettings.selectedModel {
                        print("Placement: confirmed Place for \(selectedModel.name) at \(selectedModel.assetURL.path).")
                        self.placementSettings.modelConfirmedForPlacement.append(ModelAnchor(model: selectedModel, anchor: nil))
                    } else if let pendingWorld = self.worldManager.pendingWorldForPlacement {
                        print("World: confirmed placement for saved world \(pendingWorld.name).")
                        self.sceneManager.shouldLoadSceneFromFilesystem = true
                    }
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
