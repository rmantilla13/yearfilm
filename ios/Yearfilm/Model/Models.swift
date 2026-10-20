import Foundation
import SwiftData

/// One video the family added. The bytes live in MediaStore; this row is what the app knows about them.
@Model
final class Clip {
    @Attribute(.unique) var id: UUID
    var fileName: String
    /// When it was filmed (from the file's own metadata), not when it was added.
    var capturedOn: Date
    var addedAt: Date
    var durationSeconds: Double
    var year: Int
    var week: Int

    init(fileName: String, capturedOn: Date, durationSeconds: Double, calendar: Calendar = .current) {
        let filmWeek = FilmWeek(date: capturedOn, calendar: calendar)
        self.id = UUID()
        self.fileName = fileName
        self.capturedOn = capturedOn
        self.addedAt = .now
        self.durationSeconds = durationSeconds
        self.year = filmWeek.year
        self.week = filmWeek.week
    }

    var filmWeek: FilmWeek { FilmWeek(year: year, week: week) }
    var url: URL { MediaStore.footageURL(fileName) }
}

/// The weekly "what happened this week?" recording. Becomes the narration.
@Model
final class VoiceNote {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var recordedOn: Date
    var durationSeconds: Double
    var year: Int
    var week: Int

    init(fileName: String, recordedOn: Date = .now, durationSeconds: Double, calendar: Calendar = .current) {
        let filmWeek = FilmWeek(date: recordedOn, calendar: calendar)
        self.id = UUID()
        self.fileName = fileName
        self.recordedOn = recordedOn
        self.durationSeconds = durationSeconds
        self.year = filmWeek.year
        self.week = filmWeek.week
    }

    var filmWeek: FilmWeek { FilmWeek(year: year, week: week) }
    var url: URL { MediaStore.noteURL(fileName) }
}

enum TimeText {
    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
