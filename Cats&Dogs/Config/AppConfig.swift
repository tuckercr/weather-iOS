import Foundation

enum AppConfig {
    private static let secretsFileName = "Secrets"

    /// The OpenWeather key: Remote Config `openweather_api_key` when set, so a leaked key can be
    /// rotated without an update, otherwise the one built into the app. API clients read it when
    /// they're created, so a rotated key takes effect from the next launch.
    static var openWeatherApiKey: String {
        resolveApiKey(remoteKey: RemoteConfigRepository.openWeatherApiKey, bundledKey: bundledKey("OWM_API_KEY"))
    }

    /// The Open-Meteo commercial plan's key, chosen the same way from Remote Config
    /// `open_meteo_api_key` and Secrets.plist's `OPEN_METEO_API_KEY`. Empty means the free servers
    /// (`OpenMeteoEndpoint`). Same as Android's `AppConfigModule`.
    static var openMeteoApiKey: String {
        resolveApiKey(remoteKey: RemoteConfigRepository.openMeteoApiKey, bundledKey: bundledKey("OPEN_METEO_API_KEY"))
    }

    static func resolveApiKey(remoteKey: String?, bundledKey: String) -> String {
        let remote = remoteKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return remote.isEmpty ? bundledKey : remote
    }

    /// A key from `Secrets.plist` (copy from `Secrets.example.plist`), or "" when it isn't there.
    private static func bundledKey(_ name: String) -> String {
        guard
            let url = Bundle.main.url(forResource: secretsFileName, withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
            ) as? [String: Any],
            let key = plist[name] as? String
        else {
            return ""
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "your_key_here" ? "" : trimmed
    }
}
