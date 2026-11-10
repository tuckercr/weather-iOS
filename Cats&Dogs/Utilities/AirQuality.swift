import Foundation

/// An hour's air quality: an index on the scale the city uses (Europe's, or the US one everywhere
/// else), and the pollutant behind it. Same rules as Android's `AirQuality`. Codable, as it's cached
/// with the forecast.
struct AirQuality: Codable, Equatable, Sendable {
    enum Scale: String, Codable, Equatable, Sendable {
        case us, european

        /// Europe's index for cities on a European clock, the US one everywhere else.
        static func forTimeZone(_ identifier: String?) -> Scale {
            identifier?.hasPrefix("Europe/") == true ? .european : .us
        }

        /// Where each of the six bands starts, and where the last one is drawn to end.
        var bandEdges: [Double] {
            switch self {
            case .us: [0, 50, 100, 150, 200, 300, 500]
            case .european: [0, 20, 40, 60, 80, 100, 150]
            }
        }

        var bandNames: [String] {
            switch self {
            // "Unhealthy for sensitive groups" doesn't fit on a tile.
            case .us: [String(localized: "Good", comment: "Air quality band name on the Air Quality tile"), String(localized: "Moderate", comment: "UV exposure category (WHO), or air quality band name on the Air Quality tile"), String(localized: "Poor for some", comment: "Air quality band name on the Air Quality tile"), String(localized: "Unhealthy", comment: "Air quality band name on the Air Quality tile"), String(localized: "Very unhealthy", comment: "Air quality band name on the Air Quality tile"), String(localized: "Hazardous", comment: "Air quality band name on the Air Quality tile")]
            case .european: [String(localized: "Good", comment: "Air quality band name on the Air Quality tile"), String(localized: "Fair", comment: "Air quality band name on the Air Quality tile"), String(localized: "Moderate", comment: "UV exposure category (WHO), or air quality band name on the Air Quality tile"), String(localized: "Poor", comment: "Air quality band name on the Air Quality tile"), String(localized: "Very poor", comment: "Air quality band name on the Air Quality tile"), String(localized: "Extremely poor", comment: "Air quality band name on the Air Quality tile")]
            }
        }
    }

    enum Pollutant: String, Codable, CaseIterable, Sendable {
        case fineParticles, coarseParticles, ozone, nitrogenDioxide, sulphurDioxide, carbonMonoxide

        var name: String {
            switch self {
            case .fineParticles: String(localized: "fine particles", comment: "Air pollutant, lower case, as in Mostly fine particles")
            case .coarseParticles: String(localized: "coarse particles", comment: "Air pollutant, lower case, as in Mostly fine particles")
            case .ozone: String(localized: "ozone", comment: "Air pollutant, lower case, as in Mostly fine particles")
            case .nitrogenDioxide: String(localized: "nitrogen dioxide", comment: "Air pollutant, lower case, as in Mostly fine particles")
            case .sulphurDioxide: String(localized: "sulphur dioxide", comment: "Air pollutant, lower case, as in Mostly fine particles")
            case .carbonMonoxide: String(localized: "carbon monoxide", comment: "Air pollutant, lower case, as in Mostly fine particles")
            }
        }
    }

    let index: Int
    let scale: Scale
    /// The pollutant with the highest sub-index; nil when none were reported.
    let mainPollutant: Pollutant?

    /// 0 (good) to 5 (the worst band).
    var band: Int {
        let edges = scale.bandEdges
        return (1 ..< edges.count - 1).last { Double(index) > edges[$0] } ?? 0
    }

    var bandName: String { scale.bandNames[band] }

    /// Where the index sits along the six equal bands of the tile's bar, 0 to 1.
    var barPosition: Double {
        let edges = scale.bandEdges
        let within = (Double(index) - edges[band]) / (edges[band + 1] - edges[band])
        return min(max((Double(band) + within) / 6, 0), 1)
    }

    var pollutantLine: String? {
        mainPollutant.map { String(localized: "Mostly \($0.name)", comment: "Air Quality tile: the main pollutant") }
    }

    /// What the air means for a walk, or for people when there's no dog. With a dog it follows the
    /// walk rules (`WalkConditions.airLevel`), so it moves with Remote Config's `walk_bad_air_band`
    /// and never contradicts the walk card.
    func line(hasDog: Bool, thresholds: PetWeatherThresholds = .standard) -> String {
        if hasDog {
            return switch WalkConditions.airLevel(band: band, thresholds) {
            case .stayIn, .danger: String(localized: "Stay in. Potty breaks only", comment: "Air Quality tile: what the air means for a dog walk")
            case .pottyOnly: String(localized: "Potty breaks only today", comment: "Air Quality tile: what the air means for a dog walk")
            case .fine, .wait: String(localized: "Short walks for older and flat-faced dogs", comment: "Air Quality tile: what the air means for a dog walk")
            case .great: band == 0 ? String(localized: "Good air for a long walk", comment: "Air Quality tile: what the air means for a dog walk") : String(localized: "Fine for most walks", comment: "Air Quality tile: what the air means for a dog walk")
            }
        }
        return switch band {
        case 0: String(localized: "Fresh air all round", comment: "Air Quality tile: what the air means for people")
        case 1: String(localized: "Fine for most people", comment: "Air Quality tile: what the air means for people")
        case 2: String(localized: "Sensitive people should take it easy", comment: "Air Quality tile: what the air means for people")
        case 3, 4: String(localized: "Limit time outdoors", comment: "Air Quality tile: what the air means for people")
        default: String(localized: "Stay indoors", comment: "Air Quality tile: what the air means for people")
        }
    }

