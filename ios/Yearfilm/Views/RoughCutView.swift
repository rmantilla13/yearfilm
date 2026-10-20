import AVKit
import Combine
import SwiftData
import SwiftUI

/// Year → Rough cut: the year so far, cut on the phone in a few seconds. Not the film — a
/// glimpse of it, so filming feels like it's going somewhere.
struct RoughCutView: View {
    let year: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("familyName") private var familyName = ""
    @State private var plan: RoughCutPlan?
    @State private var player: AVPlayer?
    @State private var now = 0.0
    @State private var failure: String?
    @State private var observer: Any?

    var body: some View {
        NavigationStack {
            ZStack {
                if let player, let plan {
                    VideoPlayer(player: player) {
                        if let chapter = plan.chapters.first(where: { now >= $0.start && now < $0.start + $0.seconds }) {
                            ChapterCard(season: chapter.season, family: familyName, year: year, first: chapter == plan.chapters.first)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.4), value: plan.chapters.first { now >= $0.start && now < $0.start + $0.seconds })
                    .ignoresSafeArea(edges: .bottom)
                } else if let plan, plan.isEmpty {
                    note("Nothing to cut yet", "Add a few clips and come back. Every week you film shows up here.")
                } else if let failure {
                    note("Couldn’t make the cut", failure)
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Cutting your year…").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { MemoryPool(intensity: player == nil ? 0.8 : 0.2) }
            .navigationTitle("Rough cut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                if let plan, !plan.isEmpty {
                    ToolbarItem(placement: .principal) {
                        Text(TimeText.duration(plan.duration)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task { await build() }
        .onDisappear {
            player?.pause()
            if let observer { player?.removeTimeObserver(observer) }
        }
    }

    private func build() async {
        let clips = (try? context.fetch(FetchDescriptor<Clip>(predicate: #Predicate { $0.year == year }))) ?? []
        let notes = (try? context.fetch(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.year == year }))) ?? []
        let plan = RoughCutPlan.make(
            clips: clips.map { .init(id: $0.id, url: $0.url, capturedOn: $0.capturedOn, duration: $0.durationSeconds) },
            notes: notes.map { .init(id: $0.id, url: $0.url, week: $0.filmWeek, duration: $0.durationSeconds) }
        )
        self.plan = plan
        guard !plan.isEmpty else { return }
        do {
            let item = AVPlayerItem(url: try await RoughCut.export(plan))
            let player = AVPlayer(playerItem: item)
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { time in
                MainActor.assumeIsolated { now = time.seconds }
            }
            self.player = player
            player.play()
            // Say so if AVFoundation can't play the cut, rather than sitting on a black frame. The
            // player can fail while its item still says it's ready, so watch both.
            let failed = item.publisher(for: \.status).map { $0 == .failed }
                .merge(with: player.publisher(for: \.status).map { $0 == .failed })
            for await didFail in failed.values where didFail {
                self.player = nil
                failure = (player.error ?? item.error)?.localizedDescription ?? "This cut couldn’t be played."
                break
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    private func note(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(.title, design: .serif))
            Text(body).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 28)
        .padding(24)
    }
}

/// The title over a card's black gap. The first one is the film's title card.
private struct ChapterCard: View {
    let season: Season
    let family: String
    let year: Int
    let first: Bool

    var body: some View {
        VStack(spacing: 10) {
            if first {
                Text(family.isEmpty ? "Our year" : family)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.secondary)
                Text(String(year))
                    .font(.caption.weight(.semibold)).tracking(3)
                    .foregroundStyle(Color.glow)
            }
            Text(season.title)
                .font(.system(size: 44, weight: .regular, design: .serif))
                .softGlow(radius: 18, opacity: 0.35)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
