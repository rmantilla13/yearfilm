import Foundation
import SwiftData

/// Taking things out of the film. One place for it, so the copy on this iPhone and the one in
/// the iCloud backup go together.
@MainActor
enum Library {
    static func remove(_ clip: Clip, from context: ModelContext) {
        let id = clip.id, year = clip.year, backedUp = clip.backedUpAt != nil
        MediaStore.remove(clip.url)
        context.delete(clip)
        try? context.save()
        CloudBackup.shared.removed(.clip, id: id, year: year, wasBackedUp: backedUp)
    }

    static func remove(_ note: VoiceNote, from context: ModelContext) {
        let id = note.id, year = note.year, backedUp = note.backedUpAt != nil
        MediaStore.remove(note.url)
        context.delete(note)
        try? context.save()
        CloudBackup.shared.removed(.note, id: id, year: year, wasBackedUp: backedUp)
    }
}
