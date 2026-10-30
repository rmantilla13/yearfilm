import CryptoKit
import PhotosUI
import SwiftData
import SwiftUI

/// Bulk import: as many clips as someone picks, each filed under the week it was filmed
/// (from the file's own date), duplicates skipped. One shared importer for the app, so an
/// import keeps going when you switch tabs, and a second pick joins the queue.
@MainActor
@Observable
final class BulkImporter {
    static let shared = BulkImporter()

    /// A clip's thumbnail on its way up into the pool (see FloatingMemories).
    struct Memory: Identifiable {
        let id = UUID()
        let image: UIImage?
        let label: String
        let born: Date
        /// Where across the screen it rises, -1...1.
        let lane: Double
    }

    struct Summary: Identifiable {
        let id = UUID()
        var added = 0
        var duplicates = 0
        var failed = 0
        var weeks: [FilmWeek: Int] = [:]
        /// Clips whose files carry no date. Filed under this week until someone picks theirs.
        var undated: [UUID] = []
    }

    static let floatDuration: TimeInterval = 2.6
    /// Clips copied at once. More doesn't help much: each copy is disk-bound.
    private static let concurrent = 3
    private static let maxFloating = 8

    private(set) var total = 0
    private(set) var processed = 0
    private(set) var memories: [Memory] = []
    /// Where and when the latest memory sinks into the pool, for the pool to ripple there.
    private(set) var landing: Stir?
    /// Set when an import finishes, for the summary sheet.
    var summary: Summary?
    var isRunning: Bool { task != nil }

    private var queue: [PhotosPickerItem] = []
    private var running = Summary()
    private var task: Task<Void, Never>?

    func add(_ items: [PhotosPickerItem], into context: ModelContext) {
        guard !items.isEmpty else { return }
        queue += items
        total += items.count
        if task == nil { task = Task { await run(context) } }
    }

    /// Files clips that had no date under the week someone says they belong to.
    func move(_ ids: [UUID], to week: FilmWeek, in context: ModelContext) {
        let wanted = Set(ids)
        let midday = week.start().addingTimeInterval(12 * 3600)
        for clip in (try? context.fetch(FetchDescriptor<Clip>())) ?? [] where wanted.contains(clip.id) {
            clip.capturedOn = midday
            clip.year = week.year
            clip.week = week.week
        }
        try? context.save()
    }

    private func run(_ context: ModelContext) async {
        var known = Self.fingerprints(in: context)
        while !queue.isEmpty {
            let batch = Array(queue.prefix(Self.concurrent))
            queue.removeFirst(batch.count)
            let loaded = await withTaskGroup(of: (Int, Loaded?).self) { group in
                for (i, item) in batch.enumerated() {
                    group.addTask { (i, await Self.load(item)) }
                }
                var results = [Loaded?](repeating: nil, count: batch.count)
                for await (i, result) in group { results[i] = result }
                return results
            }
            for result in loaded {
                file(result, into: context, known: &known)
                processed += 1
            }
            try? context.save()
        }
        summary = running
        running = Summary()
        total = 0
        processed = 0
        task = nil
    }

    private func file(_ loaded: Loaded?, into context: ModelContext, known: inout Set<Fingerprint>) {
        guard let loaded else {
            running.failed += 1
            return
        }
        let url = MediaStore.footageURL(loaded.fileName)
        guard known.insert(loaded.fingerprint).inserted else {
            MediaStore.remove(url)
            running.duplicates += 1
            return
        }
        let clip = Clip(fileName: loaded.fileName, capturedOn: loaded.info.capturedOn ?? .now, durationSeconds: loaded.info.duration)
        context.insert(clip)
        running.added += 1
        if loaded.info.capturedOn == nil {
            running.undated.append(clip.id)
        } else {
            running.weeks[clip.filmWeek, default: 0] += 1
        }
        float(loaded.thumbnail, label: loaded.info.capturedOn == nil ? "No date" : clip.filmWeek.label)
    }

    private func float(_ image: UIImage?, label: String) {
        prune()
        guard memories.count < Self.maxFloating else { return }
        // Staggered, so a batch rises one after another instead of in a clump.
        let born = max(Date.now, (memories.last?.born ?? .distantPast).addingTimeInterval(0.2))
        let lane = Double.random(in: -0.7...0.7)
        memories.append(Memory(image: image, label: label, born: born, lane: lane))
        landing = Stir(point: FloatingMemories.landingPoint(lane: lane), at: born.addingTimeInterval(Self.floatDuration * 0.75))
        let gone = born.timeIntervalSinceNow + Self.floatDuration + 0.5
        Task {
            try? await Task.sleep(for: .seconds(gone))
            prune()
        }
    }

    private func prune() {
        memories.removeAll { Date.now.timeIntervalSince($0.born) > Self.floatDuration }
    }

    // MARK: Loading, off the main actor

    private struct Loaded {
        let fileName: String
        let info: MovieInfo
        let fingerprint: Fingerprint
        let thumbnail: UIImage?
    }

    /// The same file picked twice. Size and length alone aren't enough (short clips of a
    /// plain scene can match), so also the filming date and a hash of the file's start.
    private struct Fingerprint: Hashable {
        let bytes: Int64
        let centiseconds: Int
        let filmed: Int?
        let head: Data

        nonisolated init(url: URL, seconds: Double, filmed: Date?) {
            bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            centiseconds = Int((seconds * 100).rounded())
            self.filmed = filmed.map { Int($0.timeIntervalSince1970.rounded()) }
            let handle = try? FileHandle(forReadingFrom: url)
            let start = (try? handle?.read(upToCount: 256 * 1024)) ?? nil
            try? handle?.close()
            head = Data(SHA256.hash(data: start ?? Data()))
        }
    }

    nonisolated private static func load(_ item: PhotosPickerItem) async -> Loaded? {
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else { return nil }
        let url = MediaStore.footageURL(movie.fileName)
        async let thumbnail = MovieInfo.thumbnail(url, maxSide: 240)
        let info = await MovieInfo.read(url)
        let fingerprint = Fingerprint(url: url, seconds: info.duration, filmed: info.capturedOn)
        return Loaded(fileName: movie.fileName, info: info, fingerprint: fingerprint, thumbnail: await thumbnail)
    }

    private static func fingerprints(in context: ModelContext) -> Set<Fingerprint> {
        let clips = (try? context.fetch(FetchDescriptor<Clip>())) ?? []
        return Set(clips.map { Fingerprint(url: $0.url, seconds: $0.durationSeconds, filmed: $0.capturedOn) })
    }
}

extension FilmWeek {
    /// "Week 11 · Mar 12", with the year added when it isn't this one.
    var label: String {
        let day = start().formatted(.dateTime.month(.abbreviated).day())
        let thisYear = Calendar.current.component(.year, from: .now)
        return year == thisYear ? "Week \(week) · \(day)" : "Week \(week), \(String(year)) · \(day)"
    }
}
