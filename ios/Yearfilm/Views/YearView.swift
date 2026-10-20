import SwiftData
import SwiftUI

struct YearView: View {
    @Query private var clips: [Clip]
    @Query private var notes: [VoiceNote]

    private static var thisYear: Int { Calendar.current.component(.year, from: .now) }
    /// The year on screen: this one, or an earlier one that clips were filmed in.
    @State private var year = YearView.thisYear
    @State private var showingRoughCut = false
    private var current: FilmWeek { FilmWeek(date: .now) }
    private var filmedWeeks: Set<Int> { Set(clips.filter { $0.year == year }.map(\.week)) }
    private var yearClips: [Clip] { clips.filter { $0.year == year } }
    /// Every year with footage, plus this one, latest first.
    private var years: [Int] { Set(clips.map(\.year)).union([Self.thisYear]).sorted(by: >) }
    /// Weeks so far: all 52 for a past year.
    private var weeksSoFar: Int { year == Self.thisYear ? current.week : FilmWeek.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if year == Self.thisYear {
                        PremiereCard(year: year)
                    } else {
                        EarlierYearCard(year: year)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(filmedWeeks.count) of \(weeksSoFar) weeks filmed")
                            .font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                            ForEach(1...FilmWeek.count, id: \.self) { w in
                                let week = FilmWeek(year: year, week: w)
                                NavigationLink(value: week) {
                                    WeekCell(week: week, filmed: filmedWeeks.contains(w), isCurrent: week == current, isFuture: week > current)
                                }
                                .disabled(week > current)
                            }
                        }
                    }
                    .padding(16)
                    .glassCard()

                    HStack(spacing: 12) {
                        Stat(value: "\(yearClips.count)", label: "clips")
                        Stat(value: TimeText.duration(yearClips.reduce(0) { $0 + $1.durationSeconds }), label: "of footage")
                        Stat(value: "\(notes.filter { $0.year == year }.count)", label: "voice notes")
                    }
                }
                .padding()
            }
            .memoryPoolBackground()
            .safeAreaInset(edge: .bottom) { ImportProgressCard() }
            .navigationTitle(String(year))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Rough cut", systemImage: "film.stack") { showingRoughCut = true }
                        .disabled(yearClips.isEmpty)
                }
                if years.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Picker("Year", selection: $year) {
                            ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .navigationDestination(for: FilmWeek.self) { WeekDetailView(week: $0) }
            .fullScreenCover(isPresented: $showingRoughCut) { RoughCutView(year: year) }
        }
    }
}

struct PremiereCard: View {
    let year: Int

    var body: some View {
        let days = Premiere.daysUntil()
        VStack(alignment: .leading, spacing: 8) {
            Text("PREMIERE")
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(Color.glow)
            Text(Premiere.date(year: year), format: .dateTime.month(.wide).day())
                .font(.system(.largeTitle, design: .serif))
            Text(days > 0 ? "\(days) days of filming left" : days == 0 ? "Tonight." : "Your \(String(year)) film is ready.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(cornerRadius: 18)
    }
}

/// In place of the premiere countdown when looking back at an earlier year.
struct EarlierYearCard: View {
    let year: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EARLIER FOOTAGE")
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(Color.glow)
            Text(String(year))
                .font(.system(.largeTitle, design: .serif))
            Text("Clips filmed in \(String(year)), kept with the rest of your memories.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard(cornerRadius: 18)
    }
}

struct WeekCell: View {
    let week: FilmWeek
    let filmed: Bool
    let isCurrent: Bool
    let isFuture: Bool

    var body: some View {
        Text("\(week.week)")
            .font(.caption.monospacedDigit())
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(filmed ? Color.ground : isFuture ? Color.secondary.opacity(0.5) : Color.primary)
            .background(filmed ? Color.glow : Color.white.opacity(isFuture ? 0.03 : 0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isCurrent { RoundedRectangle(cornerRadius: 8).stroke(Color.glow, lineWidth: 2) }
            }
            .softGlow(radius: 8, opacity: filmed ? 0.6 : isCurrent ? 0.35 : 0)
            .accessibilityLabel("Week \(week.week), \(filmed ? "filmed" : "no clips")\(isCurrent ? ", this week" : "")")
    }
}

struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.monospacedDigit().weight(.semibold))
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 14)
    }
}

struct WeekDetailView: View {
    let week: FilmWeek
    @Query private var clips: [Clip]
    @Query private var notes: [VoiceNote]
    @State private var playing: Clip?

    init(week: FilmWeek) {
        self.week = week
        let year = week.year, number = week.week
        _clips = Query(filter: #Predicate<Clip> { $0.year == year && $0.week == number }, sort: \Clip.capturedOn)
        _notes = Query(filter: #Predicate<VoiceNote> { $0.year == year && $0.week == number }, sort: \VoiceNote.recordedOn)
    }

    var body: some View {
        List {
            Section("Shot to try") { Text(ShotPrompt.forWeek(week)) }
            Section("Clips") {
                if clips.isEmpty { Text("Nothing filmed this week.").foregroundStyle(.secondary) }
                ForEach(clips) { clip in
                    Button { playing = clip } label: { ClipRow(clip: clip) }
                        .buttonStyle(.plain)
                }
            }
            Section("Voice notes") { VoiceNoteSection(notes: notes) }
        }
        .memoryPoolBackground()
        .navigationTitle("Week \(week.week)")
        .sheet(item: $playing) { ClipPlayer(url: $0.url) }
    }
}
