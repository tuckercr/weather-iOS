import SwiftUI

/// Onboarding step after the welcome screen. The answer sets the "Best walk time" switch in
/// Settings, so a home without a dog never sees the walk card. Same as Android.
struct OnboardingDogView: View {
    let onAnswered: (_ hasDog: Bool) -> Void

    var body: some View {
        OnboardingLayout {
            PetScene(mood: .cloudy)
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                .background(PetMood.cloudy.skyColor, in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 24)

            Text("Is there a dog at home?")
                .font(.brand(.title2))
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)

            Text("If there is, Sunny will suggest the best time for a walk. You can change this later in Settings.")
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
        } actions: {
            Button {
                onAnswered(true)
            } label: {
                Text("Yes").frame(maxWidth: .infinity)
            }
            .accentButtonStyle()
            .controlSize(.large)

            Button {
                onAnswered(false)
            } label: {
                Text("No").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

#Preview {
    OnboardingDogView(onAnswered: { _ in })
}
