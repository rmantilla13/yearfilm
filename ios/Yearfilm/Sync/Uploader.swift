import Foundation
import Observation
import SwiftData

/// Backs up clips and voice notes to Yearfilm, straight from this iPhone to private Blob
/// storage through presigned PUTs.
///
/// Uploads run in a background URLSession, so a 2 GB clip keeps going after the app is
/// closed. The order for each item is: ask the server for a presigned URL, upload the file,
/// then tell the server it arrived so it records the clip. Every step can be retried: the
/// URL can't overwrite, and recording is keyed by the clip's own id. An upload that lost
/// its URL (it expired before the system ran it) is simply asked for again next sync.
@MainActor
@Observable
final class Uploader: NSObject {
    static let shared = Uploader()
    static let sessionIdentifier = "com.yearfilm.app.uploads"
    static let enabledKey = "backupOn"
    /// Mirrors MAX_BYTES in lib/media.ts. One presigned PUT is proven to 500 MB.
    static let maxBytes: [String: Int64] = ["footage": 500 * 1024 * 1024, "voice_note": 50 * 1024 * 1024]

    /// Items waiting to be backed up.
    private(set) var pending = 0
    /// Clips over the size one upload can take; they wait for multipart uploads.
    private(set) var tooLarge = 0
    /// Clips from weeks this person's invite doesn't cover. They stay on the phone.
    private(set) var outsideWeeks = 0
    private(set) var lastError: String?

    @ObservationIgnored var container: ModelContainer?
    /// Handed over by the system when it relaunches the app for finished background uploads.
    @ObservationIgnored var backgroundEventsDone: (() -> Void)?
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false  // the person is waiting to see "backed up"
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Reattaches to uploads the system kept running while the app was closed.
    func reconnect() { _ = session }

    /// Takes something out of the backup: cancels its upload if one is running, and removes it
    /// from Yearfilm's servers — now if possible, otherwise on a later sync.
    func remove(kind: String, id: UUID, backedUp: Bool) {
        // Something never backed up, on a phone with no account, has nothing on the server.
        let mightBeUploaded = backedUp || Account.shared.isSignedIn || Self.arrived.contains(id)
        Self.arrived.remove(id)
        if mightBeUploaded {
            var queue = Self.removals
            queue[id.uuidString.lowercased()] = kind
            Self.removals = queue
        }
        session.getAllTasks { tasks in
            tasks.filter { UploadItem(encoded: $0.taskDescription)?.id == id }.forEach { $0.cancel() }
        }
        Task { await sync() }
    }

    /// Starts whatever isn't backed up yet, after sending any removals. Cheap to call often.
    func sync() async {
        guard let container else { return }
        if Account.shared.isSignedIn { await sendRemovals() }
        // Only ask the server for what it will take: anything else would be refused on every sync.
        let all = Self.pendingItems(container.mainContext)
        let family = Account.shared.family
        let inWeeks = all.filter { item in family.map { f in item.filmWeek.map(f.allows) ?? true } ?? true }
        let items = inWeeks.filter { $0.request.byteSize <= Self.maxBytes[$0.request.kind] ?? 0 }
        outsideWeeks = all.count - inWeeks.count
        tooLarge = inWeeks.count - items.count
        pending = items.count
        guard !syncing, isEnabled, family != nil, !items.isEmpty else { return }
        syncing = true
        defer { syncing = false }

        let running = Set(await session.allTasks.compactMap { UploadItem(encoded: $0.taskDescription)?.id })
        for item in items where !running.contains(item.id) {
            do {
                if Self.arrived.contains(item.id), try await record(item) { continue }
                try await start(item)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                if (error as? API.Failure)?.status == 401 { break }  // signed out: stop asking
            }
        }
    }

    // MARK: Steps

    private struct Removal: Encodable {
        let kind: String
        let id: String
    }

    private struct Removed: Decodable { let removed: Bool }

    private func sendRemovals() async {
        for (id, kind) in Self.removals {
            do {
                let _: Removed = try await API.request("POST", "/api/uploads/remove", json: Removal(kind: kind, id: id))
            } catch let failure as API.Failure where failure.status >= 400 && failure.status < 500 && failure.status != 401 {
                // Refused for good (not ours to remove, say): nothing more to do from here.
            } catch {
                continue  // offline or signed out: keep it for the next sync
            }
            var queue = Self.removals
            queue[id] = nil
            Self.removals = queue
        }
    }

    private struct Presigned: Decodable {
        let method: String
        let url: URL
        let headers: [String: String]
    }

    private struct Recorded: Decodable { let ok: Bool }

