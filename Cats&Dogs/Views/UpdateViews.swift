import SwiftUI

/// Shown instead of the whole app when this version is below the minimum supported one.
struct UpdateRequiredView: View {
    let storeURL: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        OnboardingLayout {
            PetScene(mood: .night)
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                .background(PetMood.night.skyColor, in: RoundedRectangle(cornerRadius: 24))

            Text("Time for an update")
                .font(.brand(.largeTitle, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)

            Text("This version of Sunny & Misty has stopped working. Sunny's packed, Misty's pretending not to notice. Update to keep the walks coming.")
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        } actions: {
            if let storeURL {
                Button {
                    openURL(storeURL)
                } label: {
                    Text("Update").frame(maxWidth: .infinity)
                }
                .accentButtonStyle()
                .controlSize(.large)
            } else {
                Text("Update from the App Store.")
                    .font(.headline)
            }
        }
    }
}

/// Above the weather when a newer version is recommended. "Not now" hides it for a week.
struct UpdateBanner: View {
    let storeURL: URL?
    let onDismiss: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("A new version is out")
                    .font(.subheadline.weight(.semibold))
                Text("Update for the latest features and fixes.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
                HStack(spacing: 20) {
                    if let storeURL {
                        Button("Update") { openURL(storeURL) }
                            .fontWeight(.semibold)
                    }
                    Button("Not now", action: onDismiss)
                        .foregroundStyle(Color.secondaryText)
                }
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accent)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.surfaceVariant, in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview("Required") {
    UpdateRequiredView(storeURL: URL(string: "https://apps.apple.com"))
}

#Preview("Banner") {
    UpdateBanner(storeURL: URL(string: "https://apps.apple.com"), onDismiss: {})
        .padding()
}
