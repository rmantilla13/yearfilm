import AVFoundation
import CoreTransferable
import UIKit
import UniformTypeIdentifiers

/// Where the bytes live: Application Support/Media/{footage,notes}. On-device only in
/// this version. Each clip is copied in when picked, so the film never depends on the
/// photo library still holding it - and the app never needs library-wide access.
enum MediaStore {
    static var root: URL { URL.applicationSupportDirectory.appending(path: "Media", directoryHint: .isDirectory) }
    static var footage: URL { root.appending(path: "footage", directoryHint: .isDirectory) }
    static var notes: URL { root.appending(path: "notes", directoryHint: .isDirectory) }

    static func footageURL(_ name: String) -> URL { footage.appending(path: name) }
    static func noteURL(_ name: String) -> URL { notes.appending(path: name) }

    static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: footage, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
    }

    static func importMovie(from source: URL) throws -> String {
        try ensureDirectories()
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        try FileManager.default.copyItem(at: source, to: footageURL(name))
        return name
    }

    static func newNoteName() -> String { "\(UUID().uuidString).m4a" }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Settings → Delete all my data. Removes every byte the app holds.
    static func deleteEverything() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }
}

/// A video picked with PhotosPicker, copied into MediaStore before the system's
/// temporary file disappears.
struct PickedMovie: Transferable {
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            PickedMovie(fileName: try MediaStore.importMovie(from: received.file))
        }
    }
}

/// What a video file says about itself. Reading the date from the file rather than
/// from PHAsset is what lets the app work with no photo library permission at all.
struct MovieInfo {
    let capturedOn: Date?
    let duration: Double

    static func read(_ url: URL) async -> MovieInfo {
        let asset = AVURLAsset(url: url)
        var seconds = 0.0
        if let time = try? await asset.load(.duration) {
            seconds = CMTimeGetSeconds(time)
        }
        var date: Date?
        if let item = try? await asset.load(.creationDate) {
            date = try? await item.load(.dateValue)
        }
        return MovieInfo(capturedOn: date, duration: seconds.isFinite ? seconds : 0)
    }

    /// Frames already pulled from clips, so scrolling back and switching tabs don't decode them again.
    private static let thumbnails: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func thumbnail(_ url: URL, maxSide: CGFloat = 320) async -> UIImage? {
        let key = "\(url.lastPathComponent)@\(Int(maxSide))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let image = await makeThumbnail(url, maxSide: maxSide)
        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }

    private static func makeThumbnail(_ url: URL, maxSide: CGFloat) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)
        guard let result = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) else {
            return nil
        }
        return UIImage(cgImage: result.image)
    }
}
