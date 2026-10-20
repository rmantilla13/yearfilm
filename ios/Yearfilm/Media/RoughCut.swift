import AVFoundation
import UIKit

/// Turns a RoughCutPlan into a playable AVPlayerItem: one composition, cut in place, so
/// nothing is rendered or written to disk. Cards are black gaps the player screen titles.
enum RoughCut {
    static let renderSize = CGSize(width: 1280, height: 720)
    /// Clip sound sits under everything; quieter still while a voice note plays.
    static let clipVolume: Float = 0.45
    static let duckedVolume: Float = 0.12

    static func item(for plan: RoughCutPlan) async throws -> AVPlayerItem {
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sound = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let voice = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CocoaError(.featureUnsupported) }

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
        var t = CMTime.zero

        for (index, piece) in plan.pieces.enumerated() {
            let length = CMTime(seconds: piece.seconds, preferredTimescale: 600)
            switch piece {
            case .card:
                // AVPlayer fails to play (-11800 / -12784) a video track with empty edits, so a
                // card is the start of the next shot at zero opacity: black, but real media.
                let next = plan.pieces[(index + 1)...].lazy.compactMap { p -> RoughCutPlan.Source? in
                    if case .shot(let s, _, _) = p { s } else { nil }
                }.first
                let filler = next.map { AVURLAsset(url: $0.url) }
                if let filler, let track = try await filler.loadTracks(withMediaType: .video).first {
                    let available = try await filler.load(.duration)
                    let take = CMTimeMinimum(available, length)
                    try video.insertTimeRange(CMTimeRange(start: .zero, duration: take), of: track, at: t)
                    if take < length {
                        video.scaleTimeRange(CMTimeRange(start: t, duration: take), toDuration: length)
                    }
                } else {
                    video.insertEmptyTimeRange(CMTimeRange(start: t, duration: length))
                }
                sound.insertEmptyTimeRange(CMTimeRange(start: t, duration: length))
                layer.setOpacity(0, at: t)
            case .shot(let source, let from, _):
                let asset = AVURLAsset(url: source.url)
                let range = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600), duration: length)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    video.insertEmptyTimeRange(CMTimeRange(start: t, duration: length))
                    sound.insertEmptyTimeRange(CMTimeRange(start: t, duration: length))
                    break
                }
                try video.insertTimeRange(range, of: track, at: t)
                if let audio = try await asset.loadTracks(withMediaType: .audio).first {
                    try sound.insertTimeRange(range, of: audio, at: t)
                } else {
                    sound.insertEmptyTimeRange(CMTimeRange(start: t, duration: length))
                }
                let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
                layer.setOpacity(1, at: t)
                layer.setTransform(fit(size, transform), at: t)
            }
            t = t + length
        }

        var clipsHaveSound = false
        var narrated = false
        let mix = AVMutableAudioMixInputParameters(track: sound)
        mix.setVolume(clipVolume, at: .zero)
        for n in plan.narration {
            narrated = true
            let note = AVURLAsset(url: n.note.url)
            guard let track = try await note.loadTracks(withMediaType: .audio).first else { continue }
            let at = CMTime(seconds: n.at, preferredTimescale: 600)
            let length = CMTime(seconds: n.seconds, preferredTimescale: 600)
            try voice.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: track, at: at)
            mix.setVolume(duckedVolume, at: at)
            mix.setVolume(clipVolume, at: at + length)
        }
        // A track that holds nothing makes the whole item fail to play, so drop silent ones.
        clipsHaveSound = sound.segments.contains { !$0.isEmpty }
        if !clipsHaveSound { composition.removeTrack(sound) }
        if !narrated || !voice.segments.contains(where: { !$0.isEmpty }) { composition.removeTrack(voice) }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = clipsHaveSound ? [mix] : []

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: t)
        instruction.layerInstructions = [layer]
        instruction.backgroundColor = UIColor.black.cgColor
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
        return item
    }

    /// Writes the cut to a movie file and returns it. Playing a plain file is dependable
    /// everywhere; live playback of an edited composition fails to build a render pipeline on
    /// the iOS Simulator (-11800 / -12784) even though the same composition plays on a Mac.
    static func export(_ plan: RoughCutPlan) async throws -> URL {
        let item = try await item(for: plan)
        let out = URL.cachesDirectory.appending(path: "rough-cut.mov")
        try? FileManager.default.removeItem(at: out)
        guard let session = AVAssetExportSession(asset: item.asset, presetName: AVAssetExportPreset1280x720) else {
            throw CocoaError(.featureUnsupported)
        }
        session.videoComposition = item.videoComposition
        session.audioMix = item.audioMix
        if #available(iOS 18, *) {
            try await session.export(to: out, as: .mov)
        } else {
            session.outputURL = out
            session.outputFileType = .mov
            await session.export()
            if let error = session.error { throw error }
        }
        return out
    }

    /// Rotates by the clip's own orientation, then scales it to fit the frame and centers it:
    /// portrait phone video sits in the middle instead of being cropped.
    static func fit(_ natural: CGSize, _ preferred: CGAffineTransform) -> CGAffineTransform {
        let rotated = CGRect(origin: .zero, size: natural).applying(preferred)
        let scale = min(renderSize.width / abs(rotated.width), renderSize.height / abs(rotated.height))
        let w = abs(rotated.width) * scale, h = abs(rotated.height) * scale
        return preferred
            .concatenating(CGAffineTransform(translationX: -rotated.minX, y: -rotated.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (renderSize.width - w) / 2, y: (renderSize.height - h) / 2))
    }
}
