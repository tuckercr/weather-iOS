import SwiftUI

struct OnboardingLocationView: View {
    let onLocationResolved: (SavedLocation) -> Void
    let onSkip: () -> Void

    @State private var viewModel = LocationPermissionViewModel()

    var body: some View {
        OnboardingLayout {
            ZStack {
                Circle()
                    .fill(Color.primaryContainer)
                    .frame(width: 112, height: 112)
                if viewModel.state == .locating {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    Image(systemName: "location.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accent)
                }
            }

            Text("Use your location?")
                .font(.brand(.title2))
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .accessibilityAddTraits(.isHeader)

            Text(bodyText)
                .font(.body)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
        } actions: {
            if viewModel.state != .locating {
                Button(action: viewModel.useMyLocation) {
                    Text("Use my location").frame(maxWidth: .infinity)
                }
                .accentButtonStyle()
                .controlSize(.large)

                Button(action: onSkip) {
                    Text("Enter a town or city manually").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .onChange(of: viewModel.state) { _, newState in
            switch newState {
            case .located(let location):
                onLocationResolved(location)
            case .permissionDenied:
                // A "no" is an answer: move on to entering a city rather than asking again.
                onSkip()
            default:
                break
            }
        }
    }

    private var bodyText: String {
        switch viewModel.state {
        case .failed:
            "Could not determine your location. You can still add locations manually."
        default:
            "Misty likes to know which window she's looking out of. Allow your location to see the weather where you are."
        }
    }
}

#Preview {
    OnboardingLocationView(onLocationResolved: { _ in }, onSkip: {})
}
