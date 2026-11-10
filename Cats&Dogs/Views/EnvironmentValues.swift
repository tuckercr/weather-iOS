import SwiftUI

// What the weather screen hands down to the views inside it.
extension EnvironmentValues {
    /// Whether the city on screen is south of the equator, where the moon is lit from the other side.
    @Entry var southernHemisphere = false

    /// The weather screen's clock, which only moves on a refresh, a return to the app or the
    /// 30-minute tick, so the moon in the icons and the pet scene matches the rest of the screen.
    /// Nil outside the weather screen, where views use the device clock.
    @Entry var screenNow: Date? = nil

    /// Today's theme for the city on screen, or nil. Set by `CurrentWeatherView`.
    @Entry var seasonalTheme: SeasonalTheme? = nil
}
