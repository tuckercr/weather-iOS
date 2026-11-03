import SwiftUI

/// The frame shared by the onboarding screens: centred when everything fits. When it doesn't (large
/// text sizes, small or landscape screens), the content scrolls from the top and the buttons stay
/// pinned at the bottom, so the way on is always in sight. Same as Android's `OnboardingLayout`.
struct OnboardingLayout<Content: View, Actions: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 12) {
                content
                actionStack
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            ScrollView {
                VStack(spacing: 12) { content }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionStack
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(Color.brandSurface)
                    .overlay(alignment: .top) { Divider() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandSurface)
    }

    private var actionStack: some View {
        VStack(spacing: 12) { actions }
    }
}
