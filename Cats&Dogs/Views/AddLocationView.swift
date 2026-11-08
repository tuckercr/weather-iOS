import SwiftUI

/// Add location, a screen of its own (a full-screen cover), opened from Manage Locations' Add
/// location row and the empty weather screen. It was a sheet with the saved list above the search,
/// which put the results under the keyboard. Same layout and rules as Android's
/// `ui/AddLocationScreen.kt`.
struct AddLocationView: View {
    /// The location to save, the name to confirm it with ("Malmö added"), and how, for `city_added`.
    let onAdd: (SavedLocation, String, CityAdded) -> Void
    /// A place already saved, at this index: show its weather.
    let onGoTo: (Int) -> Void
    let onClose: () -> Void

    @State private var geoViewModel: GeoLocationViewModel
    @State private var locationViewModel = LocationPermissionViewModel()
    @FocusState private var searchFocused: Bool

    init(
        savedLocations: [SavedLocation],
        onAdd: @escaping (SavedLocation, String, CityAdded) -> Void,
        onGoTo: @escaping (Int) -> Void,
        onClose: @escaping () -> Void,
        geoViewModel: GeoLocationViewModel? = nil
    ) {
        self.onAdd = onAdd
        self.onGoTo = onGoTo
        self.onClose = onClose
        let viewModel = geoViewModel ?? GeoLocationViewModel()
        viewModel.open(savedLocations: savedLocations)
        _geoViewModel = State(initialValue: viewModel)
    }

    private var query: String {
        geoViewModel.cityInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var action: AddLocationAction { geoViewModel.action }

    /// Offered while My Location isn't saved and access is on or can still be asked for.
    private var canAddMyLocation: Bool {
        !geoViewModel.hasMyLocation
            && (locationViewModel.hasLocationPermission() || locationViewModel.canRequestPermission())
    }

    var body: some View {
        NavigationStack {
            List {
                if query.count < AddLocationRules.minSearchLength {
                    if canAddMyLocation { myLocationRow }
                } else if !geoViewModel.citySuggestions.isEmpty {
                    ForEach(geoViewModel.citySuggestions) { suggestion in
                        row(suggestion)
                    }
                } else if action == .notFound {
                    Text("We couldn't find that town or city. Try a different search.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.never)
            .background(Color.brandSurface)
            .safeAreaInset(edge: .top, spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .background(Color.brandSurface)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.brandSurface)
            }
            .navigationTitle("Add location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .onAppear { searchFocused = true }
        // The screen stays open until the fix arrives, then adds it and closes.
        .onChange(of: locationViewModel.state) { _, state in
            if case .located(let location) = state {
                perform(geoViewModel.addingMyLocation(location))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.secondaryText)
                .accessibilityHidden(true)
            TextField("Search for a town or city", text: Binding(
                get: { geoViewModel.cityInput },
                set: { geoViewModel.onCityInputChange($0) }
            ))
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($searchFocused)
            .onSubmit(runAction)
            if geoViewModel.citySuggestLoading {
                ProgressView()
            } else if !geoViewModel.cityInput.isEmpty {
                Button {
                    geoViewModel.onCityInputChange("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accent, lineWidth: 1.5))
    }

    private var myLocationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if locationViewModel.hasLocationPermission() {
                    locationViewModel.fetchLocation()
                } else {
                    // Fetches once allowed; a "Don't Allow" hides the row.
                    locationViewModel.requestPermission()
                }
            } label: {
                HStack(spacing: 10) {
                    if locationViewModel.state == .locating {
                        ProgressView()
                    } else {
                        Image(systemName: "location.fill")
                    }
                    Text("Add My Location")
                        .fontWeight(.medium)
                }
                .foregroundStyle(Color.accent)
            }
            .disabled(locationViewModel.state == .locating)
            if locationViewModel.state == .failed {
                Text("Couldn't find your location. Try again, or search for a town or city.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func row(_ suggestion: CitySuggestion) -> some View {
        let savedIndex = geoViewModel.savedIndex(of: suggestion)
        let isTarget = suggestion == geoViewModel.target
        return Button {
            perform(geoViewModel.choose(suggestion))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(boldTyped(suggestion.name))
                    if !suggestion.detail.isEmpty {
                        Text(suggestion.detail)
                            .font(.footnote)
                            .foregroundStyle(Color.secondaryText)
                    }
                }
                Spacer()
                if savedIndex != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Saved")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accent)
                } else if isTarget {
                    // What the keyboard's Search key would take; the button says it in words.
                    Image(systemName: "return")
                        .foregroundStyle(Color.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            // Every divider starts under the name, whatever the row has on its right.
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
        .buttonStyle(.plain)
        .listRowBackground(isTarget ? Color.accent.opacity(0.12) : Color.clear)
    }

    /// The letters typed so far in bold, as the list narrows.
    private func boldTyped(_ name: String) -> AttributedString {
        let count = AddLocationRules.matchedPrefixLength(name: name, typed: geoViewModel.cityInput)
        var typed = AttributedString(String(name.prefix(count)))
        typed.inlinePresentationIntent = .stronglyEmphasized
        return typed + AttributedString(String(name.dropFirst(count)))
    }

    /// The button above the keyboard, which names what it does, or why there's none.
    @ViewBuilder private var actionBar: some View {
        switch action {
        case .add(let suggestion):
            Button(action: runAction) {
                Text("Add \(suggestion.shortLabel)")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .accentButtonStyle()
            .controlSize(.large)
        case .addByName(let name):
            Button(action: runAction) {
                Text("Add “\(name)”")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .accentButtonStyle()
            .controlSize(.large)
        case .goTo(let suggestion, _):
            Button(action: runAction) {
                Text("Go to \(suggestion.shortLabel)")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .pickFromList:
            Label("Pick a town or city from the list", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
                .padding(.vertical, 10)
        case .none, .notFound:
            EmptyView()
        }
    }

    private func runAction() {
        guard let choice = geoViewModel.submit() else {
            // Return would otherwise put the keyboard away with nothing done.
            searchFocused = true
            return
        }
        perform(choice)
    }

    private func perform(_ choice: GeoLocationViewModel.Choice) {
        switch choice {
        case let .add(location, name, added): onAdd(location, name, added)
        case .goTo(let index): onGoTo(index)
        }
    }
}

#Preview {
    AddLocationView(
        savedLocations: [SavedLocation(label: "London, England, GB", latitude: 51.51, longitude: -0.13)],
        onAdd: { _, _, _ in },
        onGoTo: { _ in },
        onClose: {}
    )
}
