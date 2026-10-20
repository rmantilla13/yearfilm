import CoreImage
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

struct UploadItemTests {
    @Test func capturedOnIsTheLocalCalendarDay() {
        // 11pm on Dec 31 in Los Angeles is already Jan 1 in UTC; the film must call it 2026.
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let lateNYE = la.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23))!
        #expect(UploadItem.localDay(lateNYE, calendar: la) == "2026-12-31")
        #expect(UploadItem.localDay(lateNYE, calendar: utc) == "2027-01-01")
    }
}

@MainActor
struct InviteTests {
    let token = "AbCdEfGhIjKlMnOpQrStUvWxYz012-_9"

    @Test func readsBothLinkShapes() {
        #expect(Account.PendingInvite(url: URL(string: "yearfilm://join/\(token)")!)?.token == token)
        #expect(Account.PendingInvite(url: URL(string: "https://www.yearfilm.com/join/\(token)")!)?.token == token)
    }

    @Test func ignoresAnythingElse() {
        #expect(Account.PendingInvite(url: URL(string: "yearfilm://join/short")!) == nil)
        #expect(Account.PendingInvite(url: URL(string: "yearfilm://other/\(token)")!) == nil)
        #expect(Account.PendingInvite(url: URL(string: "https://www.yearfilm.com/join/\(token)/extra")!) == nil)
    }

    @Test func weekLimitedContributorsOnlySendTheirWeeks() throws {
        let json = #"{"id":"0b4e7a52-6c1f-4a8e-9a3d-2f6b1c9e8d70","name":"The Garcias","role":"contributor","weeks":[47,48],"year":2026}"#
        let family = try JSONDecoder().decode(Account.Family.self, from: Data(json.utf8))
        #expect(family.allows(FilmWeek(year: 2026, week: 48)))
        #expect(!family.allows(FilmWeek(year: 2026, week: 11)))
        #expect(!family.allows(FilmWeek(year: 2025, week: 48)))
    }

    @Test func weeksReadLikeTheWebsite() {
        #expect(weeksLabel(nil, year: nil) == "any week")
        #expect(weeksLabel([30], year: 2026) == "week 30 of 2026")
        #expect(weeksLabel([1, 2, 3, 10, 12, 13], year: nil) == "weeks 1–3, 10, 12–13")
    }
}

struct RoughCutPlanTests {
    private func clip(_ m: Int, _ d: Int, seconds: Double = 10) -> RoughCutPlan.Source {
        .init(id: UUID(), url: URL(fileURLWithPath: "/c\(m)-\(d).mov"), capturedOn: day(2026, m, d), duration: seconds)
    }

    @Test func shotsRunInFilmedOrderWithACardPerSeason() {
        let plan = RoughCutPlan.make(clips: [clip(7, 4), clip(1, 10), clip(1, 20)], notes: [], calendar: utc)
        #expect(plan.chapters.map(\.season) == [.winter, .summer])
        guard case .card(.winter, _) = plan.pieces[0], case .shot(let first, let from, let s) = plan.pieces[1] else {
            Issue.record("expected a winter card, then a shot"); return
        }
        #expect(first.capturedOn == day(2026, 1, 10))
        #expect(s == RoughCutPlan.shotSeconds)
        #expect(from == (10 - RoughCutPlan.shotSeconds) / 2)  // from the middle of the clip
        #expect(abs(plan.duration - (2 * RoughCutPlan.cardSeconds + 3 * RoughCutPlan.shotSeconds)) < 1e-9)
    }

    @Test func tooShortClipsAreLeftOutAndShortOnesKeptWhole() {
        let plan = RoughCutPlan.make(clips: [clip(3, 1, seconds: 0.3), clip(3, 2, seconds: 1.5)], notes: [], calendar: utc)
        #expect(plan.pieces.count == 2)
        #expect(plan.pieces.last?.seconds == 1.5)
    }

    @Test func aBigYearIsSampledAcrossTheWholeYear() {
        let clips = (1...12).flatMap { m in (1...20).map { clip(m, $0) } }
        let plan = RoughCutPlan.make(clips: clips, notes: [], maxShots: 24, calendar: utc)
        let shots = plan.pieces.filter { if case .shot = $0 { true } else { false } }
        #expect(shots.count == 24)
        #expect(Set(plan.chapters.map(\.season)) == Set(Season.allCases))
    }

    @Test func notesNarrateTheirWeekWithoutOverlapping() {
        let jan10 = clip(1, 10), jan11 = clip(1, 11)
        let week = FilmWeek(date: day(2026, 1, 10), calendar: utc)
        let note = { RoughCutPlan.Note(id: UUID(), url: URL(fileURLWithPath: "/n.m4a"), week: $0, duration: 20) }
        let plan = RoughCutPlan.make(
            clips: [jan10, jan11],
            notes: [note(week), note(FilmWeek(year: 2026, week: 30))],  // week 30 has no shots
            calendar: utc
        )
        #expect(plan.narration.count == 1)
        #expect(plan.narration[0].at == RoughCutPlan.cardSeconds)
        #expect(abs(plan.narration[0].seconds - (plan.duration - RoughCutPlan.cardSeconds)) < 1e-9)  // trimmed to the cut
    }

    @Test func nothingFilmedMeansNothingToCut() {
        #expect(RoughCutPlan.make(clips: [], notes: [], calendar: utc).isEmpty)
    }
}

struct FramingTests {
    private let tv = CGSize(width: 1280, height: 720)

    @Test func iPhonePortraitTransformsStandUpright() {
        #expect(RoughCut.orientation(of: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)) == .right)
        #expect(RoughCut.orientation(of: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)) == .left)
        #expect(RoughCut.orientation(of: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)) == .down)
        #expect(RoughCut.orientation(of: .identity) == .up)
    }

    @Test func everyFrameIsExactly16x9() {
        let landscape = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        // A portrait phone clip: landscape pixels plus a quarter turn.
        let portrait = landscape
        #expect(RoughCut.frame(landscape, orientation: .up, in: tv).extent == CGRect(origin: .zero, size: tv))
        #expect(RoughCut.frame(portrait, orientation: .right, in: tv).extent == CGRect(origin: .zero, size: tv))
        let square = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 500, height: 500))
        #expect(RoughCut.frame(square, orientation: .up, in: tv).extent == CGRect(origin: .zero, size: tv))
    }
}
