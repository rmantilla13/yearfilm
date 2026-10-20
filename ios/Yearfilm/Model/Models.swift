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
    // iCloud (docs/storage-plan.md). All defaulted, so existing libraries open unchanged.
    /// When this clip's record last reached the owner's iCloud backup.
    var backedUpAt: Date? = nil
    /// The record's CloudKit system fields, kept so later saves don't conflict.
    var cloudSystemFields: Data? = nil
    /// When it was sent to a family film this person contributes to.
    var sharedAt: Date? = nil
    /// Who added it, when it came from a relative's phone through a family share.
    var addedBy: String? = nil

    init(id: UUID = UUID(), fileName: String, capturedOn: Date, durationSeconds: Double, calendar: Calendar = .current) {
        let filmWeek = FilmWeek(date: capturedOn, calendar: calendar)
        self.id = id
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
    var backedUpAt: Date? = nil
    var cloudSystemFields: Data? = nil
    var sharedAt: Date? = nil
    var addedBy: String? = nil

    init(id: UUID = UUID(), fileName: String, recordedOn: Date = .now, durationSeconds: Double, calendar: Calendar = .current) {
        let filmWeek = FilmWeek(date: recordedOn, calendar: calendar)
        self.id = id
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
