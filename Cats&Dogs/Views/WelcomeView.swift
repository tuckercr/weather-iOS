import SwiftUI

/// The first onboarding screen: introduces Sunny and Misty, who tell you the weather.
struct WelcomeView: View {
    let onGetStarted: () -> Void

    var body: some View {
        OnboardingLayout {
            PetScene(mood: .sunny)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(PetMood.sunny.skyColor, in: RoundedRectangle(cornerRadius: 24))

            title

            character(
                name: "Sunny",
                body: "Loves a walk in almost any weather, and always knows the best time to head out."
            )
            character(
                name: "Misty",
                body: "Prefers the window seat, and will tell you when it's a day for staying in."
            )

            Text("Together they check the sky so you know what to expect, for you and your pets.")
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
        } actions: {
            Button(action: onGetStarted) {
                Text("Get started").frame(maxWidth: .infinity)
            }
            .accentButtonStyle()
            .controlSize(.large)
        }
    }

    /// One line when it fits. Otherwise it breaks after "Meet", keeping the two names together. The
    /// largest text sizes wrap wherever they must.
    private var title: some View {
        ViewThatFits(in: .horizontal) {
            titleText("Meet Sunny & Misty")
            VStack(spacing: 0) {
                titleText("Meet")
                titleText("Sunny & Misty")
            }
            titleText("Meet Sunny & Misty")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meet Sunny & Misty")
        .accessibilityAddTraits(.isHeader)
    }

    private func titleText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.brand(.largeTitle, weight: .bold))
            .multilineTextAlignment(.center)
    }

    private func character(name: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.brand(.title2))
                .foregroundStyle(Color.accent)
            Text(body)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView(onGetStarted: {})
}
