import SwiftUI

// What the weather screen hands down to the views inside it.
extension EnvironmentValues {
    /// Whether the city on screen is south of the equator, where the moon is lit from the other side.
    @Entry var southernHemisphere = false

    /// Today's theme for the city on screen, or nil. Set by `CurrentWeatherView`.
    @Entry var seasonalTheme: SeasonalTheme? = nil
}
