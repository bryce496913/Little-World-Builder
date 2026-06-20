import SwiftUI

struct SavedWorldsView: View {
    @EnvironmentObject var islandManager: IslandManager
    @State private var refreshID = UUID()
    @State private var islandPendingDeletion: SavedIsland?
    @State private var navigateToWorld = false

    private var savedIslands: [SavedIsland] { islandManager.savedIslands() }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppScreenHeader("Saved Worlds", subtitle: "Portable islands are stored locally on this device.")
                    if savedIslands.isEmpty {
                        AppSurface {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("No saved islands yet").appText(.h2)
                                Text("Create an island, place the root in AR, add models, then save it from the AR controls.").appText(.paragraph, color: AppTheme.mutedText)
                                NavigationLink(destination: ContentView()) {
                                    HStack { Image(systemName: "sparkles"); Text("Create Island").appText(.h3) }
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .background(AppTheme.highlight.opacity(0.95))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    } else {
                        ForEach(savedIslands) { island in
                            SavedWorldCard(savedIsland: island, open: {
                                islandManager.loadIsland(island)
                                navigateToWorld = true
                            }, delete: { islandPendingDeletion = island })
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
        .alert("Delete saved island?", isPresented: Binding(get: { islandPendingDeletion != nil }, set: { if !$0 { islandPendingDeletion = nil } })) {
            Button("Delete", role: .destructive) {
                if let islandPendingDeletion { islandManager.delete(islandPendingDeletion) }
                islandPendingDeletion = nil
                refreshID = UUID()
            }
            Button("Cancel", role: .cancel) { islandPendingDeletion = nil }
        } message: {
            Text("This removes the portable SavedIsland JSON and optional thumbnail from this device.")
        }
    }
}

private struct SavedWorldCard: View {
    let savedIsland: SavedIsland
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text(savedIsland.name).appText(.h2)
                Text(savedIsland.updatedAt.formatted(date: .abbreviated, time: .shortened)).appText(.paragraph, color: AppTheme.mutedText)
                Text("\(savedIsland.placedAssets.count) island asset\(savedIsland.placedAssets.count == 1 ? "" : "s") • Water: \(savedIsland.waterType.rawValue)").appText(.h3, color: AppTheme.mutedText)
                HStack(spacing: 12) {
                    AppButton("Open", systemImage: "arkit", style: .primary, action: open)
                    AppButton("Delete", systemImage: "trash", style: .destructive, action: delete)
                }
            }
        }
    }
}
