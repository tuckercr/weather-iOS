import Foundation

enum WeatherErrorMessages {
    static let pullToRetry = "Pull to try again."

    static func message(for errorKey: String) -> String {
        switch errorKey {
        case "offline":
            // No "try again" here: the full-screen error has a Try again button, and the banner adds
            // `pullToRetry`, as pulling to refresh is the only way to retry there.
            "Misty knocked the Wi-Fi off the shelf."
        case "city_not_found":
            "We couldn't find that town or city. Try a different search."
        case "missing_api_key", "bad_api_key":
            "Weather service is not configured. Check your API key in Secrets.plist."
        case "rate_limited":
            "Too many requests. Please wait a moment and try again."
        case "server_error":
            "The weather service is napping. Try again in a few minutes."
        case "empty_query":
            "Please enter a city name."
        default:
            "Weather data is not available right now. Please try again later."
        }
    }

    static func errorKey(for error: Error) -> String {
        if let clientError = error as? OpenWeatherClientError {
            switch clientError {
            case .missingApiKey: return "missing_api_key"
            case .emptyQuery: return "empty_query"
            case .network: return "offline"
            case .http(let statusCode, let message):
                switch statusCode {
                case 401, 403: return "bad_api_key"
                case 404: return "city_not_found"
                case 429: return "rate_limited"
                case 500...599: return "server_error"
                default:
                    return message.hasPrefix("http_") ? "generic" : message
                }
            case .invalidPayload: return "generic"
            }
        }
        return "generic"
    }

    static func canRetry(for error: Error) -> Bool {
        let key = errorKey(for: error)
        switch key {
        case "missing_api_key", "bad_api_key", "city_not_found", "empty_query":
            return false
        default:
            return true
        }
    }
}
