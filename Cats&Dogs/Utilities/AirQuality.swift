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
            case .us: ["Good", "Moderate", "Poor for some", "Unhealthy", "Very unhealthy", "Hazardous"]
            case .european: ["Good", "Fair", "Moderate", "Poor", "Very poor", "Extremely poor"]
            }
        }
    }

    enum Pollutant: String, Codable, CaseIterable, Sendable {
        case fineParticles, coarseParticles, ozone, nitrogenDioxide, sulphurDioxide, carbonMonoxide

        var name: String {
            switch self {
            case .fineParticles: "fine particles"
            case .coarseParticles: "coarse particles"
            case .ozone: "ozone"
            case .nitrogenDioxide: "nitrogen dioxide"
            case .sulphurDioxide: "sulphur dioxide"
            case .carbonMonoxide: "carbon monoxide"
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
        mainPollutant.map { "Mostly \($0.name)" }
    }

    /// What the air means for a walk, or for people when there's no dog.
    func line(hasDog: Bool) -> String {
        if hasDog {
            return switch band {
            case 0: "Good air for a long walk"
            case 1: "Fine for most walks"
            case 2: "Short walks for older and flat-faced dogs"
            case 3, 4: "Potty breaks only today"
            default: "Stay in. Potty breaks only"
            }
        }
        return switch band {
        case 0: "Fresh air all round"
        case 1: "Fine for most people"
        case 2: "Sensitive people should take it easy"
        case 3, 4: "Limit time outdoors"
        default: "Stay indoors"
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
                (.fineParticles, readings.usAqiPm25), (.coarseParticles, readings.usAqiPm10),
                (.ozone, readings.usAqiOzone), (.nitrogenDioxide, readings.usAqiNitrogenDioxide),
                (.sulphurDioxide, readings.usAqiSulphurDioxide), (.carbonMonoxide, readings.usAqiCarbonMonoxide),
            ]
        case .european:
            index = readings.europeanAqi
            subIndices = [
                (.fineParticles, readings.europeanAqiPm25), (.coarseParticles, readings.europeanAqiPm10),
                (.ozone, readings.europeanAqiOzone), (.nitrogenDioxide, readings.europeanAqiNitrogenDioxide),
                (.sulphurDioxide, readings.europeanAqiSulphurDioxide),
            ]
        }
        guard let index else { return nil }
        // The first listed wins a tie.
        var main: (pollutant: Pollutant, value: Int)?
        for (pollutant, value) in subIndices {
            if let value, value > (main?.value ?? .min) { main = (pollutant, value) }
        }
        return AirQuality(index: index, scale: scale, mainPollutant: main?.pollutant)
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
        var columns: [AirQualityReadings.Field: [Int?]] = [:]
        for field in AirQualityReadings.Field.allCases {
            columns[field] = try hourly.decodeIfPresent([Int?].self, forKey: FieldKey(stringValue: field.rawValue))
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
        let scale = AirQuality.Scale.forTimeZone(timezone)
        var result: [Int: AirQuality] = [:]
        for (time, readings) in hours {
            if let air = AirQuality.from(readings, scale: scale) { result[time] = air }
        }
        return result
    }
}

/// One hour's indices from Open-Meteo, overall and per pollutant, on both scales.
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
}
