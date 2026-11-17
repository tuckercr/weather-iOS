import Foundation

/// Where an Open-Meteo request goes. With the commercial plan's key, the customer servers
/// (`customer-` in front of the free host, as in `customer-api.open-meteo.com`) with `apikey`
/// added; without one (a local build with no key in Secrets.plist), the free servers. Release
/// builds can't be made without the key. Same as Android's `data/OpenMeteoEndpoint.kt`.
enum OpenMeteoEndpoint {
    nonisolated static func url(_ freeURL: URL, apiKey: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: freeURL, resolvingAgainstBaseURL: false)!
        var items = query
        if !apiKey.isEmpty, let host = components.host {
            components.host = "customer-" + host
            items.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        components.queryItems = items
        return components.url!
    }
}
