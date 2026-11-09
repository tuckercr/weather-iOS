import Foundation

/// Maps Open-Meteo's WMO weather codes onto the OpenWeatherMap-style condition, description and
/// icon code the rest of the app (icons, pet moods) already understands.
/// Reference: https://open-meteo.com/en/docs (WMO Weather interpretation codes).
enum WmoWeatherCodes {
    struct Condition: Equatable {
        let main: String
        let description: String
        let iconCode: String
    }

    static func condition(_ code: Int, isDay: Bool) -> Condition {
        let (main, description, icon): (String, String, String) = switch code {
        case 0: ("Clear", String(localized: "clear sky", comment: "Weather description, lower case, shown on the hero and in notifications"), "01")
        case 1: ("Clouds", String(localized: "mainly clear", comment: "Weather description, lower case, shown on the hero and in notifications"), "02")
        case 2: ("Clouds", String(localized: "partly cloudy", comment: "Weather description, lower case, shown on the hero and in notifications"), "03")
        case 3: ("Clouds", String(localized: "overcast", comment: "Weather description, lower case, shown on the hero and in notifications"), "04")
        case 45, 48: ("Fog", String(localized: "fog", comment: "Weather description, lower case, shown on the hero and in notifications"), "50")
        case 51, 53, 55: ("Drizzle", String(localized: "drizzle", comment: "Weather description, lower case, shown on the hero and in notifications"), "09")
        case 56, 57: ("Drizzle", String(localized: "freezing drizzle", comment: "Weather description, lower case, shown on the hero and in notifications"), "09")
        case 61: ("Rain", String(localized: "light rain", comment: "Weather description, lower case, shown on the hero and in notifications"), "10")
        case 63: ("Rain", String(localized: "moderate rain", comment: "Weather description, lower case, shown on the hero and in notifications"), "10")
        case 65: ("Rain", String(localized: "heavy rain", comment: "Weather description, lower case, shown on the hero and in notifications"), "10")
        case 66, 67: ("Rain", String(localized: "freezing rain", comment: "Weather description, lower case, shown on the hero and in notifications"), "13")
        case 71: ("Snow", String(localized: "light snow", comment: "Weather description, lower case, shown on the hero and in notifications"), "13")
        case 73: ("Snow", String(localized: "moderate snow", comment: "Weather description, lower case, shown on the hero and in notifications"), "13")
        case 75: ("Snow", String(localized: "heavy snow", comment: "Weather description, lower case, shown on the hero and in notifications"), "13")
        case 77: ("Snow", String(localized: "snow grains", comment: "Weather description, lower case, shown on the hero and in notifications"), "13")
        case 80, 81: ("Rain", String(localized: "rain showers", comment: "Weather description, lower case, shown on the hero and in notifications"), "09")
        case 82: ("Rain", String(localized: "violent rain showers", comment: "Weather description, lower case, shown on the hero and in notifications"), "09")
        case 85, 86: ("Snow", String(localized: "snow showers", comment: "Weather description, lower case, shown on the hero and in notifications"), "13")
        case 95: ("Thunderstorm", String(localized: "thunderstorm", comment: "Weather description, lower case, shown on the hero and in notifications"), "11")
        case 96, 99: ("Thunderstorm", String(localized: "thunderstorm with hail", comment: "Weather description, lower case, shown on the hero and in notifications"), "11")
        default: ("Clouds", String(localized: "cloudy", comment: "Weather description, lower case, shown on the hero and in notifications"), "03")
        }
        return Condition(main: main, description: description, iconCode: icon + (isDay ? "d" : "n"))
    }
}
