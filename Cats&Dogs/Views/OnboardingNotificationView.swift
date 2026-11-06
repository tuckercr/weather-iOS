import SwiftUI

struct OnboardingNotificationView: View {
    let onDone: () -> Void

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

            // With a dog (the question just before), the walk-time nudge is mentioned too; each kind
            // only while Remote Config has it on.
            Text(
                (PreferencesStore.shared.showWalkCard && RemoteConfigRepository.shared.walkTimeNotificationsEnabled
                    ? "Each morning, Sunny & Misty will send a weather briefing for your location, and Sunny will nudge you at the best time for a walk."
                    : "Each morning, Sunny & Misty will send a weather briefing for your location.")
                    + (RemoteConfigRepository.shared.rainNotificationsEnabled ? "\n\nYou can turn on rain alerts in Settings." : "")
            )
                .font(.body)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
        } actions: {
            Button {
                Task {
                    _ = await WeatherNotificationScheduler.shared.requestAuthorization()
                    await WeatherNotificationScheduler.shared.scheduleNotifications()
                    onDone()
                }
            } label: {
                Text("Allow notifications").frame(maxWidth: .infinity)
            }
            .accentButtonStyle()
            .controlSize(.large)

            Button(action: onDone) {
                Text("Not now").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

#Preview {
    OnboardingNotificationView(onDone: {})
}
