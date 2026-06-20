import SwiftUI

enum Setting {
    case peopleOcclusion
    case objectOcclusion
    case lidarDebug
    case multiuser

    var label: String {
        switch self {
        case .peopleOcclusion: return "People"
        case .objectOcclusion: return "Objects"
        case .lidarDebug: return "LiDAR"
        case .multiuser: return "Multiuser"
        }
    }

    var detail: String {
        switch self {
        case .peopleOcclusion: return "Hide models behind people."
        case .objectOcclusion: return "Blend models with real objects."
        case .lidarDebug: return "Show scene mesh debug."
        case .multiuser: return "Keep existing shared-session toggle."
        }
    }

    var systemIconName: String {
        switch self {
        case .peopleOcclusion: return "person"
        case .objectOcclusion: return "cube.box.fill"
        case .lidarDebug: return "light.min"
        case .multiuser: return "person.2"
        }
    }
}

struct SettingsView: View {
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AppScreenHeader("Settings", subtitle: "Tune the AR view while keeping your worlds local.")
                    SettingsGrid()
                }
                .padding(24)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsGrid: View {
    @EnvironmentObject var sessionSettings: SessionSettings

    var body: some View {
        VStack(spacing: 14) {
            SettingToggleButton(setting: .peopleOcclusion, isOn: $sessionSettings.isPeopleOcclusionEnabled)
            SettingToggleButton(setting: .objectOcclusion, isOn: $sessionSettings.isObjectOcclusionEnabled)
            SettingToggleButton(setting: .lidarDebug, isOn: $sessionSettings.isLidarDebugEnabled)
            SettingToggleButton(setting: .multiuser, isOn: $sessionSettings.isMultiuserEnabled)
        }
    }
}

struct SettingToggleButton: View {
    let setting: Setting
    @Binding var isOn: Bool

    var body: some View {
        Button(action: {
            self.isOn.toggle()
            print("\(#file) - \(setting): \(self.isOn)")
        }) {
            AppSurface(borderColor: isOn ? AppTheme.highlight : AppTheme.accent.opacity(0.45)) {
                HStack(spacing: 14) {
                    Image(systemName: setting.systemIconName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(isOn ? AppTheme.highlight : AppTheme.accent)
                        .frame(width: 42, height: 42)
                        .background((isOn ? AppTheme.highlight : AppTheme.accent).opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(setting.label).appText(.h2)
                        Text(setting.detail).appText(.paragraph, color: AppTheme.mutedText)
                    }
                    Spacer()
                    Text(isOn ? "On" : "Off").appText(.h3, color: isOn ? AppTheme.highlight : AppTheme.mutedText)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
