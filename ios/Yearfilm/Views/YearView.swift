import PhotosUI
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
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .bottom) {
                        ScreenHeader(eyebrow: year == Self.thisYear ? "Your film" : "Earlier footage", title: String(year))
                        if years.count > 1 {
                            Menu {
                                Picker("Year", selection: $year) {
                                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                                }
                            } label: {
                                Label("Year", systemImage: "chevron.up.chevron.down")
                                    .labelStyle(.iconOnly)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(width: 40, height: 40)
                                    .glassCapsule()
                            }
                            .accessibilityLabel("Choose a year")
                        }
                    }

                    if year == Self.thisYear {
                        PremiereCard(year: year)
                    } else {
                        EarlierYearCard(year: year)
                    }

                    RoughCutCard(clips: yearClips) { showingRoughCut = true }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(title: "52 weeks", detail: "\(filmedWeeks.count) of \(weeksSoFar) filmed")
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
                    .padding(18)
                    .glassCard(cornerRadius: 22)

                    HStack(spacing: 12) {
                        Stat(value: "\(yearClips.count)", label: "clips")
                        Stat(value: TimeText.duration(yearClips.reduce(0) { $0 + $1.durationSeconds }), label: "of footage")
                        Stat(value: "\(notes.filter { $0.year == year }.count)", label: "voice notes")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .memoryPoolBackground()
            .safeAreaInset(edge: .bottom) { ImportProgressCard() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: FilmWeek.self) { WeekDetailView(week: $0) }
            .fullScreenCover(isPresented: $showingRoughCut) { RoughCutView(year: year) }
        }
    }
}

/// The payoff, up front: a few frames of the year so far and a way to watch them cut together.
struct RoughCutCard: View {
    let clips: [Clip]
    let watch: () -> Void

    /// Up to five clips spread across the year, for the fanned-out frames.
    private var sample: [Clip] {
        let sorted = clips.sorted { $0.capturedOn < $1.capturedOn }
        guard sorted.count > 5 else { return sorted }
        return (0..<5).map { sorted[$0 * sorted.count / 5] }
    }

    var body: some View {
        Button(action: watch) {
            HStack(spacing: 14) {
                ZStack {
                    if sample.isEmpty {
                        RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)).frame(width: 72, height: 46)
                    }
                    ForEach(Array(sample.enumerated()), id: \.element.id) { i, clip in
                        FrameThumb(url: clip.url)
                            .rotationEffect(.degrees(Double(i - sample.count / 2) * 7))
                            .offset(x: CGFloat(i - sample.count / 2) * 5)
                    }
                }
                .frame(width: 84, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ROUGH CUT")
                        .font(.caption.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(Color.glow)
                    Text(clips.isEmpty ? "Your year, so far" : "Watch your year so far")
                        .font(.system(.title3, design: .serif))
                    Text(clips.isEmpty ? "Film a few weeks and it appears here." : "\(clips.count) \(clips.count == 1 ? "clip" : "clips") so far")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !clips.isEmpty {
                    Image(systemName: "play.fill")
                        .font(.headline)
                        .foregroundStyle(Color.ground)
                        .frame(width: 40, height: 40)
                        .background(Color.glow, in: Circle())
                        .softGlow(radius: 10, opacity: 0.5)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 22, tint: Color.glow.opacity(0.08))
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .disabled(clips.isEmpty)
        .accessibilityHint(clips.isEmpty ? "" : "Cuts and plays the year so far")
    }
}

private struct FrameThumb: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .frame(width: 72, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.glow.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
        .task(id: url) { image = await MovieInfo.thumbnail(url, maxSide: 200) }
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
                .font(.system(size: 38, weight: .regular, design: .serif))
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
                .font(.system(size: 38, weight: .regular, design: .serif))
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
    @State private var picked: [PhotosPickerItem] = []
    @Environment(\.modelContext) private var context

    init(week: FilmWeek) {
        self.week = week
        let year = week.year, number = week.week
        _clips = Query(filter: #Predicate<Clip> { $0.year == year && $0.week == number }, sort: \Clip.capturedOn)
        _notes = Query(filter: #Predicate<VoiceNote> { $0.year == year && $0.week == number }, sort: \VoiceNote.recordedOn)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ScreenHeader(eyebrow: "\(week.season().title) · \(week.dateRange())", title: "Week \(week.week)")
                    .padding(.horizontal, 20)
                PromptCard(week: week)
                    .padding(.horizontal, 20)
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Clips", detail: clips.isEmpty ? "Nothing filmed" : "\(clips.count) \(clips.count == 1 ? "clip" : "clips")")
                        .padding(.horizontal, 20)
                    Filmstrip(clips: clips, picked: $picked) { playing = $0 }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: notes.count > 1 ? "Voice notes" : "Voice note")
                    // Notes are filed under the week they're recorded in, so only this week records.
                    VoiceNoteSection(notes: notes, canRecord: week == FilmWeek(date: .now))
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .memoryPoolBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            BulkImporter.shared.add(items, into: context)
            picked = []
        }
        .sheet(item: $playing) { ClipPlayer(url: $0.url) }
    }
}
