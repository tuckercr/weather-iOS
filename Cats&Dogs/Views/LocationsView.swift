import SwiftUI

/// Manage Locations: reorder and remove, and the Add location row, which opens the full-screen
/// `AddLocationView`.
struct LocationsView: View {
    @Bindable var cityListViewModel: CityListViewModel
    /// Back to the weather screen, after Add location's Go to picks a place already saved.
    let onShowWeather: () -> Void
    @State private var showAddLocation = false
    /// "Malmö added", shown for a few seconds after adding.
    @State private var confirmation: String?

    var body: some View {
        List {
            Section {
                ForEach(Array(cityListViewModel.locations.enumerated()), id: \.offset) { index, location in
                    HStack {
                        if location.isCurrentLocation {
                            Image(systemName: "location.fill")
                                .font(.caption)
                                .foregroundStyle(Color.accent)
                        }
                        Text(location.label)
                        if index == cityListViewModel.locations.notificationIndex {
                            Image(systemName: "bell.fill")
                                .font(.caption)
                                .foregroundStyle(Color.accent)
                                .accessibilityLabel("Notifications")
                        }
                        Spacer()
                    }
                    // The last city stays: the app always has one to show.
                    .deleteDisabled(cityListViewModel.locations.count <= 1)
                }
                // The standard delete: swipe left, or Edit and the red minus.
                .onDelete { offsets in
                    guard let index = offsets.first, cityListViewModel.locations.count > 1 else { return }
                    cityListViewModel.removeLocation(at: index)
                }
                .onMove { source, destination in
                    cityListViewModel.reorderLocations(from: source, to: destination)
                }
            } footer: {
                Label("Notifications are for My Location, otherwise the top location.", systemImage: "bell.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryText)
            }
            Section {
                Button {
                    showAddLocation = true
                } label: {
                    Label("Add location", systemImage: "plus")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.brandSurface)
        .navigationTitle("Manage Locations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        .overlay(alignment: .bottom) {
            if let confirmation {
                Text(confirmation)
                    .font(.subheadline)
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.label).opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: confirmation)
        .task(id: confirmation) {
            guard confirmation != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            confirmation = nil
        }
        .fullScreenCover(isPresented: $showAddLocation) {
            AddLocationView(
                savedLocations: cityListViewModel.locations,
                onAdd: { location, name, added in
                    cityListViewModel.addLocation(location, added: added)
                    showAddLocation = false
                    let message = "\(name) added"
                    confirmation = message
                    AccessibilityNotification.Announcement(message).post()
                },
                onGoTo: { index in
                    cityListViewModel.setActiveIndex(index)
                    showAddLocation = false
                    onShowWeather()
                },
                onClose: { showAddLocation = false }
            )
        }
    }
}

#Preview {
    NavigationStack {
        LocationsView(
            cityListViewModel: CityListViewModel(),
            onShowWeather: {}
        )
    }
}
