import Foundation

/// Response of Open-Meteo's /v1/forecast with `timeformat=unixtime` and `timezone=auto`.
struct OpenMeteoResponse: Decodable {
    /// The location's offset from UTC, in seconds (`timezone=auto` resolves it from the coordinates).
    var utcOffsetSeconds: Int = 0
    /// IANA zone name (e.g. "Europe/London"), so DST changes inside the forecast window are honoured.
    var timezone: String? = nil
    var hourly = OpenMeteoHourlyDTO()
    var minutely15 = OpenMeteoMinutely15DTO()
    var daily = OpenMeteoDailyDTO()

    enum CodingKeys: String, CodingKey {
        case utcOffsetSeconds = "utc_offset_seconds"
        case timezone
        case hourly
        case minutely15 = "minutely_15"
        case daily
    }

    init(
        utcOffsetSeconds: Int = 0,
        timezone: String? = nil,
        hourly: OpenMeteoHourlyDTO = OpenMeteoHourlyDTO(),
        minutely15: OpenMeteoMinutely15DTO = OpenMeteoMinutely15DTO(),
        daily: OpenMeteoDailyDTO = OpenMeteoDailyDTO()
    ) {
        self.utcOffsetSeconds = utcOffsetSeconds
        self.timezone = timezone
        self.hourly = hourly
        self.minutely15 = minutely15
        self.daily = daily
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        utcOffsetSeconds = try container.decodeIfPresent(Int.self, forKey: .utcOffsetSeconds) ?? 0
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        hourly = try container.decodeIfPresent(OpenMeteoHourlyDTO.self, forKey: .hourly) ?? OpenMeteoHourlyDTO()
        minutely15 = try container.decodeIfPresent(OpenMeteoMinutely15DTO.self, forKey: .minutely15) ?? OpenMeteoMinutely15DTO()
        daily = try container.decodeIfPresent(OpenMeteoDailyDTO.self, forKey: .daily) ?? OpenMeteoDailyDTO()
    }
}

/// Parallel arrays, one entry per local day from `time[i]`, its midnight. In a polar night both
/// times are that midnight, and in a polar day the sunset is the next one.
struct OpenMeteoDailyDTO: Decodable {
    var time: [Int] = []
    var sunrise: [Int?] = []
    var sunset: [Int?] = []
    /// Asked for only with the current reading, for the day's high and low.
    var temperatureMax: [Double?] = []
    var temperatureMin: [Double?] = []

    init(
        time: [Int] = [],
        sunrise: [Int?] = [],
        sunset: [Int?] = [],
        temperatureMax: [Double?] = [],
        temperatureMin: [Double?] = []
    ) {
        self.time = time
        self.sunrise = sunrise
        self.sunset = sunset
        self.temperatureMax = temperatureMax
        self.temperatureMin = temperatureMin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decodeIfPresent([Int].self, forKey: .time) ?? []
        sunrise = try c.decodeIfPresent([Int?].self, forKey: .sunrise) ?? []
        sunset = try c.decodeIfPresent([Int?].self, forKey: .sunset) ?? []
        temperatureMax = try c.decodeIfPresent([Double?].self, forKey: .temperatureMax) ?? []
        temperatureMin = try c.decodeIfPresent([Double?].self, forKey: .temperatureMin) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case time, sunrise, sunset
        case temperatureMax = "temperature_2m_max"
        case temperatureMin = "temperature_2m_min"
    }
}

/// Response of Open-Meteo's /v1/forecast asked for the `current` reading and today's `daily` values,
/// with `timeformat=unixtime` and `timezone=auto`.
struct OpenMeteoCurrentResponse: Decodable {
    var utcOffsetSeconds: Int = 0
    var current = OpenMeteoCurrentDTO()
    var daily = OpenMeteoDailyDTO()

    enum CodingKeys: String, CodingKey {
        case utcOffsetSeconds = "utc_offset_seconds"
        case current, daily
    }

    init(utcOffsetSeconds: Int = 0, current: OpenMeteoCurrentDTO = OpenMeteoCurrentDTO(), daily: OpenMeteoDailyDTO = OpenMeteoDailyDTO()) {
        self.utcOffsetSeconds = utcOffsetSeconds
        self.current = current
        self.daily = daily
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        utcOffsetSeconds = try c.decodeIfPresent(Int.self, forKey: .utcOffsetSeconds) ?? 0
        current = try c.decodeIfPresent(OpenMeteoCurrentDTO.self, forKey: .current) ?? OpenMeteoCurrentDTO()
        daily = try c.decodeIfPresent(OpenMeteoDailyDTO.self, forKey: .daily) ?? OpenMeteoDailyDTO()
    }
}

/// The model's reading for the current 15 minutes, starting at `time`. Visibility is in metres
/// whatever the units.
struct OpenMeteoCurrentDTO: Decodable, Equatable {
    var time: Int?
    var temperature: Double?
    var apparentTemperature: Double?
    var relativeHumidity: Int?
    var weatherCode: Int?
    var cloudCover: Int?
    var seaLevelPressure: Double?
    var windSpeed: Double?
    var windDirection: Int?
    var windGusts: Double?
    var visibility: Double?
    var isDay: Int?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case relativeHumidity = "relative_humidity_2m"
        case weatherCode = "weather_code"
        case cloudCover = "cloud_cover"
        case seaLevelPressure = "pressure_msl"
        case windSpeed = "wind_speed_10m"
        case windDirection = "wind_direction_10m"
        case windGusts = "wind_gusts_10m"
        case visibility
        case isDay = "is_day"
    }

    init(
        time: Int? = nil,
        temperature: Double? = nil,
        apparentTemperature: Double? = nil,
        relativeHumidity: Int? = nil,
        weatherCode: Int? = nil,
        cloudCover: Int? = nil,
        seaLevelPressure: Double? = nil,
        windSpeed: Double? = nil,
        windDirection: Int? = nil,
        windGusts: Double? = nil,
        visibility: Double? = nil,
        isDay: Int? = nil
    ) {
        self.time = time
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.relativeHumidity = relativeHumidity
        self.weatherCode = weatherCode
        self.cloudCover = cloudCover
        self.seaLevelPressure = seaLevelPressure
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.windGusts = windGusts
        self.visibility = visibility
        self.isDay = isDay
    }
}

