import CloudKit
import Foundation
import Observation
import SwiftData

/// Making a year's film together, through iCloud sharing.
///
/// The producer shares that year's zone of their backup (a zone-wide `CKShare`). A relative who
/// accepts sends their own clips from that year, and only the weeks asked for, into the shared
/// zone, and downloads nothing: their phone never fills with the whole family's footage. The
/// producer's backup pulls the new clips in like any other change.
@MainActor
@Observable
final class FamilyShare {
    static let shared = FamilyShare()

    /// A family film this person was invited to and accepted.
    struct Membership: Codable, Equatable {
        let zoneName: String
        let ownerName: String
        let familyName: String
        let year: Int
        let weeks: [Int]?

        var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName) }
        var info: CloudRecords.FilmInfo { .init(familyName: familyName, year: year, weeks: weeks) }
    }

    private(set) var membership: Membership? = FamilyShare.savedMembership
    private(set) var sending = false
    var lastError: String?

    @ObservationIgnored var container: ModelContainer?
    @ObservationIgnored private lazy var cloud = CKContainer(identifier: CloudRecords.containerID)

    // MARK: Producer

    /// The share for a year's film, made the first time someone invites family to it. The year's
    /// zone and a FilmInfo record saying whose film it is go with it.
    func share(year: Int, familyName: String, weeks: [Int]?) async throws -> CKShare {
        let database = cloud.privateCloudDatabase
        let zoneID = CloudRecords.zoneID(year: year)
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])

        let infoID = CKRecord.ID(recordName: CloudRecords.filmInfoName, zoneID: zoneID)
        let info = (try? await database.record(for: infoID)) ?? CKRecord(recordType: CloudRecords.filmInfoName, recordID: infoID)
        CloudRecords.fill(info, with: .init(familyName: familyName, year: year, weeks: weeks))

        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        let share = (try? await database.record(for: shareID) as? CKShare) ?? CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "\(familyName)’s \(year) film" as NSString
        // Anyone with the link can add to this year's film, like the invite links before.
        share.publicPermission = .readWrite

        let results = try await database.modifyRecords(saving: [info, share], deleting: [], savePolicy: .allKeys)
        guard case .success(let saved as CKShare) = results.saveResults[shareID] else {
            throw CKError(.internalError)
        }
        return saved
    }

    /// Changes which weeks an existing year's film asks relatives for.
    func ask(for weeks: [Int]?, year: Int, familyName: String) async throws {
        let database = cloud.privateCloudDatabase
        let infoID = CKRecord.ID(recordName: CloudRecords.filmInfoName, zoneID: CloudRecords.zoneID(year: year))
        let info = (try? await database.record(for: infoID)) ?? CKRecord(recordType: CloudRecords.filmInfoName, recordID: infoID)
        CloudRecords.fill(info, with: .init(familyName: familyName, year: year, weeks: weeks))
        _ = try await database.modifyRecords(saving: [info], deleting: [], savePolicy: .allKeys)
    }

    // MARK: Relative

    /// The system hands the app an accepted invite (see SceneDelegate).
    func accept(_ metadata: CKShare.Metadata) async {
        do {
            _ = try await cloud.accept(metadata)
            let zoneID = metadata.share.recordID.zoneID
            let infoID = CKRecord.ID(recordName: CloudRecords.filmInfoName, zoneID: zoneID)
            let record = try await cloud.sharedCloudDatabase.record(for: infoID)
            guard let info = CloudRecords.filmInfo(from: record) else { throw CKError(.unknownItem) }
            let joined = Membership(
                zoneName: zoneID.zoneName, ownerName: zoneID.ownerName,
                familyName: info.familyName, year: info.year, weeks: info.weeks
            )
            membership = joined
            Self.savedMembership = joined
            await send()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Sends this person's clips and notes for the family film: their own, from that year and the
    /// weeks asked for, that haven't been sent yet. Safe to call often.
    func send() async {
        guard var joined = membership, !sending, let context = container?.mainContext else { return }
        sending = true
        defer { sending = false }

        // The producer may have changed the weeks they're asking for.
        let infoID = CKRecord.ID(recordName: CloudRecords.filmInfoName, zoneID: joined.zoneID)
        if let record = try? await cloud.sharedCloudDatabase.record(for: infoID), let info = CloudRecords.filmInfo(from: record) {
            joined = Membership(zoneName: joined.zoneName, ownerName: joined.ownerName, familyName: info.familyName, year: info.year, weeks: info.weeks)
            membership = joined
            Self.savedMembership = joined
        }

        let name = UserDefaults.standard.string(forKey: "yourName").flatMap { $0.isEmpty ? nil : $0 }
        let clips = ((try? context.fetch(FetchDescriptor<Clip>())) ?? []).filter { $0.sharedAt == nil }
        let notes = ((try? context.fetch(FetchDescriptor<VoiceNote>())) ?? []).filter { $0.sharedAt == nil }
        var files: [UUID: URL] = [:]
        let items = clips.map { c -> CloudRecords.Item in
            files[c.id] = c.url
            return .init(kind: .clip, id: c.id, date: c.capturedOn, duration: c.durationSeconds, year: c.year, week: c.week, ext: c.url.pathExtension, addedBy: c.addedBy)
        } + notes.map { n -> CloudRecords.Item in
            files[n.id] = n.url
            return .init(kind: .note, id: n.id, date: n.recordedOn, duration: n.durationSeconds, year: n.year, week: n.week, ext: n.url.pathExtension, addedBy: n.addedBy)
        }

        // A few at a time: each carries a whole video.
        for batch in CloudRecords.toShare(items, for: joined.info).chunked(into: 4) {
            let records = batch.map { item -> CKRecord in
                let record = CKRecord(recordType: item.kind.rawValue, recordID: CloudRecords.recordID(item.kind, item.id, year: item.year, owner: joined.ownerName))
                var tagged = item
                tagged.addedBy = name ?? "Family"
                CloudRecords.fill(record, with: tagged, file: files[item.id])
                return record
            }
            do {
                let results = try await cloud.sharedCloudDatabase.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
                for (id, result) in results.saveResults {
                    guard case .success = result, let (kind, uuid) = CloudRecords.parse(id) else { continue }
                    if kind == .clip {
                        clips.first { $0.id == uuid }?.sharedAt = .now
                    } else {
                        notes.first { $0.id == uuid }?.sharedAt = .now
                    }
                }
                try? context.save()
                lastError = nil
            } catch {
                lastError = (error as? CKError)?.code == .quotaExceeded
                    ? "\(joined.familyName)’s iCloud is full, so your clips are waiting on this iPhone."
                    : error.localizedDescription
                return
            }
        }
    }

    /// Stops taking part: removes this person from the share. What they sent stays in the film.
    func leave() async {
        guard let joined = membership else { return }
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: joined.zoneID)
        _ = try? await cloud.sharedCloudDatabase.deleteRecord(withID: shareID)
        membership = nil
        Self.savedMembership = nil
    }

    private static var savedMembership: Membership? {
        get { UserDefaults.standard.data(forKey: "familyFilm").flatMap { try? JSONDecoder().decode(Membership.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "familyFilm") }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
