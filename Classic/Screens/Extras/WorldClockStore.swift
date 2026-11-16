//
//  WorldClockStore.swift
//  Classic
//

import UIKit

/// One clock in the user's list: a display name plus an IANA time zone.
struct WorldClock: Codable, Equatable {
    var city: String
    var timeZoneID: String

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
}

struct ClockCity {
    let name: String
    let timeZoneID: String
}

struct ClockRegion {
    let name: String
    let cities: [ClockCity]   // alphabetical
}

/// Ordered list of world clocks, persisted in UserDefaults.
final class WorldClockStore {
    static let shared = WorldClockStore()

    private let listKey = "classic.clocks.list"
    private let defaults = UserDefaults.standard

    private(set) var clocks: [WorldClock] = []

    private init() {
        load()
    }

    // MARK: Persistence

    private func load() {
        if let data = defaults.data(forKey: listKey),
           let decoded = try? JSONDecoder().decode([WorldClock].self, from: data) {
            clocks = decoded.filter { TimeZone(identifier: $0.timeZoneID) != nil }
        }
        if clocks.isEmpty {
            let tz = TimeZone.current
            clocks = [WorldClock(city: WorldClockStore.cityName(fromIdentifier: tz.identifier), timeZoneID: tz.identifier)]
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(clocks) {
            defaults.set(data, forKey: listKey)
        }
    }

    // MARK: Mutation

    @discardableResult
    func add(_ clock: WorldClock) -> Int {
        clocks.append(clock)
        save()
        return clocks.count - 1
    }

    func replace(at index: Int, with clock: WorldClock) {
        guard clocks.indices.contains(index) else { add(clock); return }
        clocks[index] = clock
        save()
    }

    /// Removes a clock. The last remaining clock can't be deleted.
    @discardableResult
    func remove(at index: Int) -> Bool {
        guard clocks.count > 1, clocks.indices.contains(index) else { return false }
        clocks.remove(at: index)
        save()
        return true
    }

    var canDelete: Bool { clocks.count > 1 }

    // MARK: Helpers

    /// "Europe/London" → "London", "America/New_York" → "New York".
    static func cityName(fromIdentifier id: String) -> String {
        let last = id.split(separator: "/").last.map(String.init) ?? id
        let name = last.replacingOccurrences(of: "_", with: " ")
        return name.isEmpty ? "Local" : name
    }

    /// Daytime is 6am–6pm local to the clock's time zone.
    static func isDaytime(in timeZone: TimeZone, at date: Date = Date()) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let hour = cal.component(.hour, from: date)
        return hour >= 6 && hour < 18
    }

    // MARK: Formatting (cached per time zone)

    private static var formatterCache: [String: DateFormatter] = [:]

    private static func formatter(_ kind: String, _ format: String, template: Bool, tz: TimeZone) -> DateFormatter {
        let key = kind + "|" + tz.identifier
        if let f = formatterCache[key] { return f }
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeZone = tz
        if template {
            f.setLocalizedDateFormatFromTemplate(format)
        } else {
            f.dateFormat = format
        }
        formatterCache[key] = f
        return f
    }

    /// "5:24 PM" or "17:24" depending on the user's locale.
    static func timeString(_ date: Date, in tz: TimeZone) -> String {
        formatter("time", "jmm", template: true, tz: tz).string(from: date)
    }

    /// "Tuesday"
    static func weekdayString(_ date: Date, in tz: TimeZone) -> String {
        formatter("weekday", "EEEE", template: false, tz: tz).string(from: date)
    }

    /// "Oct 18 2005"
    static func shortDateString(_ date: Date, in tz: TimeZone) -> String {
        formatter("date", "MMM d yyyy", template: false, tz: tz).string(from: date)
    }

    /// "Tuesday, Oct 18 2005"
    static func fullDateString(_ date: Date, in tz: TimeZone) -> String {
        formatter("fulldate", "EEEE, MMM d yyyy", template: false, tz: tz).string(from: date)
    }

    // MARK: City catalogue

