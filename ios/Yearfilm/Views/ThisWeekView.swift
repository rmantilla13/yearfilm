import PhotosUI
import SwiftData
import SwiftUI

struct ThisWeekView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Clip.capturedOn) private var allClips: [Clip]
    @Query(sort: \VoiceNote.recordedOn) private var allNotes: [VoiceNote]

    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var message: String?
    @State private var playing: Clip?

    private var week: FilmWeek { FilmWeek(date: .now) }
    private var clips: [Clip] { allClips.filter { $0.filmWeek == week } }
    private var notes: [VoiceNote] { allNotes.filter { $0.filmWeek == week } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PromptCard(week: week)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    if clips.isEmpty {
                        Text("No clips from this week yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(clips) { clip in
                        Button { playing = clip } label: { ClipRow(clip: clip) }
                            .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteClips)

                    // PhotosPicker runs out of process: the app sees only what is picked,
                    // so it needs no photo library permission at all.
                    PhotosPicker(selection: $picked, maxSelectionCount: 20, matching: .videos) {
                        Label("Add clips", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Clips")
                }

                Section {
                    VoiceNoteSection(notes: notes)
                } header: {
                    Text("Voice note")
                } footer: {
                    Text("Twenty seconds on what happened this week. In December, these become the narration.")
                }
            }
            .navigationTitle("Week \(week.week)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(week.season().title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                if importing {
                    ProgressView("Adding clips…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .onChange(of: picked) { _, items in
                Task { await importItems(items) }
            }
            .alert("Clips added", isPresented: .constant(message != nil), presenting: message) { _ in
                Button("OK") { message = nil }
            } message: { text in
                Text(text)
            }
            .sheet(item: $playing) { clip in
                ClipPlayer(url: clip.url)
            }
        }
    }

    @MainActor
    private func importItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        importing = true
        var added = 0, elsewhere = 0, failed = 0
        for item in items {
            do {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                    failed += 1
                    continue
                }
                let info = await MovieInfo.read(MediaStore.footageURL(movie.fileName))
                let clip = Clip(fileName: movie.fileName, capturedOn: info.capturedOn ?? .now, durationSeconds: info.duration)
                context.insert(clip)
                added += 1
                if clip.filmWeek != week { elsewhere += 1 }
            } catch {
                failed += 1
            }
        }
        try? context.save()
        importing = false
        picked = []

        // Say where clips went: a clip filmed in March belongs to March's week, not this one.
        var lines: [String] = []
        if elsewhere > 0 {
            lines.append("\(elsewhere) of \(added) were filmed in an earlier week and were added there. You’ll find them in Year.")
        }
        if failed > 0 {
            lines.append("\(failed) couldn’t be added. If they’re in iCloud, try again once they’ve downloaded.")
        }
        if !lines.isEmpty { message = lines.joined(separator: "\n\n") }
    }

    private func deleteClips(at offsets: IndexSet) {
        for index in offsets {
            let clip = clips[index]
            MediaStore.remove(clip.url)
            context.delete(clip)
        }
        try? context.save()
    }
}

struct PromptCard: View {
    let week: FilmWeek

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SHOT TO TRY")
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(Color.ember)
            Text(ShotPrompt.forWeek(week))
                .font(.system(.title3, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [Color.ember.opacity(0.22), Color.ember.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }
}

struct ClipRow: View {
    let clip: Clip

    var body: some View {
        HStack(spacing: 14) {
            ClipThumbnail(url: clip.url)
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.capturedOn, format: .dateTime.weekday(.wide).month().day())
                Text(TimeText.duration(clip.durationSeconds))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays the clip")
    }
}

struct ClipThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: 96, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) { image = await MovieInfo.thumbnail(url) }
        .accessibilityHidden(true)
    }
}
