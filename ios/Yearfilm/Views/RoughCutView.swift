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
    @State private var memories: [UIImage] = []

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
                    MixingMemories(images: memories)
                        .overlay(alignment: .bottom) {
                            Text("Cutting your year…")
                                .font(.system(.title3, design: .serif))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 80)
                        }
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { MemoryPool(intensity: player == nil ? 0.9 : 0.2, center: UnitPoint(x: 0.5, y: 0.42)) }
            .animation(.easeInOut(duration: 0.6), value: player == nil)
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
        memories = await Self.thumbnails(for: plan)
        do {
            // Let the memories swirl in for a moment even when the cut is quick to make.
            async let cut = RoughCut.export(plan)
            try? await Task.sleep(for: .seconds(2.5))
            let item = AVPlayerItem(url: try await cut)
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

    /// A frame from up to 16 clips spread across the year, for the clips swirling into the pool.
    private static func thumbnails(for plan: RoughCutPlan) async -> [UIImage] {
        let shots = plan.pieces.compactMap { piece -> URL? in
            if case .shot(let source, _, _) = piece { source.url } else { nil }
        }
        let picked = shots.count <= 16 ? shots : (0..<16).map { shots[$0 * shots.count / 16] }
        return await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (i, url) in picked.enumerated() {
                group.addTask { (i, await MovieInfo.thumbnail(url, maxSide: 240)) }
            }
            var found: [(Int, UIImage)] = []
            for await (i, image) in group { if let image { found.append((i, image)) } }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
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

/// The cut being made: the year's clips spiral in toward the pool's center, shrinking and
/// glowing as they near it, and dissolve into the light there. Holds still with Reduce Motion.
private struct MixingMemories: View {
    let images: [UIImage]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds for one memory to fall from the rim into the center.
    private let fall = 3.6

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.42)
                let rim = min(geo.size.width, geo.size.height) * 0.46
                ZStack {
                    ForEach(images.indices, id: \.self) { i in
                        memory(images[i], index: i, t: t, center: center, rim: rim)
                    }
                    core(t: t).position(center)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Mixing your clips into the rough cut")
    }

    private func memory(_ image: UIImage, index i: Int, t: Double, center: CGPoint, rim: CGFloat) -> some View {
        // Each memory is somewhere along its fall, staggered so they arrive one after another.
        let phase = (t / fall + Double(i) / Double(max(images.count, 1))).truncatingRemainder(dividingBy: 1)
        let pull = phase * phase  // drifts at the rim, then is drawn in faster and faster
        let angle = Double(i) * 2.39996 + phase * 2.4 * .pi + t * 0.12
        let r = Double(rim) * (1 - pull)
        let dissolve = smoothstep(0.7, 1, phase)
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 96, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.glow.opacity(0.6), lineWidth: 1))
            .rotationEffect(.radians((angle + .pi / 2) * 0.12))
            .scaleEffect(1 - 0.8 * pull)
            .softGlow(radius: 8 + 20 * pull, opacity: 0.25 + 0.6 * pull)
            .blur(radius: 10 * dissolve)
            .opacity(min(1, phase * 6) * (1 - dissolve))
            .position(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r * 0.82)
    }

    /// The light everything falls into, breathing a little.
    private func core(t: Double) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.glow.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 70))
                .frame(width: 140, height: 140)
            Circle()
                .fill(.white)
                .frame(width: 14, height: 14)
                .softGlow(radius: 18, opacity: 1)
        }
        .scaleEffect(1 + 0.12 * sin(t * 2.6))
        .allowsHitTesting(false)
    }

    private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
