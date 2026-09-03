import SwiftUI
import ARKit

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
            if placementSettings.selectedModel != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Placement Mode").appText(.paragraph, color: AppTheme.text)
                    Picker("Placement Mode", selection: $placementSettings.placementMode) {
                        Text("Free").tag(PlacementMode.free)
                        Text("Grid").tag(PlacementMode.grid)
                    }
                    .pickerStyle(.segmented)
                    .tint(AppTheme.accent)
                    .accessibilityLabel("Placement Mode")
                    .accessibilityValue(placementSettings.placementMode == .grid ? "Grid" : "Free")

                    Text("Grid snaps placement to the world grid.")
                        .appText(.paragraph, color: AppTheme.mutedText)
                }

                if placementSettings.placementMode == .grid {
                    HStack(spacing: 24) {
                        Button { placementSettings.rotatePending(clockwise: false) } label: { Label("Rotate left", systemImage: "rotate.left") }
                            .accessibilityLabel("Rotate pending asset left")
                        Text("\(placementSettings.requestedQuarterTurns * 90)°").appText(.paragraph)
                        Button { placementSettings.rotatePending(clockwise: true) } label: { Label("Rotate right", systemImage: "rotate.right") }
                            .accessibilityLabel("Rotate pending asset right")
                    }
                }
            }
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
                        let capturedSurface = self.placementSettings.latestRawWorldTransform.map(ARAnchor.init(transform:))
                        self.placementSettings.modelConfirmedForPlacement.append(ModelAnchor(model: selectedModel, anchor: capturedSurface, modelTransform: self.placementSettings.latestResolvedTransform))
                    } else if let pendingWorld = self.worldManager.pendingWorldForPlacement {
                        print("World: confirmed placement for saved world \(pendingWorld.name).")
                        self.sceneManager.shouldPlacePendingWorld = true
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
        .onChange(of: placementSettings.selectedModel?.id) { _ in placementSettings.resetPendingRotation() }
    }
}
