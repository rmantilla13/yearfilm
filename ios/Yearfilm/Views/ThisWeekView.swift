import PhotosUI
import SwiftData
import SwiftUI

struct ThisWeekView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Clip.capturedOn) private var allClips: [Clip]
    @Query(sort: \VoiceNote.recordedOn) private var allNotes: [VoiceNote]

    @State private var picked: [PhotosPickerItem] = []
    @State private var playing: Clip?
    private let importer = BulkImporter.shared

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
                        .contextMenu {
                            Button("Remove from your film", systemImage: "trash", role: .destructive) {
                                Library.remove(clip, from: context)
                            }
                        }
                    }
                    .onDelete(perform: deleteClips)

                    // PhotosPicker runs out of process: the app sees only what is picked,
                    // so it needs no photo library permission at all. No limit: pick a whole
                    // year at once and each clip is filed under the week it was filmed.
                    // `.current` hands over the original file, so its filming date survives.
                    PhotosPicker(selection: $picked, maxSelectionCount: nil, matching: .videos, preferredItemEncoding: .current) {
                        Label("Add clips", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Clips")
                } footer: {
                    Text("Add as many as you like, from any time. Each clip goes to the week it was filmed.")
                }

                Section {
                    VoiceNoteSection(notes: notes)
                } header: {
                    Text("Voice note")
                } footer: {
                    Text("Twenty seconds on what happened this week. In December, these become the narration.")
                }
            }
            .memoryPoolBackground(stir: importer.landing)
            .overlay { FloatingMemories() }
            .safeAreaInset(edge: .bottom) { ImportProgressCard() }
            .animation(.smooth, value: importer.isRunning)
            .navigationTitle("Week \(week.week)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(week.season().title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                importer.add(items, into: context)
                picked = []
            }
            .sheet(item: Binding(get: { importer.summary }, set: { BulkImporter.shared.summary = $0 })) { summary in
                ImportSummaryView(summary: summary)
            }
            .sheet(item: $playing) { clip in
                ClipPlayer(url: clip.url)
            }
        }
    }

    private func deleteClips(at offsets: IndexSet) {
        offsets.map { clips[$0] }.forEach { Library.remove($0, from: context) }
    }
}

struct PromptCard: View {
    let week: FilmWeek

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SHOT TO TRY")
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(Color.glow)
            Text(ShotPrompt.forWeek(week))
                .font(.system(.title3, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(cornerRadius: 18, tint: Color.glow.opacity(0.1))
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