    /// Picks the pollutant with the highest sub-index on `scale`. Nil without an index.
    static func from(_ readings: AirQualityReadings, scale: Scale) -> AirQuality? {
        let index: Int?
        let subIndices: [(Pollutant, Int?)]
        switch scale {
        case .us:
            index = readings.usAqi
            subIndices = [
                (.coarseParticles, readings.usAqiPm10), (.fineParticles, readings.usAqiPm25),
                (.ozone, readings.usAqiOzone), (.nitrogenDioxide, readings.usAqiNitrogenDioxide),
                (.sulphurDioxide, readings.usAqiSulphurDioxide), (.carbonMonoxide, readings.usAqiCarbonMonoxide),
            ]
        case .european:
            index = readings.europeanAqi
            subIndices = [
                (.coarseParticles, readings.europeanAqiPm10), (.fineParticles, readings.europeanAqiPm25),
                (.ozone, readings.europeanAqiOzone), (.nitrogenDioxide, readings.europeanAqiNitrogenDioxide),
                (.sulphurDioxide, readings.europeanAqiSulphurDioxide),
            ]
        }
        guard let index else { return nil }
        // The first listed wins a tie. Coarse particles come before fine ones: when PM10 is as bad as
        // PM2.5 the air is dusty, whereas smoke shows up far more in PM2.5.
        var main: (pollutant: Pollutant, value: Int)?
        for (pollutant, value) in subIndices {
            if let value, value > (main?.value ?? .min) { main = (pollutant, value) }
        }
        var pollutant = main?.pollutant
        if pollutant == .fineParticles, isDusty(pm25: readings.pm25, pm10: readings.pm10) { pollutant = .coarseParticles }
        return AirQuality(index: index, scale: scale, mainPollutant: pollutant)
    }

    /// Fine particles are under this share of PM10 in dust (Riyadh's dust storm on 11-07 was 0.16),
    /// against 0.5 to 0.7 in city air and 0.8 or more in smoke.
    static let dustyFineShare = 0.35
    /// Below this much PM10 (µg/m³) the mix isn't worth naming as dust.
    static let dustyPm10 = 50

    /// Particles that are mostly coarse, by mass. A dust storm can push PM2.5's index off the top of
    /// the scale while PM10's has none at all (Open-Meteo gives no US PM10 index above about 600
    /// µg/m³), so the indices alone would call it smoke.
    static func isDusty(pm25: Int?, pm10: Int?) -> Bool {
        guard let pm25, let pm10, pm10 >= dustyPm10 else { return false }
        return Double(pm25) < dustyFineShare * Double(pm10)
    }
}

/// Open-Meteo's hourly air quality forecast: one request feeds both the walk planner and the Air
/// quality tile, which shows the hour in progress.
struct AirQualityHourlyResponse: Decodable, Sendable {
    let timezone: String?
    /// Each hour's start in Unix seconds, with its readings.
    let hours: [(time: Int, readings: AirQualityReadings)]

    private enum CodingKeys: String, CodingKey { case timezone, hourly }
    private struct FieldKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(timezone: String?, hours: [(time: Int, readings: AirQualityReadings)]) {
        self.timezone = timezone
        self.hours = hours
    }

    /// The hourly block is a list per field, so it's turned round into readings per hour.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        let hourly = try container.nestedContainer(keyedBy: FieldKey.self, forKey: .hourly)
        let times = try hourly.decode([Int].self, forKey: FieldKey(stringValue: "time"))
        // Read as numbers and rounded: the indices are whole, the particle masses (µg/m³) aren't.
        var columns: [AirQualityReadings.Field: [Int?]] = [:]
        for field in AirQualityReadings.Field.allCases {
            columns[field] = try hourly.decodeIfPresent([Double?].self, forKey: FieldKey(stringValue: field.rawValue))?
                .map { $0.map { Int($0.rounded()) } }
        }
        hours = times.indices.map { row in
            (times[row], AirQualityReadings { field in
                guard let column = columns[field] ?? nil, row < column.count else { return nil }
                return column[row]
            })
        }
    }

    /// Each hour's air quality on the city's scale, by the hour's start in Unix seconds.
    var byHour: [Int: AirQuality] {
        byHour(on: .forTimeZone(timezone))
    }

    /// Each hour's air quality on `scale`, by the hour's start in Unix seconds.
    func byHour(on scale: AirQuality.Scale) -> [Int: AirQuality] {
        var result: [Int: AirQuality] = [:]
        for (time, readings) in hours {
            if let air = AirQuality.from(readings, scale: scale) { result[time] = air }
        }
        return result
    }
}

