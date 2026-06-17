import SwiftUI

struct SavedWorldsView: View {
    @EnvironmentObject var sceneManager: SceneManager
    @State private var refreshID = UUID()
    @State private var showingDeleteConfirmation = false
    @State private var navigateToWorld = false

    private var savedWorld: SavedWorldInfo? {
        SavedWorldInfo(url: sceneManager.persistenceUrl)
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppScreenHeader("Saved Worlds", subtitle: "Worlds are stored locally on this device.")
                    if let savedWorld = savedWorld {
                        SavedWorldCard(savedWorld: savedWorld, open: { navigateToWorld = true }, delete: { showingDeleteConfirmation = true })
                    } else {
                        AppSurface {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("No saved worlds yet").appText(.h2)
                                Text("Create a world, place a few models, then save it from the AR controls.").appText(.paragraph, color: AppTheme.mutedText)
                                NavigationLink(destination: ContentView()) {
                                    HStack { Image(systemName: "sparkles"); Text("Create World").appText(.h3) }
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .background(AppTheme.highlight.opacity(0.95))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
                .padding(24)
            }
            NavigationLink("", destination: ContentView(loadSavedWorldOnAppear: true), isActive: $navigateToWorld).hidden()
        }
        .id(refreshID)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete saved world?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                sceneManager.deleteSavedScene()
                refreshID = UUID()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the local saved scene from this device.")
        }
    }
}

struct SavedWorldInfo {
    let url: URL
    let savedAt: Date?
    let modelCount: Int?

    init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        self.url = url
        if let data = try? Data(contentsOf: url), let scene = try? JSONDecoder().decode(PersistedScene.self, from: data) {
            self.savedAt = scene.savedAt
            self.modelCount = scene.placements.count
        } else {
            self.savedAt = nil
            self.modelCount = nil
        }
    }
}

private struct SavedWorldCard: View {
    let savedWorld: SavedWorldInfo
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved World").appText(.h2)
                if let savedAt = savedWorld.savedAt {
                    Text(savedAt.formatted(date: .abbreviated, time: .shortened)).appText(.paragraph, color: AppTheme.mutedText)
                }
                if let modelCount = savedWorld.modelCount {
                    Text("\(modelCount) placed model\(modelCount == 1 ? "" : "s")").appText(.h3, color: AppTheme.mutedText)
                }
                HStack(spacing: 12) {
                    AppButton("Open", systemImage: "arkit", style: .primary, action: open)
                    AppButton("Delete", systemImage: "trash", style: .destructive, action: delete)
                }
            }
        }
    }
}
