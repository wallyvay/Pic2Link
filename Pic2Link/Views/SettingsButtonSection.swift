import SwiftUI

/// 设置按钮区域
struct SettingsButtonSection: View {
    let activeProfile: ImageHostProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("settings.profileConfiguration"))
                .font(.headline)
                .foregroundColor(.primary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: (activeProfile?.isConfigured ?? false) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor((activeProfile?.isConfigured ?? false) ? .green : .orange)

                        Text(L10n.tr((activeProfile?.isConfigured ?? false) ? "profile.configured" : "profile.notConfigured"))
                            .font(.caption)
                    }

                    Text(activeProfile?.displayName ?? L10n.tr("profile.none"))
                        .font(.caption)

                    Text(activeProfile?.providerSummary ?? L10n.tr("profile.addInSettings"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                SettingsLink {
                    HStack {
                        Image(systemName: "gearshape")
                        Text(L10n.tr("common.settings"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
            }
        }
    }
}
