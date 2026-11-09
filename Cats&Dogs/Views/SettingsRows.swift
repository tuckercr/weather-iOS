import SwiftUI
import UIKit

/// The rows Settings and its Notifications screen share.
protocol SettingsScreen: View {}

extension SettingsScreen {
    /// The system's header grey is only about 3.3:1 on the brand surface; this one is 8.8:1.
    func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title).foregroundStyle(Color.secondaryText)
    }

    /// Takes the value rather than reading it inside the binding, so the body observes it and the
    /// switch redraws when it changes.
    func switchRow(
        _ title: LocalizedStringKey,
        summary: LocalizedStringKey? = nil,
        isOn: Bool,
        set: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: set)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    func permissionRow(
        status: PermissionStatus,
        grantedText: LocalizedStringKey,
        requestTitle: LocalizedStringKey,
        openSettingsTitle: LocalizedStringKey,
        settingsURL: String,
        onRequest: @escaping () -> Void
    ) -> some View {
        switch status {
        case .granted:
            Text(grantedText)
                .foregroundStyle(Color.secondaryText)
        case .notDetermined:
            // iOS has no Settings entry for a permission the app has never asked for.
            Button(requestTitle, action: onRequest)
        case .denied:
            Button(openSettingsTitle) {
                openSystemSettings(settingsURL)
            }
        }
    }

    func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}
