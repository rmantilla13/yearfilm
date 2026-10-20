import Foundation
import Testing
@testable import Yearfilm

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}

struct FilmWeekTests {
    @Test func januaryFirstIsWeekOne() {
        #expect(FilmWeek(date: day(2026, 1, 1), calendar: utc) == FilmWeek(year: 2026, week: 1))
        #expect(FilmWeek(date: day(2026, 1, 7), calendar: utc).week == 1)
        #expect(FilmWeek(date: day(2026, 1, 8), calendar: utc).week == 2)
    }

    @Test func newYearsEveBelongsToThisYearsFilm() {
        // An ISO week would call Dec 31 "week 1" of next year; the film must not.
        let week = FilmWeek(date: day(2026, 12, 31), calendar: utc)
        #expect(week.year == 2026)
        #expect(week.week == 52)
        #expect(FilmWeek(date: day(2028, 12, 31), calendar: utc).week == 52)  // leap year
    }

    @Test func weekNumbersAreClamped() {
        #expect(FilmWeek(year: 2026, week: 0).week == 1)
        #expect(FilmWeek(year: 2026, week: 60).week == 52)
    }

    @Test func seasonsMatchThePlanner() {
        #expect(FilmWeek(date: day(2026, 2, 10), calendar: utc).season(calendar: utc) == .winter)
        #expect(FilmWeek(date: day(2026, 7, 4), calendar: utc).season(calendar: utc) == .summer)
        #expect(FilmWeek(date: day(2026, 12, 24), calendar: utc).season(calendar: utc) == .holidays)
    }

    @Test func ordering() {
        #expect(FilmWeek(year: 2026, week: 3) < FilmWeek(year: 2026, week: 4))
        #expect(FilmWeek(year: 2025, week: 52) < FilmWeek(year: 2026, week: 1))
    }
}

struct ShotPromptTests {
    @Test func sameWeekSamePrompt() {
        let week = FilmWeek(year: 2026, week: 10)
        #expect(ShotPrompt.forWeek(week, calendar: utc) == ShotPrompt.forWeek(week, calendar: utc))
    }

    @Test func everyWeekHasAPrompt() {
        for w in 1...FilmWeek.count {
            #expect(!ShotPrompt.forWeek(FilmWeek(year: 2026, week: w), calendar: utc).isEmpty)
        }
    }
}

struct PremiereTests {
    @Test func countsDownToDecember20() {
        #expect(Premiere.daysUntil(from: day(2026, 12, 19), calendar: utc) == 1)
        #expect(Premiere.daysUntil(from: day(2026, 12, 20), calendar: utc) == 0)
        #expect(Premiere.daysUntil(from: day(2026, 12, 25), calendar: utc) < 0)
    }
}

struct ReminderTests {
    @Test func sundaysAtSixAfterNow() {
        let now = day(2026, 10, 20)  // a Tuesday
        let dates = Reminders.dates(after: now, count: 3, calendar: utc)
        #expect(dates.count == 3)
        for date in dates {
            #expect(utc.component(.weekday, from: date) == 1)
            #expect(utc.component(.hour, from: date) == 18)
            #expect(date > now)
        }
        #expect(utc.dateComponents([.day], from: dates[0], to: dates[1]).day == 7)
    }

    @Test func sundayAfterSixSkipsToNextWeek() {
        let lateSunday = day(2026, 10, 25, hour: 19)
        let first = Reminders.dates(after: lateSunday, count: 1, calendar: utc)[0]
        #expect(first == utc.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 18))!)
    }
}
