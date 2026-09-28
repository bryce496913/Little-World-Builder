import SwiftUI
import RealityKit

struct EditView: View {
    @EnvironmentObject var worldManager: WorldManager

    private var record: PlacedAssetRecord? {
        guard let id = worldManager.interactionState.selection?.instanceID else { return nil }
        return worldManager.record(for: id)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Edit \(record?.displayName ?? "Object")").appText(.h2)
                .accessibilityLabel("Selected object")
                .accessibilityValue(record?.displayName ?? "No selection")
            Text("Twist or pinch the selected object, or use the controls below.")
                .appText(.paragraph, color: AppTheme.mutedText)
            HStack(spacing: 12) {
                editButton("Rotate Left", icon: "rotate.left") { rotate(clockwise: false) }
                editButton("Rotate Right", icon: "rotate.right") { rotate(clockwise: true) }
                editButton("Smaller", icon: "minus.magnifyingglass") { scale(by: 0.9) }
                editButton("Larger", icon: "plus.magnifyingglass") { scale(by: 1.1) }
            }
            HStack(spacing: 12) {
                editButton("Lower selected object", icon: "arrow.down") { worldManager.adjustSelectedHeight(.lower) }
                    .disabled(!worldManager.heightAdjustmentState.canAdjust)
                Text(heightText)
                    .appText(.paragraph)
                    .monospacedDigit()
                    .accessibilityLabel(heightAccessibilityLabel)
                editButton("Raise selected object", icon: "arrow.up") { worldManager.adjustSelectedHeight(.raise) }
                    .disabled(!worldManager.heightAdjustmentState.canAdjust)
                editButton("Undo height adjustment", icon: "arrow.uturn.backward") { worldManager.undoSelectedHeightAdjustment() }
                    .disabled(!worldManager.heightAdjustmentState.canUndo)
            }
            HStack(spacing: 18) {
                AppButton("Done", systemImage: "checkmark", style: .secondary) {
                    worldManager.clearSelection()
                }
                .accessibilityLabel("Done editing and deselect object")
                AppButton("Delete", systemImage: "trash", style: .destructive) {
                    worldManager.removeSelected()
                }
                .accessibilityLabel("Delete selected object")
            }
        }
        .padding(16)
        .background(AppTheme.surface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.highlight, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private var heightText: String {
        guard let y = worldManager.heightAdjustmentState.currentY else { return "Height unavailable" }
        return String(format: "Height %.0f cm", y * 100)
    }

    private var heightAccessibilityLabel: String {
        guard let y = worldManager.heightAdjustmentState.currentY else { return "Height unavailable" }
        return String(format: "Height, %.0f centimetres", y * 100)
    }

    private func editButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).frame(width: 44, height: 44)
                .background(AppTheme.accent.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(record?.displayName ?? "Selected object")
    }

    private func rotate(clockwise: Bool) {
        guard let entity = record?.entity else { worldManager.clearSelection(); return }
        entity.transform = SelectionTransformEditor.rotated(entity.transform, radians: clockwise ? -.pi / 8 : .pi / 8)
        if let id = record?.id { worldManager.select(instanceID: id) }
    }

    private func scale(by factor: Float) {
        guard let entity = record?.entity else { worldManager.clearSelection(); return }
        entity.transform = SelectionTransformEditor.scaled(entity.transform, factor: factor)
        if let id = record?.id { worldManager.select(instanceID: id) }
    }
}