    static let regions: [ClockRegion] = {
        let raw: [(String, [(String, String)])] = [
            ("Africa", [
                ("Accra", "Africa/Accra"),
                ("Addis Ababa", "Africa/Addis_Ababa"),
                ("Algiers", "Africa/Algiers"),
                ("Cairo", "Africa/Cairo"),
                ("Cape Town", "Africa/Johannesburg"),
                ("Casablanca", "Africa/Casablanca"),
                ("Dakar", "Africa/Dakar"),
                ("Dar es Salaam", "Africa/Dar_es_Salaam"),
                ("Johannesburg", "Africa/Johannesburg"),
                ("Kampala", "Africa/Kampala"),
                ("Khartoum", "Africa/Khartoum"),
                ("Kinshasa", "Africa/Kinshasa"),
                ("Lagos", "Africa/Lagos"),
                ("Luanda", "Africa/Luanda"),
                ("Nairobi", "Africa/Nairobi"),
                ("Tunis", "Africa/Tunis"),
            ]),
            ("Asia", [
                ("Bangkok", "Asia/Bangkok"),
                ("Beijing", "Asia/Shanghai"),
                ("Dhaka", "Asia/Dhaka"),
                ("Dubai", "Asia/Dubai"),
                ("Hong Kong", "Asia/Hong_Kong"),
                ("Jakarta", "Asia/Jakarta"),
                ("Jerusalem", "Asia/Jerusalem"),
                ("Karachi", "Asia/Karachi"),
                ("Kathmandu", "Asia/Kathmandu"),
                ("Kolkata", "Asia/Kolkata"),
                ("Kuala Lumpur", "Asia/Kuala_Lumpur"),
                ("Manila", "Asia/Manila"),
                ("Mumbai", "Asia/Kolkata"),
                ("New Delhi", "Asia/Kolkata"),
                ("Riyadh", "Asia/Riyadh"),
                ("Seoul", "Asia/Seoul"),
                ("Shanghai", "Asia/Shanghai"),
                ("Singapore", "Asia/Singapore"),
                ("Taipei", "Asia/Taipei"),
                ("Tehran", "Asia/Tehran"),
                ("Tokyo", "Asia/Tokyo"),
            ]),
            ("Australia & Pacific", [
                ("Adelaide", "Australia/Adelaide"),
                ("Auckland", "Pacific/Auckland"),
                ("Brisbane", "Australia/Brisbane"),
                ("Darwin", "Australia/Darwin"),
                ("Fiji", "Pacific/Fiji"),
                ("Guam", "Pacific/Guam"),
                ("Hobart", "Australia/Hobart"),
                ("Honolulu", "Pacific/Honolulu"),
                ("Melbourne", "Australia/Melbourne"),
                ("Nouméa", "Pacific/Noumea"),
                ("Perth", "Australia/Perth"),
                ("Port Moresby", "Pacific/Port_Moresby"),
                ("Samoa", "Pacific/Apia"),
                ("Sydney", "Australia/Sydney"),
                ("Tahiti", "Pacific/Tahiti"),
                ("Tonga", "Pacific/Tongatapu"),
                ("Wellington", "Pacific/Auckland"),
            ]),
            ("Europe", [
                ("Amsterdam", "Europe/Amsterdam"),
                ("Athens", "Europe/Athens"),
                ("Berlin", "Europe/Berlin"),
                ("Brussels", "Europe/Brussels"),
                ("Copenhagen", "Europe/Copenhagen"),
                ("Dublin", "Europe/Dublin"),
                ("Edinburgh", "Europe/London"),
                ("Helsinki", "Europe/Helsinki"),
                ("Istanbul", "Europe/Istanbul"),
                ("Kyiv", "Europe/Kiev"),
                ("Lisbon", "Europe/Lisbon"),
                ("London", "Europe/London"),
                ("Madrid", "Europe/Madrid"),
                ("Moscow", "Europe/Moscow"),
                ("Oslo", "Europe/Oslo"),
                ("Paris", "Europe/Paris"),
                ("Prague", "Europe/Prague"),
                ("Reykjavik", "Atlantic/Reykjavik"),
                ("Rome", "Europe/Rome"),
                ("Stockholm", "Europe/Stockholm"),
                ("Vienna", "Europe/Vienna"),
                ("Warsaw", "Europe/Warsaw"),
                ("Zurich", "Europe/Zurich"),
            ]),
            ("North America", [
                ("Anchorage", "America/Anchorage"),
                ("Atlanta", "America/New_York"),
                ("Boston", "America/New_York"),
                ("California", "America/Los_Angeles"),
                ("Chicago", "America/Chicago"),
                ("Cupertino", "America/Los_Angeles"),
                ("Dallas", "America/Chicago"),
                ("Denver", "America/Denver"),
                ("Halifax", "America/Halifax"),
                ("Havana", "America/Havana"),
                ("Los Angeles", "America/Los_Angeles"),
                ("Mexico City", "America/Mexico_City"),
                ("Montreal", "America/Toronto"),
                ("New York", "America/New_York"),
                ("Phoenix", "America/Phoenix"),
                ("San Francisco", "America/Los_Angeles"),
                ("Seattle", "America/Los_Angeles"),
                ("St. John's", "America/St_Johns"),
                ("Toronto", "America/Toronto"),
                ("Vancouver", "America/Vancouver"),
                ("Washington, D.C.", "America/New_York"),
            ]),
            ("South America", [
                ("Asunción", "America/Asuncion"),
                ("Bogotá", "America/Bogota"),
                ("Brasília", "America/Sao_Paulo"),
                ("Buenos Aires", "America/Argentina/Buenos_Aires"),
                ("Caracas", "America/Caracas"),
                ("Guayaquil", "America/Guayaquil"),
                ("La Paz", "America/La_Paz"),
                ("Lima", "America/Lima"),
                ("Montevideo", "America/Montevideo"),
                ("Quito", "America/Guayaquil"),
                ("Rio de Janeiro", "America/Sao_Paulo"),
                ("Santiago", "America/Santiago"),
                ("São Paulo", "America/Sao_Paulo"),
            ]),
        ]
        return raw.map { region, cities in
            let valid = cities
                .filter { TimeZone(identifier: $0.1) != nil }
                .map { ClockCity(name: $0.0, timeZoneID: $0.1) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return ClockRegion(name: region, cities: valid)
        }.filter { !$0.cities.isEmpty }
    }()
}
