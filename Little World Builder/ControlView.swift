//
//  ControlView.swift
//  AR Test
//
//  Created by Bryce on 1/07/21.
//

import SwiftUI

enum ControlModes: String, CaseIterable {
    case browse = "Models"
    case scene = "Scene"
}

struct ControlView: View {
    @Binding var selectControlMode: Int
    @Binding var isControlsVisible: Bool
    @Binding var showBrowse: Bool

    var body: some View {
        VStack {
            HStack {
                Spacer()
                ControlVisibilityToggleButton(isControlsVisible: $isControlsVisible)
            }
            .padding(.top, 100)
            .padding(.trailing, 16)

            Spacer()

            if isControlsVisible {
                VStack(spacing: 12) {
                    ControlModePicker(selectedControlMode: $selectControlMode)
                    ControlButtonBar(showBrowse: $showBrowse, selectedControlMode: selectControlMode)
                }
                .padding(16)
                .background(AppTheme.surface.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.accent.opacity(0.65), lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }
}

struct ControlVisibilityToggleButton: View {
    @Binding var isControlsVisible: Bool

    var body: some View {
        Button(action: { self.isControlsVisible.toggle() }) {
            Image(systemName: self.isControlsVisible ? "rectangle.compress.vertical" : "slider.horizontal.below.rectangle")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.text)
                .frame(width: 44, height: 44)
                .background(AppTheme.surface.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.accent, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ControlModePicker: View {
    @Binding var selectedControlMode: Int
    let controlModes = ControlModes.allCases

    var body: some View {
        Picker(selection: $selectedControlMode, label: Text("Controls")) {
            ForEach(0..<controlModes.count, id: \.self) { index in
                Text(self.controlModes[index].rawValue).tag(index)
            }
        }
        .pickerStyle(.segmented)
        .tint(AppTheme.accent)
    }
}

struct ControlButtonBar: View {
    @Binding var showBrowse: Bool
    var selectedControlMode: Int

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if selectedControlMode == 1 {
                SceneButtons()
            } else {
                BrowseButtons(showBrowse: $showBrowse)
            }
        }
    }
}

struct BrowseButtons: View {
    @EnvironmentObject var placementSettings: PlacementSettings
    @Binding var showBrowse: Bool

    var body: some View {
        HStack(spacing: 14) {
            MostRecentlyPlacedButton().opacity(self.placementSettings.recentlyPlaced.isEmpty ? 0.35 : 1)
            ControlButton(title: "Models", systemIconName: "square.grid.2x2") { self.showBrowse.toggle() }
                .sheet(isPresented: $showBrowse) {
                    BrowseView(showBrowse: $showBrowse)
                        .environmentObject(placementSettings)
                }
        }
    }
}

struct SceneButtons: View {
    @EnvironmentObject var sceneManager: SceneManager

    var body: some View {
        HStack(spacing: 14) {
            ControlButton(title: "Save", systemIconName: "square.and.arrow.down") {
                self.sceneManager.shouldSaveSceneToFilesystem = true
            }


            ControlButton(title: "Load", systemIconName: "folder") {
                self.sceneManager.shouldLoadSceneFromFilesystem = true
            }

            ControlButton(title: "Clear", systemIconName: "trash", role: .destructive) {
                self.sceneManager.clearCurrentScene()
            }
        }
    }
}

struct ControlButton: View {
    enum Role { case normal, destructive }
    let title: String
    let systemIconName: String
    var role: Role = .normal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemIconName)
                    .font(.system(size: 20, weight: .bold))
                Text(title).appText(.paragraph)
            }
            .foregroundColor(AppTheme.text)
            .frame(width: 72, height: 58)
            .background((role == .destructive ? AppTheme.highlight : AppTheme.accent).opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(role == .destructive ? AppTheme.highlight : AppTheme.accent, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct MostRecentlyPlacedButton: View {
    @EnvironmentObject var placementSettings: PlacementSettings

    var body: some View {
        Button(action: {
            self.placementSettings.selectedModel = self.placementSettings.recentlyPlaced.last
        }) {
            VStack(spacing: 4) {
                if let model = self.placementSettings.recentlyPlaced.last {
                    Image(uiImage: model.thumbnail).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "clock.fill").font(.system(size: 20, weight: .bold))
                }
                Text("Recent").appText(.paragraph)
            }
            .frame(width: 72, height: 58)
            .background(AppTheme.accent.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.accent, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(self.placementSettings.recentlyPlaced.isEmpty)
    }
}
