import SwiftUI
import RealityKit

struct DeletionView: View {
    @EnvironmentObject var sceneManager: SceneManager
    @EnvironmentObject var modelDeletionManager: ModelDeletionManager

    var body: some View {
        VStack(spacing: 12) {
            Text("Delete selected model?").appText(.h2)
            HStack(spacing: 18) {
                AppButton("Cancel", systemImage: "xmark", style: .secondary) {
                    self.modelDeletionManager.entitySelectedForDeletion = nil
                }
                AppButton("Delete", systemImage: "trash", style: .destructive) {
                    guard let anchor = self.modelDeletionManager.entitySelectedForDeletion?.anchor as? AnchorEntity else { return }
                    self.sceneManager.removeAnchorEntity(anchor)
                    self.modelDeletionManager.entitySelectedForDeletion = nil
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