    private func start(_ item: UploadItem) async throws {
        let presigned: Presigned = try await API.request("POST", "/api/uploads", json: item.request)
        var request = URLRequest(url: presigned.url)
        request.httpMethod = presigned.method
        for (name, value) in presigned.headers { request.setValue(value, forHTTPHeaderField: name) }
        let task = session.uploadTask(with: request, fromFile: item.file)
        task.taskDescription = item.encoded
        task.countOfBytesClientExpectsToSend = item.request.byteSize
        task.resume()
    }

    /// Tells the server the file arrived. False if it hasn't, so the upload should run again.
    private func record(_ item: UploadItem) async throws -> Bool {
        do {
            let _: Recorded = try await API.request("POST", "/api/uploads/complete", json: item.request)
        } catch let failure as API.Failure where failure.status == 409 {
            Self.arrived.remove(item.id)
            return false
        }
        Self.arrived.remove(item.id)
        markUploaded(item)
        return true
    }

    private func finished(_ item: UploadItem, status: Int?, error: Error?) async {
        if let error {
            lastError = error.localizedDescription  // retried on the next sync
            return
        }
        guard let status else { return }
        // 2xx: it's there. 409/412: an earlier attempt already put it there and overwrite is
        // refused. Either way the server should now record it. Anything else (an expired
        // URL, say) is asked for again on the next sync.
        guard (200..<300).contains(status) || status == 409 || status == 412 else { return }
        Self.arrived.insert(item.id)
        _ = try? await record(item)
    }

    private func markUploaded(_ item: UploadItem) {
        guard let context = container?.mainContext else { return }
        let id = item.id
        switch item.request.kind {
        case "footage":
            if let clip = try? context.fetch(FetchDescriptor<Clip>(predicate: #Predicate { $0.id == id })).first {
                clip.uploadedAt = .now
            }
        default:
            if let note = try? context.fetch(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == id })).first {
                note.uploadedAt = .now
            }
        }
        try? context.save()
        pending = max(0, pending - 1)
    }

    // MARK: What's pending

    static func pendingItems(_ context: ModelContext) -> [UploadItem] {
        let clips = (try? context.fetch(FetchDescriptor<Clip>(predicate: #Predicate { $0.uploadedAt == nil }))) ?? []
        let notes = (try? context.fetch(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.uploadedAt == nil }))) ?? []
        return clips.compactMap { UploadItem(kind: "footage", id: $0.id, file: $0.url, day: $0.capturedOn, week: $0.filmWeek, duration: $0.durationSeconds) }
            + notes.compactMap { UploadItem(kind: "voice_note", id: $0.id, file: $0.url, day: $0.recordedOn, week: $0.filmWeek, duration: $0.durationSeconds) }
    }

    /// Removals waiting to reach the server, id → kind; survives the app being killed.
    private static var removals: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: "uploadsToRemove") as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "uploadsToRemove") }
    }

    /// Uploaded but not yet recorded by the server; survives the app being killed in between.
    private static var arrived: Set<UUID> {
        get { Set((UserDefaults.standard.stringArray(forKey: "uploadsArrived") ?? []).compactMap(UUID.init(uuidString:))) }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: "uploadsArrived") }
    }
}

extension Uploader: URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let item = UploadItem(encoded: task.taskDescription) else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        Task { @MainActor in await self.finished(item, status: status, error: error) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundEventsDone?()
            self.backgroundEventsDone = nil
        }
    }
}

/// One file to back up, and everything the server needs to place it.
struct UploadItem: Sendable {
    struct Request: Codable, Sendable {
        let kind: String
        let id: String
        let capturedOn: String
        let ext: String
        let byteSize: Int64
        let durationS: Double
    }

    let request: Request
    let file: URL
    /// The week it's filed under. Not kept across relaunches; only the backlog filter needs it.
    var filmWeek: FilmWeek?
    var id: UUID { UUID(uuidString: request.id)! }

    init?(kind: String, id: UUID, file: URL, day: Date, week: FilmWeek, duration: Double) {
        guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 else { return nil }
        request = Request(
            kind: kind,
            id: id.uuidString.lowercased(),
            capturedOn: Self.localDay(day),
            ext: file.pathExtension.lowercased(),
            byteSize: Int64(size),
            durationS: duration
        )
        self.file = file
        filmWeek = week
    }

    /// Kept in the task's description so a relaunched app knows what finished.
    var encoded: String {
        let data = try! JSONEncoder().encode(Encoded(request: request, path: file.path))
        return String(decoding: data, as: UTF8.self)
    }

    init?(encoded: String?) {
        guard let data = encoded?.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Encoded.self, from: data)
        else { return nil }
        request = decoded.request
        file = URL(fileURLWithPath: decoded.path)
    }

    private struct Encoded: Codable {
        let request: Request
        let path: String
    }

    /// The calendar day where it was filmed, never a UTC instant (docs/data-model.md).
    static func localDay(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
