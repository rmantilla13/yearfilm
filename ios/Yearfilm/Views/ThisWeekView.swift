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
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ScreenHeader(eyebrow: "\(week.season().title) · \(week.dateRange())", title: "Week \(week.week)")
                        .padding(.horizontal, 20)

                    PromptCard(week: week)
                        .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Clips", detail: clips.isEmpty ? nil : "\(clips.count) \(clips.count == 1 ? "clip" : "clips")")
                            .padding(.horizontal, 20)
                        Filmstrip(clips: clips, picked: $picked) { playing = $0 }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "Voice note")
                        VoiceNoteSection(notes: notes)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .memoryPoolBackground(stir: importer.landing)
            .overlay { FloatingMemories() }
            .safeAreaInset(edge: .bottom) { ImportProgressCard() }
            .animation(.smooth, value: importer.isRunning)
            .toolbar(.hidden, for: .navigationBar)
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
        .padding(22)
        .glassCard(cornerRadius: 22, tint: Color.glow.opacity(0.1))
    }
}
