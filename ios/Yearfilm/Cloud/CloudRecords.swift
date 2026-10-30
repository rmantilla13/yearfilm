import CloudKit
import Foundation

/// How clips and voice notes look in CloudKit. Pure: no container, no network, so it's tested.
///
/// One record zone per film year (`Film-2026`) in the owner's private database. Sharing a year
/// shares exactly that zone, so an invite covers one film and nothing else.
enum CloudRecords {
    static let containerID = "iCloud.com.yearfilm.app"

    /// False in builds without the iCloud entitlement (unsigned, as in CI), where touching
    /// CloudKit would crash. Set by YF_CLOUDKIT in project.yml.
    static var isAvailable: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "YFCloudKit") as? String)?.uppercased() == "YES"
    }

    enum Kind: String, CaseIterable, Sendable {
        case clip = "Clip"
        case note = "VoiceNote"
    }

    /// What a record says about one clip or note, apart from the file itself.
    struct Item: Equatable, Sendable {
        let kind: Kind
        let id: UUID
        /// When it was filmed or recorded.
        let date: Date
        let duration: Double
        let year: Int
        let week: Int
        /// The file's extension, so a restored file keeps its type.
        let ext: String
        /// Who added it, when it came through a family share.
        var addedBy: String?
    }

    /// The record that names and describes a shared year's film.
    struct FilmInfo: Equatable, Sendable {
        var familyName: String
        var year: Int
        /// The weeks the producer is asking relatives for; nil asks for the whole year.
        var weeks: [Int]?
    }

    static let filmInfoName = "FilmInfo"

    static func zoneID(year: Int, owner: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "Film-\(year)", ownerName: owner)
    }

    /// The film year a zone holds, or nil for a zone that isn't one of ours.
    static func year(of zone: CKRecordZone.ID) -> Int? {
        guard zone.zoneName.hasPrefix("Film-") else { return nil }
        return Int(zone.zoneName.dropFirst(5))
    }

    static func recordID(_ kind: Kind, _ id: UUID, year: Int, owner: String = CKCurrentUserDefaultName) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(kind.rawValue)-\(id.uuidString)", zoneID: zoneID(year: year, owner: owner))
    }

    /// The kind and id a record name stands for.
    static func parse(_ id: CKRecord.ID) -> (kind: Kind, id: UUID)? {
        let parts = id.recordName.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = Kind(rawValue: parts[0]), let uuid = UUID(uuidString: parts[1]) else { return nil }
        return (kind, uuid)
    }

    /// Fills a record from an item. `file` becomes the record's asset when given.
    static func fill(_ record: CKRecord, with item: Item, file: URL?) {
        record["date"] = item.date as NSDate
        record["duration"] = item.duration as NSNumber
        record["year"] = item.year as NSNumber
        record["week"] = item.week as NSNumber
        record["ext"] = item.ext as NSString
        record["addedBy"] = item.addedBy.map { $0 as NSString }
        if let file { record["file"] = CKAsset(fileURL: file) }
    }

    static func item(from record: CKRecord) -> Item? {
        guard let (kind, id) = parse(record.recordID),
              let date = record["date"] as? Date,
              let year = record["year"] as? Int,
              let week = record["week"] as? Int
        else { return nil }
        let ext = (record["ext"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (kind == .clip ? "mov" : "m4a")
        return Item(
            kind: kind,
            id: id,
            date: date,
            duration: record["duration"] as? Double ?? 0,
            year: year,
            week: week,
            ext: ext.lowercased(),
            addedBy: record["addedBy"] as? String
        )
    }

    static func fill(_ record: CKRecord, with info: FilmInfo) {
        record["familyName"] = info.familyName as NSString
        record["year"] = info.year as NSNumber
        record["weeks"] = info.weeks.map { $0 as NSArray }
    }

    static func filmInfo(from record: CKRecord) -> FilmInfo? {
        guard let year = record["year"] as? Int else { return nil }
        let name = (record["familyName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Your family"
        let weeks = (record["weeks"] as? [Int]).flatMap { $0.isEmpty ? nil : $0.sorted() }
        return FilmInfo(familyName: name, year: year, weeks: weeks)
    }

    /// What a relative sends to a family film: their own clips and notes from that year, and
    /// only the weeks asked for. The share can't enforce this, so the app does.
    static func toShare(_ items: [Item], for info: FilmInfo) -> [Item] {
        items.filter { item in
            item.addedBy == nil && item.year == info.year && (info.weeks?.contains(item.week) ?? true)
        }
    }

    /// Records from iCloud that aren't in the library yet, once each.
    static func newItems(_ incoming: [Item], known: Set<UUID>) -> [Item] {
        var seen = known
        return incoming.filter { seen.insert($0.id).inserted }
    }

    /// Encodes a record's system fields (its server identity and change tag) for keeping locally.
    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    /// A record carrying the system fields kept earlier, or nil if there are none or they don't decode.
    static func record(fromSystemFields data: Data?) -> CKRecord? {
        guard let data, let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}

/// "any week", "week 30", "weeks 47–48 of 2026".
func weeksLabel(_ weeks: [Int]?, year: Int?) -> String {
    guard let weeks, let first = weeks.first else { return "any week" }
    var runs: [String] = []
    var start = first, prev = first
    for w in weeks.dropFirst() + [Int.min] {
        if w == prev + 1 { prev = w; continue }
        runs.append(start == prev ? "\(start)" : "\(start)–\(prev)")
        start = w; prev = w
    }
    let noun = weeks.count > 1 ? "weeks" : "week"
    return "\(noun) \(runs.joined(separator: ", "))" + (year.map { " of \(String($0))" } ?? "")
}
