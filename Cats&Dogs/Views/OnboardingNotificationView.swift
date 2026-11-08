import SwiftUI

struct OnboardingNotificationView: View {
    /// What the notifications will be, from the welcome view model.
    let text: String
    let onAllow: () async -> Void
    let onNotNow: () -> Void

    var body: some View {
        OnboardingLayout {
            ZStack {
                Circle()
                    .fill(Color.primaryContainer)
                    .frame(width: 112, height: 112)
                Image(systemName: "bell.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accent)
            }

            Text("Stay in the loop")
                .font(.brand(.title2))
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)

            Text(text)
                .font(.body)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
        } actions: {
            Button {
                Task { await onAllow() }
            } label: {
                Text("Allow notifications").frame(maxWidth: .infinity)
            }
            .accentButtonStyle()
            .controlSize(.large)

            Button(action: onNotNow) {
                Text("Not now").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

#Preview {
    OnboardingNotificationView(
        text: "Each morning, Sunny & Misty will send a weather briefing for your location.",
        onAllow: {},
        onNotNow: {}
    )
}