/// Parallel arrays in 15-minute steps. Like the hourly ones, the amounts at `time[i]` are totals for
/// the 15 minutes *before* it: rain and snow in mm water, snowfall in cm.
struct OpenMeteoMinutely15DTO: Decodable {
    var time: [Int] = []
    var precipitation: [Double?] = []
    var snowfall: [Double?] = []

    init(time: [Int] = [], precipitation: [Double?] = [], snowfall: [Double?] = []) {
        self.time = time
        self.precipitation = precipitation
        self.snowfall = snowfall
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decodeIfPresent([Int].self, forKey: .time) ?? []
        precipitation = try c.decodeIfPresent([Double?].self, forKey: .precipitation) ?? []
        snowfall = try c.decodeIfPresent([Double?].self, forKey: .snowfall) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case time, precipitation, snowfall
    }
}

/// Parallel arrays: index i of every list describes the hour starting at `time[i]`.
struct OpenMeteoHourlyDTO: Decodable {
    var time: [Int] = []
    var temperature: [Double?] = []
    var apparentTemperature: [Double?] = []
    var precipitationProbability: [Int?] = []
    var weatherCode: [Int?] = []
    var windSpeed: [Double?] = []
    var windDirection: [Int?] = []
    var relativeHumidity: [Int?] = []
    var seaLevelPressure: [Double?] = []
    var uvIndex: [Double?] = []
    var shortwaveRadiation: [Double?] = []
    var isDay: [Int?] = []
    /// Rain and snow over the hour before `time[i]`, in mm; snow lying on the ground, in metres.
    var precipitation: [Double?] = []
    var snowDepth: [Double?] = []

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case precipitationProbability = "precipitation_probability"
        case weatherCode = "weather_code"
        case windSpeed = "wind_speed_10m"
        case windDirection = "wind_direction_10m"
        case relativeHumidity = "relative_humidity_2m"
        case seaLevelPressure = "pressure_msl"
        case uvIndex = "uv_index"
        case shortwaveRadiation = "shortwave_radiation"
        case isDay = "is_day"
        case precipitation
        case snowDepth = "snow_depth"
    }

    init(
        time: [Int] = [],
        temperature: [Double?] = [],
        apparentTemperature: [Double?] = [],
        precipitationProbability: [Int?] = [],
        weatherCode: [Int?] = [],
        windSpeed: [Double?] = [],
        windDirection: [Int?] = [],
        relativeHumidity: [Int?] = [],
        seaLevelPressure: [Double?] = [],
        uvIndex: [Double?] = [],
        shortwaveRadiation: [Double?] = [],
        isDay: [Int?] = [],
        precipitation: [Double?] = [],
        snowDepth: [Double?] = []
    ) {
        self.time = time
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.precipitationProbability = precipitationProbability
        self.weatherCode = weatherCode
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.relativeHumidity = relativeHumidity
        self.seaLevelPressure = seaLevelPressure
        self.uvIndex = uvIndex
        self.shortwaveRadiation = shortwaveRadiation
        self.isDay = isDay
        self.precipitation = precipitation
        self.snowDepth = snowDepth
    }

    /// Missing arrays decode as empty, matching Open-Meteo omitting fields it has no data for.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decodeIfPresent([Int].self, forKey: .time) ?? []
        temperature = try c.decodeIfPresent([Double?].self, forKey: .temperature) ?? []
        apparentTemperature = try c.decodeIfPresent([Double?].self, forKey: .apparentTemperature) ?? []
        precipitationProbability = try c.decodeIfPresent([Int?].self, forKey: .precipitationProbability) ?? []
        weatherCode = try c.decodeIfPresent([Int?].self, forKey: .weatherCode) ?? []
        windSpeed = try c.decodeIfPresent([Double?].self, forKey: .windSpeed) ?? []
        windDirection = try c.decodeIfPresent([Int?].self, forKey: .windDirection) ?? []
        relativeHumidity = try c.decodeIfPresent([Int?].self, forKey: .relativeHumidity) ?? []
        seaLevelPressure = try c.decodeIfPresent([Double?].self, forKey: .seaLevelPressure) ?? []
        uvIndex = try c.decodeIfPresent([Double?].self, forKey: .uvIndex) ?? []
        shortwaveRadiation = try c.decodeIfPresent([Double?].self, forKey: .shortwaveRadiation) ?? []
        isDay = try c.decodeIfPresent([Int?].self, forKey: .isDay) ?? []
        precipitation = try c.decodeIfPresent([Double?].self, forKey: .precipitation) ?? []
        snowDepth = try c.decodeIfPresent([Double?].self, forKey: .snowDepth) ?? []
    }
}

extension Array {
    subscript(ifPresent index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
