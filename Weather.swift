import Foundation

enum WeatherIntent: Equatable {
    case forecast(city: String?, tomorrow: Bool)
    case setCity(String)

    static func match(_ input: String) -> Self? {
        let text = clean(input)
        for prefix in ["把天气城市设为", "天气城市设为", "天气城市改成", "天气城市设置为"] {
            if text.hasPrefix(prefix), let city = cityName(String(text.dropFirst(prefix.count))) {
                return .setCity(city)
            }
        }
        guard let word = text.range(of: "天气", options: .backwards) else { return nil }
        let suffix = clean(String(text[word.upperBound...]))
        let endings = ["", "怎么样", "如何", "好吗", "怎样", "预报", "预报怎么样", "冷不冷", "会下雨吗"]
        guard endings.contains(suffix) else { return nil }

        let tomorrow = text.contains("明天")
        var prefix = String(text[..<word.lowerBound])
        for polite in ["请帮我查一下", "帮我查一下", "给我查一下", "帮我看看", "请问", "帮我查", "查一下", "看看", "查询"] {
            if prefix.hasPrefix(polite) {
                prefix = String(prefix.dropFirst(polite.count))
                break
            }
        }
        let timeWords = ["今天的", "明天的", "现在的", "今天", "明天", "现在", "当地"]
        for time in timeWords {
            prefix = prefix.replacingOccurrences(of: time, with: "")
        }
        prefix = clean(prefix)
        if prefix.hasSuffix("的") { prefix = clean(String(prefix.dropLast())) }
        if prefix.isEmpty || ["这里", "本地", "我这儿", "我这里"].contains(prefix) {
            return .forecast(city: nil, tomorrow: tomorrow)
        }
        guard let city = cityName(prefix) else { return nil }
        return .forecast(city: city, tomorrow: tomorrow)
    }

    static func cityName(_ raw: String) -> String? {
        var name = clean(raw)
        for prefix in ["我的城市是", "我在", "城市是"] where name.hasPrefix(prefix) {
            name = clean(String(name.dropFirst(prefix.count)))
            break
        }
        guard (2...42).contains(name.count),
              name.allSatisfy({ $0.isLetter || $0.isWhitespace || $0 == "-" || $0 == "'" || $0 == "." || $0 == "·" })
        else { return nil }
        return name
    }

    private static func clean(_ value: String) -> String {
        let marks = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "？?！!。。，,：:"))
        return value.trimmingCharacters(in: marks)
    }
}

struct WeatherService {
    var session = URLSession.shared

    struct Place: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    private struct Search: Decodable { let results: [Place]? }

    struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
        }
        struct Daily: Decodable {
            let weather_code: [Int]
            let temperature_2m_min: [Double]
            let temperature_2m_max: [Double]
            let precipitation_probability_max: [Int?]?
        }
        let current: Current
        let daily: Daily

        func reply(for place: Place, tomorrow: Bool) throws -> String {
            let day = tomorrow ? 1 : 0
            guard daily.temperature_2m_min.indices.contains(day),
                  daily.temperature_2m_max.indices.contains(day),
                  daily.weather_code.indices.contains(day) else { throw Failure.unavailable }
            let low = Int(daily.temperature_2m_min[day].rounded())
            let high = Int(daily.temperature_2m_max[day].rounded())
            let rain = daily.precipitation_probability_max.flatMap { $0.indices.contains(day) ? $0[day] : nil }
            let condition = Self.condition(daily.weather_code[day])
            let summary: String
            if tomorrow {
                summary = "\(place.name)明天\(condition)，\(low)–\(high)°C"
            } else {
                summary = "\(place.name)现在\(Self.condition(current.weather_code))，\(Int(current.temperature_2m.rounded()))°C，今天\(low)–\(high)°C"
            }
            return summary + (rain.map { "，降雨概率最高 \($0)%" } ?? "") + "。\n数据：Open-Meteo"
        }

        private static func condition(_ code: Int) -> String {
            switch code {
            case 0: return "晴"
            case 1: return "大致晴朗"
            case 2: return "多云"
            case 3: return "阴"
            case 45, 48: return "有雾"
            case 51...57: return "有毛毛雨"
            case 61...67, 80...82: return "有雨"
            case 71...77, 85, 86: return "有雪"
            case 95...99: return "有雷雨"
            default: return "天气情况暂缺"
            }
        }
    }

    enum Failure: LocalizedError {
        case cityNotFound, unavailable
        var errorDescription: String? {
            switch self {
            case .cityNotFound: return "没找到这个城市，试试更完整的地名。"
            case .unavailable: return "天气暂时查不到，等会儿再试。"
            }
        }
    }

    func place(named city: String) async throws -> Place {
        let query = city.hasSuffix("市") && city.count > 2 ? String(city.dropLast()) : city
        let search: Search = try await fetch("https://geocoding-api.open-meteo.com/v1/search", [
            .init(name: "name", value: query), .init(name: "language", value: "zh"),
            .init(name: "count", value: "1")
        ])
        guard let place = search.results?.first else { throw Failure.cityNotFound }
        return place
    }

    func forecast(for place: Place) async throws -> Forecast {
        try await fetch("https://api.open-meteo.com/v1/forecast", [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_min,temperature_2m_max,precipitation_probability_max"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "2")
        ])
    }

    private func fetch<Value: Decodable>(_ endpoint: String, _ query: [URLQueryItem]) async throws -> Value {
        var components = URLComponents(string: endpoint)
        components?.queryItems = query
        guard let url = components?.url else { throw Failure.unavailable }
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 12))
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw Failure.unavailable
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
