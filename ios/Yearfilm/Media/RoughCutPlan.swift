import Foundation

/// The rough cut as data: which slice of which clip goes where, where the chapter cards fall,
/// and where each week's voice note plays. Pure, so it can be tested; RoughCut turns it into
/// something AVPlayer can play.
///
/// A quick on-phone approximation of the engine's edit (engine/yearfilm/plan.py): shots about
/// 2.4 s long taken from the middle of each clip, in the order they were filmed, a card at
/// each season, and the voice notes as narration. No music, no beat detection, no moment
/// scoring — that's the real film's job.
struct RoughCutPlan: Equatable {
    struct Source: Equatable {
        let id: UUID
        let url: URL
        let capturedOn: Date
        let duration: Double
    }

    struct Note: Equatable {
        let id: UUID
        let url: URL
        let week: FilmWeek
        let duration: Double
    }

    enum Piece: Equatable {
        case card(Season, seconds: Double)
        case shot(Source, from: Double, seconds: Double)

        var seconds: Double {
            switch self {
            case .card(_, let s), .shot(_, _, let s): s
            }
        }
    }

    struct Narration: Equatable {
        let note: Note
        let at: Double
        let seconds: Double
    }

    struct Chapter: Equatable {
        let season: Season
        let start: Double
        let seconds: Double
    }

    var pieces: [Piece] = []
    var narration: [Narration] = []
    var chapters: [Chapter] = []
    var duration: Double { pieces.reduce(0) { $0 + $1.seconds } }
    var isEmpty: Bool { !pieces.contains { if case .shot = $0 { true } else { false } } }

    static let shotSeconds = 2.4
    static let cardSeconds = 3.0
    /// Too short to read as a shot.
    static let shortestShot = 0.8

    static func make(
        clips: [Source],
        notes: [Note],
        maxShots: Int = 60,
        calendar: Calendar = .current
    ) -> RoughCutPlan {
        let usable = clips.filter { $0.duration >= shortestShot }.sorted { $0.capturedOn < $1.capturedOn }
        // Over the budget, keep shots spread evenly across the year rather than the first N.
        let chosen: [Source] = usable.count <= maxShots
            ? usable
            : (0..<maxShots).map { usable[$0 * usable.count / maxShots] }

        var plan = RoughCutPlan()
        var season: Season?
        var t = 0.0
        var firstShotOfWeek: [FilmWeek: Double] = [:]

        for clip in chosen {
            let s = Season(month: calendar.component(.month, from: clip.capturedOn))
            if s != season {
                plan.chapters.append(Chapter(season: s, start: t, seconds: cardSeconds))
                plan.pieces.append(.card(s, seconds: cardSeconds))
                t += cardSeconds
                season = s
            }
            let seconds = min(shotSeconds, clip.duration)
            let from = max(0, (clip.duration - seconds) / 2)  // the middle: past the fumble, before the stop
            let week = FilmWeek(date: clip.capturedOn, calendar: calendar)
            if firstShotOfWeek[week] == nil { firstShotOfWeek[week] = t }
            plan.pieces.append(.shot(clip, from: from, seconds: seconds))
            t += seconds
        }

        // One note per week, starting with that week's first shot, never overlapping the last one.
        var lastEnd = 0.0
        let byWeek = Dictionary(grouping: notes, by: \.week)
        for week in byWeek.keys.sorted() {
            guard let start = firstShotOfWeek[week], let note = byWeek[week]?.first else { continue }
            let at = max(start, lastEnd)
            let seconds = min(note.duration, plan.duration - at)
            guard seconds >= 1 else { continue }
            plan.narration.append(Narration(note: note, at: at, seconds: seconds))
            lastEnd = at + seconds
        }
        return plan
    }
}
