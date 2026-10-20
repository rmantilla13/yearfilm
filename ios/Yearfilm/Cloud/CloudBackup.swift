import CloudKit
import Foundation
import Observation
import SwiftData
import UIKit

/// Backs the library up to the person's own iCloud (private database, one zone per film year),
/// and restores it on a new phone with the same Apple ID. Relatives' clips added through a
/// family share arrive here too, because a shared zone lives in its owner's private database.
///
/// Nothing here runs until backup is turned on: the container and engine are created then and
/// not before, so the app works the same without iCloud, signed out, or unsigned in development.
@MainActor
@Observable
final class CloudBackup {
    static let shared = CloudBackup()
    static let enabledKey = "iCloudBackupOn"

    enum Status: Equatable {
        case off
        case starting
        case upToDate
        case sending(Int)
        case noAccount
        case full
        case failed(String)
    }

    private(set) var status: Status = .off
    var isOn: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    @ObservationIgnored var container: ModelContainer?
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var database: CKDatabase?

    // MARK: Turning it on and off

    /// Starts syncing if backup was left on. Call once the library is open.
    func resume() {
        guard isOn, engine == nil else { return }
        start()
    }

    func turnOn() {
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        start()
        enqueueEverything()
        Task { await sync() }
    }

    /// Stops backing up. What's already in iCloud stays there; Delete iCloud backup removes it.
    func turnOff() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        engine = nil
        status = .off
    }

    /// Deletes every year's zone from iCloud, then turns backup off. A year shared with family
    /// ends for everyone in it. The library on this phone is untouched.
    func deleteBackup() async {
        if engine == nil { start() }
        guard let engine else { return }
        let years = Set(allItems().map(\.year)).union(knownZoneYears)
        engine.state.add(pendingDatabaseChanges: years.map { .deleteZone(CloudRecords.zoneID(year: $0)) })
        do {
            try await engine.sendChanges()
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        forgetCloudState()
        turnOff()
    }

    /// Something changed in the library: send it.
    func sync() async {
        guard let engine else { return }
        enqueueUnsent()
        do {
            try await engine.sendChanges()
            try await engine.fetchChanges()
        } catch {
            note(error)
        }
    }

    /// A clip or note was removed on this phone: remove its record too, now or once backup runs.
    func removed(_ kind: CloudRecords.Kind, id: UUID, year: Int, wasBackedUp: Bool) {
        guard wasBackedUp else { return }
        let recordID = CloudRecords.recordID(kind, id, year: year)
        if let engine {
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            Task { try? await engine.sendChanges() }
        } else {
            var waiting = Self.waitingDeletes
            waiting[recordID.recordName] = year
            Self.waitingDeletes = waiting
        }
    }

    // MARK: Engine

    private func start() {
        guard CloudRecords.isAvailable else {
            status = .failed("iCloud isn’t available in this build.")
            return
        }
        status = .starting
        // CloudKit pushes changes so backups and relatives' clips arrive without opening the app.
        UIApplication.shared.registerForRemoteNotifications()
        let container = CKContainer(identifier: CloudRecords.containerID)
        let database = container.privateCloudDatabase
        self.database = database
        let configuration = CKSyncEngine.Configuration(database: database, stateSerialization: Self.savedState, delegate: self)
        let engine = CKSyncEngine(configuration)
        self.engine = engine

        // Removals made while backup was off.
        let waiting = Self.waitingDeletes.map { name, year in
            CKSyncEngine.PendingRecordZoneChange.deleteRecord(CKRecord.ID(recordName: name, zoneID: CloudRecords.zoneID(year: year)))
        }
        if !waiting.isEmpty { engine.state.add(pendingRecordZoneChanges: waiting) }
        Self.waitingDeletes = [:]

        Task {
            switch try? await container.accountStatus() {
            case .available: status = .upToDate
            case .none: break
            default: status = .noAccount
            }
        }
    }

    /// Queues every year's zone and every item not yet in iCloud.
    private func enqueueEverything() {
        guard let engine else { return }
        let years = Set(allItems().map(\.year))
        engine.state.add(pendingDatabaseChanges: years.map { .saveZone(CKRecordZone(zoneID: CloudRecords.zoneID(year: $0))) })
        enqueueUnsent()
    }

    private func enqueueUnsent() {
        guard let engine else { return }
        let pending = Set(engine.state.pendingRecordZoneChanges.compactMap { change -> CKRecord.ID? in
            if case .saveRecord(let id) = change { id } else { nil }
        })
        let unsent = allItems().filter { $0.backedUpAt == nil }
            .map { CloudRecords.recordID($0.kind, $0.id, year: $0.year) }
            .filter { !pending.contains($0) }
        if !unsent.isEmpty { engine.state.add(pendingRecordZoneChanges: unsent.map { .saveRecord($0) }) }
        updateSending()
    }

    private func updateSending() {
        guard case .failed = status else {
            let count = engine?.state.pendingRecordZoneChanges.count ?? 0
            if status != .noAccount && status != .full { status = count == 0 ? .upToDate : .sending(count) }
            return
        }
    }

    private func note(_ error: Error) {
        switch (error as? CKError)?.code {
        case .quotaExceeded: status = .full
        case .notAuthenticated: status = .noAccount
        case .networkUnavailable, .networkFailure: break  // the engine retries by itself
        default: status = .failed(error.localizedDescription)
        }
    }

    // MARK: Library access

    /// A clip or note as backup sees it.
    private struct Local {
        let kind: CloudRecords.Kind
        let id: UUID
        let year: Int
        let backedUpAt: Date?
    }

    private func allItems() -> [Local] {
        guard let context = container?.mainContext else { return [] }
        let clips = (try? context.fetch(FetchDescriptor<Clip>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<VoiceNote>())) ?? []
        return clips.map { Local(kind: .clip, id: $0.id, year: $0.year, backedUpAt: $0.backedUpAt) }
            + notes.map { Local(kind: .note, id: $0.id, year: $0.year, backedUpAt: $0.backedUpAt) }
    }

    private func clip(_ id: UUID) -> Clip? {
        try? container?.mainContext.fetch(FetchDescriptor<Clip>(predicate: #Predicate { $0.id == id })).first
    }

    private func voiceNote(_ id: UUID) -> VoiceNote? {
        try? container?.mainContext.fetch(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.id == id })).first
    }

    /// The record to send for a pending save, built from the library.
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let (kind, id) = CloudRecords.parse(recordID) else { return nil }
        let item: CloudRecords.Item
        let file: URL
        let saved: Data?
        switch kind {
        case .clip:
            guard let c = clip(id) else { return nil }
            item = .init(kind: .clip, id: c.id, date: c.capturedOn, duration: c.durationSeconds, year: c.year, week: c.week, ext: c.url.pathExtension, addedBy: c.addedBy)
            file = c.url
            saved = c.cloudSystemFields
        case .note:
            guard let n = voiceNote(id) else { return nil }
            item = .init(kind: .note, id: n.id, date: n.recordedOn, duration: n.durationSeconds, year: n.year, week: n.week, ext: n.url.pathExtension, addedBy: n.addedBy)
            file = n.url
            saved = n.cloudSystemFields
        }
        let record = CloudRecords.record(fromSystemFields: saved) ?? CKRecord(recordType: kind.rawValue, recordID: recordID)
        CloudRecords.fill(record, with: item, file: FileManager.default.fileExists(atPath: file.path) ? file : nil)
        return record
    }

    /// A record arrived from iCloud: a restore on a new phone, or a relative's clip.
    private func apply(_ record: CKRecord) {
        guard let context = container?.mainContext, let item = CloudRecords.item(from: record) else { return }
        let fields = CloudRecords.systemFields(of: record)
        switch item.kind {
        case .clip:
            if let existing = clip(item.id) {
                existing.cloudSystemFields = fields
                existing.backedUpAt = existing.backedUpAt ?? .now
                return
            }
        case .note:
            if let existing = voiceNote(item.id) {
                existing.cloudSystemFields = fields
                existing.backedUpAt = existing.backedUpAt ?? .now
                return
            }
        }
        // New to this phone. The asset is at a temporary URL, so copy it in now.
        guard let asset = (record["file"] as? CKAsset)?.fileURL else { return }
        let name = "\(item.id.uuidString).\(item.ext)"
        let destination = item.kind == .clip ? MediaStore.footageURL(name) : MediaStore.noteURL(name)
        do {
            try MediaStore.ensureDirectories()
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: asset, to: destination)
        } catch {
            return
        }
        switch item.kind {
        case .clip:
            let c = Clip(id: item.id, fileName: name, capturedOn: item.date, durationSeconds: item.duration)
            c.year = item.year
            c.week = item.week
            c.addedBy = item.addedBy
            c.backedUpAt = .now
            c.cloudSystemFields = fields
            context.insert(c)
        case .note:
            let n = VoiceNote(id: item.id, fileName: name, recordedOn: item.date, durationSeconds: item.duration)
            n.year = item.year
            n.week = item.week
            n.addedBy = item.addedBy
            n.backedUpAt = .now
            n.cloudSystemFields = fields
            context.insert(n)
        }
    }

    private func markSent(_ record: CKRecord) {
        guard let (kind, id) = CloudRecords.parse(record.recordID) else { return }
        let fields = CloudRecords.systemFields(of: record)
        switch kind {
        case .clip:
            clip(id)?.backedUpAt = .now
            clip(id)?.cloudSystemFields = fields
        case .note:
            voiceNote(id)?.backedUpAt = .now
            voiceNote(id)?.cloudSystemFields = fields
        }
    }

    /// Signed out or switched Apple ID: forget everything about the old iCloud, keep the library.
    private func forgetCloudState() {
        Self.savedState = nil
        for clip in (try? container?.mainContext.fetch(FetchDescriptor<Clip>())) ?? [] {
            clip.backedUpAt = nil
            clip.cloudSystemFields = nil
        }
        for note in (try? container?.mainContext.fetch(FetchDescriptor<VoiceNote>())) ?? [] {
            note.backedUpAt = nil
            note.cloudSystemFields = nil
        }
        try? container?.mainContext.save()
    }

    // MARK: Persistence

    private static var savedState: CKSyncEngine.State.Serialization? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "iCloudSyncState") else { return nil }
            return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "iCloudSyncState")
        }
    }

    /// Record name → film year, for removals made while backup was off.
    private static var waitingDeletes: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: "iCloudWaitingDeletes") as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "iCloudWaitingDeletes") }
    }

    /// Years whose zones this phone has seen in iCloud, so Delete iCloud backup can find them all.
    private var knownZoneYears: Set<Int> {
        get { Set(UserDefaults.standard.array(forKey: "iCloudZoneYears") as? [Int] ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "iCloudZoneYears") }
    }
}

