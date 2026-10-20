import Foundation

/// A week of the film year. Counted from January 1 so a film year is exactly a
/// calendar year: a clip shot on Dec 31 belongs to this year's film, never to
/// "week 1" of the next one the way an ISO week would file it.
struct FilmWeek: Hashable, Comparable, Codable {
    static let count = 52

    let year: Int
    let week: Int  // 1...52; the last day or two of the year fold into week 52

    init(year: Int, week: Int) {
        self.year = year
        self.week = min(max(week, 1), Self.count)
    }

    init(date: Date, calendar: Calendar = .current) {
        let year = calendar.component(.year, from: date)
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        self.init(year: year, week: (day - 1) / 7 + 1)
    }

    static func < (a: FilmWeek, b: FilmWeek) -> Bool {
        (a.year, a.week) < (b.year, b.week)
    }

    func start(calendar: Calendar = .current) -> Date {
        let jan1 = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        return calendar.date(byAdding: .day, value: (week - 1) * 7, to: jan1)!
    }

    func season(calendar: Calendar = .current) -> Season {
        Season(month: calendar.component(.month, from: start(calendar: calendar)))
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        FilmWeek(date: date, calendar: calendar) == self
    }
}

/// The film's acts. Mirrors ACTS in yearfilm/plan.py - keep them in step.
enum Season: Int, CaseIterable, Codable {
    case winter, spring, summer, fall, holidays

    init(month: Int) {
        switch month {
        case 1, 2: self = .winter
        case 3...5: self = .spring
        case 6...8: self = .summer
        case 9...11: self = .fall
        default: self = .holidays
        }
    }

    var title: String {
        switch self {
        case .winter: "Winter"
        case .spring: "Spring"
        case .summer: "Summer"
        case .fall: "Fall"
        case .holidays: "The Holidays"
        }
    }
}

/// The night the film unlocks. One date for everyone, so families premiere together.
enum Premiere {
    static func date(year: Int, calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: 12, day: 20, hour: 18))!
    }

    static func daysUntil(from now: Date = .now, calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: now)
        let start = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date(year: year, calendar: calendar))
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }
}
