import SwiftUI

struct MainMenuView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 24) {
                    AppScreenHeader("Little World Builder", subtitle: "Build tiny playful worlds in AR with local models, then save them on this device.")
                        .padding(.top, 24)

                    VStack(spacing: 16) {
                        NavigationLink(destination: ContentView()) {
                            MainMenuCard(title: "Create World", subtitle: "Pick a model and place it in AR.", icon: "sparkles", borderColor: AppTheme.highlight)
                        }
                        NavigationLink(destination: SavedWorldsView()) {
                            MainMenuCard(title: "Saved Worlds", subtitle: "Open or delete your local saved world.", icon: "folder", borderColor: AppTheme.accent)
                        }
                        NavigationLink(destination: SettingsView()) {
                            MainMenuCard(title: "Settings", subtitle: "Adjust AR display and occlusion options.", icon: "slider.horizontal.3", borderColor: AppTheme.accent)
                        }
                    }
                    Spacer()
                }
                .padding(24)
            }
            .navigationBarHidden(true)
        }
        .tint(AppTheme.text)
    }
}

private struct MainMenuCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let borderColor: Color

    var body: some View {
        AppSurface(borderColor: borderColor) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(borderColor)
                    .frame(width: 44, height: 44)
                    .background(borderColor.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).appText(.h2)
                    Text(subtitle).appText(.paragraph, color: AppTheme.mutedText)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(AppTheme.mutedText)
            }
        }
    }
}