/// One hour's indices from Open-Meteo, overall and per pollutant, on both scales, and the particle
/// masses that tell dust from smoke.
struct AirQualityReadings: Equatable, Sendable {
    enum Field: String, CaseIterable, Sendable {
        case usAqi = "us_aqi"
        case usAqiPm25 = "us_aqi_pm2_5"
        case usAqiPm10 = "us_aqi_pm10"
        case usAqiOzone = "us_aqi_ozone"
        case usAqiNitrogenDioxide = "us_aqi_nitrogen_dioxide"
        case usAqiSulphurDioxide = "us_aqi_sulphur_dioxide"
        case usAqiCarbonMonoxide = "us_aqi_carbon_monoxide"
        case europeanAqi = "european_aqi"
        case europeanAqiPm25 = "european_aqi_pm2_5"
        case europeanAqiPm10 = "european_aqi_pm10"
        case europeanAqiOzone = "european_aqi_ozone"
        case europeanAqiNitrogenDioxide = "european_aqi_nitrogen_dioxide"
        case europeanAqiSulphurDioxide = "european_aqi_sulphur_dioxide"
        case pm25 = "pm2_5"
        case pm10
    }

    /// What to ask Open-Meteo for: `scale`'s index and its pollutants' sub-indices, with the
    /// particle masses that tell dust from smoke (9 fields for the US, 8 for Europe). Both scales
    /// (15) when the city's time zone, and so its scale, isn't known. Open-Meteo counts more than
    /// 10 fields as more than one call. The same lists as on Android.
    static func fields(for scale: AirQuality.Scale?) -> [Field] {
        switch scale {
        case .us:
            [.usAqi, .usAqiPm25, .usAqiPm10, .usAqiOzone, .usAqiNitrogenDioxide, .usAqiSulphurDioxide,
             .usAqiCarbonMonoxide, .pm25, .pm10]
        case .european:
            [.europeanAqi, .europeanAqiPm25, .europeanAqiPm10, .europeanAqiOzone, .europeanAqiNitrogenDioxide,
             .europeanAqiSulphurDioxide, .pm25, .pm10]
        case nil:
            Field.allCases
        }
    }

    private let values: [Field: Int]

    init(_ value: (Field) -> Int?) {
        var values: [Field: Int] = [:]
        for field in Field.allCases { values[field] = value(field) }
        self.values = values
    }

    init(_ values: [Field: Int]) {
        self.values = values
    }

    var usAqi: Int? { values[.usAqi] }
    var usAqiPm25: Int? { values[.usAqiPm25] }
    var usAqiPm10: Int? { values[.usAqiPm10] }
    var usAqiOzone: Int? { values[.usAqiOzone] }
    var usAqiNitrogenDioxide: Int? { values[.usAqiNitrogenDioxide] }
    var usAqiSulphurDioxide: Int? { values[.usAqiSulphurDioxide] }
    var usAqiCarbonMonoxide: Int? { values[.usAqiCarbonMonoxide] }
    var europeanAqi: Int? { values[.europeanAqi] }
    var europeanAqiPm25: Int? { values[.europeanAqiPm25] }
    var europeanAqiPm10: Int? { values[.europeanAqiPm10] }
    var europeanAqiOzone: Int? { values[.europeanAqiOzone] }
    var europeanAqiNitrogenDioxide: Int? { values[.europeanAqiNitrogenDioxide] }
    var europeanAqiSulphurDioxide: Int? { values[.europeanAqiSulphurDioxide] }
    /// Particle masses in µg/m³, rounded.
    var pm25: Int? { values[.pm25] }
    var pm10: Int? { values[.pm10] }
}

/// A city's air quality hours as last fetched, kept with the city's cached weather so a refresh
/// within `maxAge` (the background one too, which may run in a fresh process) can reuse them
/// instead of asking again: air quality changes slowly, and each response holds two days of hours.
/// The same rules as on Android.
struct AirQualityHours: Codable, Equatable, Sendable {
    /// How long fetched air quality is reused for.
    static let maxAge: TimeInterval = 3 * 60 * 60
    /// How far ahead from now the hours must reach to be reused.
    static let coverage: TimeInterval = 24 * 60 * 60

    let fetchedAt: Date
    let scale: AirQuality.Scale
    /// Each hour's air quality, by the hour's start in Unix seconds.
    let byHour: [Int: AirQuality]

    /// Fetched under `maxAge` ago, on `scale`, and reaching from the hour in progress to at least
    /// `coverage` from `now`.
    func canBeReused(on scale: AirQuality.Scale, now: Date) -> Bool {
        guard scale == self.scale,
              (0 ..< Self.maxAge).contains(now.timeIntervalSince(fetchedAt)),
              let first = byHour.keys.min(), let last = byHour.keys.max() else { return false }
        let nowSeconds = now.timeIntervalSince1970
        return TimeInterval(first) <= nowSeconds && TimeInterval(last + 3600) >= nowSeconds + Self.coverage
    }
}
