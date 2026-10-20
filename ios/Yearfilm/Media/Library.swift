import Foundation
import SwiftData

/// Taking things out of the film. One place for it, so the copy on this iPhone, an upload
/// still in flight and the backup on Yearfilm's servers all go together.
@MainActor
enum Library {
    static func remove(_ clip: Clip, from context: ModelContext) {
        let id = clip.id, backedUp = clip.uploadedAt != nil
        MediaStore.remove(clip.url)
        context.delete(clip)
        try? context.save()
        Uploader.shared.remove(kind: "footage", id: id, backedUp: backedUp)
    }

    static func remove(_ note: VoiceNote, from context: ModelContext) {
        let id = note.id, backedUp = note.uploadedAt != nil
        MediaStore.remove(note.url)
        context.delete(note)
        try? context.save()
        Uploader.shared.remove(kind: "voice_note", id: id, backedUp: backedUp)
    }
}