extension CloudBackup: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            Self.savedState = update.stateSerialization

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                status = .upToDate
                enqueueEverything()
            case .signOut, .switchAccounts:
                // Never merge another Apple ID's iCloud into this library.
                forgetCloudState()
                turnOff()
                status = .noAccount
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            knownZoneYears.formUnion(changes.modifications.compactMap { CloudRecords.year(of: $0.zoneID) })
            for deletion in changes.deletions {
                // A year's zone went away (deleted from another device): keep the files here,
                // and treat them as not backed up.
                guard let year = CloudRecords.year(of: deletion.zoneID) else { continue }
                knownZoneYears.remove(year)
                for clip in (try? container?.mainContext.fetch(FetchDescriptor<Clip>(predicate: #Predicate { $0.year == year }))) ?? [] {
                    clip.backedUpAt = nil
                    clip.cloudSystemFields = nil
                }
                for note in (try? container?.mainContext.fetch(FetchDescriptor<VoiceNote>(predicate: #Predicate { $0.year == year }))) ?? [] {
                    note.backedUpAt = nil
                    note.cloudSystemFields = nil
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications { apply(modification.record) }
            for deletion in changes.deletions {
                guard let (kind, id) = CloudRecords.parse(deletion.recordID) else { continue }
                // Removed on another of this person's devices: remove it here too.
                switch kind {
                case .clip: if let c = clip(id) { MediaStore.remove(c.url); container?.mainContext.delete(c) }
                case .note: if let n = voiceNote(id) { MediaStore.remove(n.url); container?.mainContext.delete(n) }
                }
            }
            try? container?.mainContext.save()

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords { markSent(record) }
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []
            var zones: [CKSyncEngine.PendingDatabaseChange] = []
            for failure in sent.failedRecordSaves {
                let id = failure.record.recordID
                switch failure.error.code {
                case .zoneNotFound:
                    zones.append(.saveZone(CKRecordZone(zoneID: id.zoneID)))
                    retry.append(.saveRecord(id))
                case .serverRecordChanged:
                    // Keep the server's change tag, then send ours again.
                    if let server = failure.error.serverRecord { markSent(server) }
                    retry.append(.saveRecord(id))
                case .unknownItem:
                    // Our saved system fields point at a record that no longer exists.
                    if let (kind, uuid) = CloudRecords.parse(id) {
                        if kind == .clip { clip(uuid)?.cloudSystemFields = nil } else { voiceNote(uuid)?.cloudSystemFields = nil }
                    }
                    retry.append(.saveRecord(id))
                case .quotaExceeded:
                    status = .full
                default:
                    break  // the engine retries transient errors itself
                }
            }
            if !zones.isEmpty { syncEngine.state.add(pendingDatabaseChanges: zones) }
            if !retry.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: retry) }
            try? container?.mainContext.save()
            updateSending()

        case .sentDatabaseChanges(let sent):
            knownZoneYears.formUnion(sent.savedZones.compactMap { CloudRecords.year(of: $0.zoneID) })
            for deleted in sent.deletedZoneIDs { knownZoneYears.remove(CloudRecords.year(of: deleted) ?? -1) }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        // Build the records here, on the main actor, then hand them over by ID. An item removed
        // before it was sent has nothing to send, so its pending save is dropped.
        var records: [CKRecord.ID: CKRecord] = [:]
        var gone: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in changes {
            guard case .saveRecord(let id) = change else { continue }
            if let record = record(for: id) { records[id] = record } else { gone.append(change) }
        }
        if !gone.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: gone) }
        let ready = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes.filter { !gone.contains($0) }) { ready[$0] }
    }
}
