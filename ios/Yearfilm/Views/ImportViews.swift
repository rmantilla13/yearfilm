import SwiftData
import SwiftUI

/// "Adding memories… 12 of 41", above the tab bar while a bulk import runs.
struct ImportProgressCard: View {
    private let importer = BulkImporter.shared

    var body: some View {
        if importer.isRunning {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Adding memories to the pool")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(importer.processed) of \(importer.total)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(importer.processed), total: Double(max(importer.total, 1)))
                    .tint(Color.glow)
            }
            .padding(16)
            .glassCard(cornerRadius: 20)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}

/// Each clip as it's added: its thumbnail floats up, glows, and dissolves into the pool,
/// labelled with the week it was filed under. Purely decorative; off with Reduce Motion.
struct FloatingMemories: View {
    private let importer = BulkImporter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where a memory sinks into the pool, as a fraction of the screen. The pool ripples there.
    static func landingPoint(lane: Double) -> UnitPoint {
        UnitPoint(x: 0.5 + lane * 0.3, y: 0.36)
    }

    var body: some View {
        if !reduceMotion, !importer.memories.isEmpty {
            TimelineView(.animation) { context in
                GeometryReader { geo in
                    ForEach(importer.memories) { memory in
                        let progress = context.date.timeIntervalSince(memory.born) / BulkImporter.floatDuration
                        if progress >= 0, progress <= 1 {
                            MemoryBubble(memory: memory, progress: progress, size: geo.size)
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct MemoryBubble: View {
    let memory: BulkImporter.Memory
    let progress: Double
    let size: CGSize

    var body: some View {
        let rise = 1 - pow(1 - progress, 2)  // quick off the ground, slowing as it reaches the pool
        let landing = FloatingMemories.landingPoint(lane: memory.lane)
        let x = size.width * landing.x + sin(progress * .pi * 3 + memory.lane * 5) * 14 * (1 - progress)
        let y = size.height * (0.8 - (0.8 - landing.y) * rise)
        let dissolve = smoothstep(0.55, 1, progress)

        VStack(spacing: 6) {
            Group {
                if let image = memory.image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.glow.opacity(0.25)
                }
            }
            .frame(width: 96, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.glow.opacity(0.7), lineWidth: 1))
            Text(memory.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.glow)
        }
        .softGlow(radius: 10 + 22 * dissolve, opacity: 0.45 + 0.45 * dissolve)
        .scaleEffect(1 - 0.6 * dissolve)
        .blur(radius: 12 * dissolve)
        .opacity(min(1, progress * 6) * (1 - dissolve))
        .position(x: x, y: y)
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// After a bulk import: how many clips went where, what was skipped, and a week for the undated ones.
struct ImportSummaryView: View {
    let summary: BulkImporter.Summary

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var undatedWeek = FilmWeek(date: .now)
    @State private var moved = false

    private var weeks: [(week: FilmWeek, count: Int)] {
        summary.weeks.map { ($0.key, $0.value) }.sorted { $0.week < $1.week }
    }
    private var thisYear: Int { Calendar.current.component(.year, from: .now) }
    private var otherYears: [Int] { Array(Set(summary.weeks.keys.map(\.year)).subtracting([thisYear])).sorted() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(headline)
                            .font(.system(.title2, design: .serif))
                        ForEach(notes, id: \.self) { Text($0).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 6)
                }

                if !summary.undated.isEmpty {
                    Section {
                        if moved {
                            Label("Moved to \(undatedWeek.label)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.glow)
                        } else {
                            Text("\(count(summary.undated.count, "clip")) didn’t say when \(summary.undated.count == 1 ? "it was" : "they were") filmed, so \(summary.undated.count == 1 ? "it’s" : "they’re") in this week for now.")
                            Picker("Filmed in", selection: $undatedWeek) {
                                ForEach(pickableWeeks, id: \.self) { Text($0.label).tag($0) }
                            }
                            Button("Move \(summary.undated.count == 1 ? "it" : "them") there") {
                                BulkImporter.shared.move(summary.undated, to: undatedWeek, in: context)
                                moved = true
                            }
                        }
                    } header: {
                        Text("No date")
                    }
                }

                if !weeks.isEmpty {
                    Section("Where they went") {
                        ForEach(weeks, id: \.week) { item in
                            LabeledContent(item.week.label, value: count(item.count, "clip"))
                        }
                    }
                }
            }
            .memoryPoolBackground(intensity: 0.5)
            .navigationTitle("Added to your year")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var headline: String {
        guard summary.added > 0 else { return "Nothing new to add" }
        let weekCount = summary.weeks.count + (summary.undated.isEmpty ? 0 : 1)
        return "\(count(summary.added, "clip")) across \(count(weekCount, "week"))"
    }

    private var notes: [String] {
        var lines: [String] = []
        if summary.duplicates > 0 {
            lines.append("\(count(summary.duplicates, "duplicate")) skipped: already in your year.")
        }
        if summary.failed > 0 {
            lines.append("\(count(summary.failed, "clip")) couldn’t be added. If they’re in iCloud, try again once they’ve downloaded.")
        }
        if !otherYears.isEmpty {
            let years = otherYears.map(String.init).joined(separator: ", ")
            lines.append("Some were filmed in \(years). Find them in Year, under \(otherYears.count == 1 ? "that year" : "those years").")
        }
        return lines
    }

    /// Every week of this year so far, latest first.
    private var pickableWeeks: [FilmWeek] {
        let current = FilmWeek(date: .now)
        return (1...current.week).reversed().map { FilmWeek(year: current.year, week: $0) }
    }

    private func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}
