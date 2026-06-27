import SwiftUI

struct SavedWorldsView: View {
    @EnvironmentObject var worldManager: WorldManager
    @State private var refreshID = UUID()
    @State private var worldPendingDeletion: SavedWorld?
    @State private var navigateToWorld = false

    private var savedWorlds: [SavedWorld] { worldManager.savedWorlds() }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppScreenHeader("Saved Worlds", subtitle: "Portable worlds are stored locally on this device.")
                    if savedWorlds.isEmpty {
                        AppSurface {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("No saved worlds yet").appText(.h2)
                                Text("Start a blank AR session, place any local model, then save your arrangement from the AR controls.").appText(.paragraph, color: AppTheme.mutedText)
                                NavigationLink(destination: ContentView()) {
                                    HStack { Image(systemName: "sparkles"); Text("Create World").appText(.h3) }
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .background(AppTheme.highlight.opacity(0.95))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    } else {
                        ForEach(savedWorlds) { world in
                            SavedWorldCard(savedWorld: world, open: {
                                worldManager.loadWorld(world)
                                navigateToWorld = true
                            }, delete: { worldPendingDeletion = world })
                        }
                    }
                }
                .padding(24)
            }
        }
        .navigationDestination(isPresented: $navigateToWorld) {
            ContentView(loadSavedWorldOnAppear: true)
        }
        .id(refreshID)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete saved world?", isPresented: Binding(get: { worldPendingDeletion != nil }, set: { if !$0 { worldPendingDeletion = nil } })) {
            Button("Delete", role: .destructive) {
                if let worldPendingDeletion { worldManager.delete(worldPendingDeletion) }
                worldPendingDeletion = nil
                refreshID = UUID()
            }
            Button("Cancel", role: .cancel) { worldPendingDeletion = nil }
        } message: {
            Text("This removes the portable SavedWorld JSON and optional thumbnail from this device.")
        }
    }
}

private struct SavedWorldCard: View {
    let savedWorld: SavedWorld
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text(savedWorld.name).appText(.h2)
                Text(savedWorld.updatedAt.formatted(date: .abbreviated, time: .shortened)).appText(.paragraph, color: AppTheme.mutedText)
                Text("\(savedWorld.placedAssets.count) asset\(savedWorld.placedAssets.count == 1 ? "" : "s")").appText(.h3, color: AppTheme.mutedText)
                HStack(spacing: 12) {
                    AppButton("Open", systemImage: "arkit", style: .primary, action: open)
                    AppButton("Delete", systemImage: "trash", style: .destructive, action: delete)
                }
            }
        }
    }
}
