import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Turns a RoughCutPlan into a 16:9 movie: one composition, cut in place, with every frame
/// drawn by Core Image so each clip can be stood upright and framed for a TV.
enum RoughCut {
    static let renderSize = CGSize(width: 1280, height: 720)
    /// Clip sound sits under everything; quieter still while a voice note plays.
    static let clipVolume: Float = 0.45
    static let duckedVolume: Float = 0.12

    /// What occupies one stretch of the timeline, so the frame handler knows how to draw it.
    struct Segment: Sendable {
        let range: CMTimeRange
        let orientation: CGImagePropertyOrientation
        let isCard: Bool
    }

    static func item(for plan: RoughCutPlan) async throws -> AVPlayerItem {
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sound = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let voice = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CocoaError(.featureUnsupported) }

        var segments: [Segment] = []
        var t = CMTime.zero

        for (index, piece) in plan.pieces.enumerated() {
            let length = CMTime(seconds: piece.seconds, preferredTimescale: 600)
            let range = CMTimeRange(start: t, duration: length)
            switch piece {
            case .card:
                // AVPlayer fails to play (-11800 / -12784) a video track with empty edits, so a
                // card is the start of the next shot underneath, drawn as black.
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
                    video.insertEmptyTimeRange(range)
                }
                sound.insertEmptyTimeRange(range)
                segments.append(Segment(range: range, orientation: .up, isCard: true))
            case .shot(let source, let from, _):
                let asset = AVURLAsset(url: source.url)
                let take = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600), duration: length)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    video.insertEmptyTimeRange(range)
                    sound.insertEmptyTimeRange(range)
                    segments.append(Segment(range: range, orientation: .up, isCard: true))
                    break
                }
                try video.insertTimeRange(take, of: track, at: t)
                if let audio = try await asset.loadTracks(withMediaType: .audio).first {
                    try sound.insertTimeRange(take, of: audio, at: t)
                } else {
                    sound.insertEmptyTimeRange(range)
                }
                let transform = try await track.load(.preferredTransform)
                segments.append(Segment(range: range, orientation: orientation(of: transform), isCard: false))
            }
            t = t + length
        }

        var narrated = false
        let mix = AVMutableAudioMixInputParameters(track: sound)
        mix.setVolume(clipVolume, at: .zero)
        for n in plan.narration {
            let note = AVURLAsset(url: n.note.url)
            guard let track = try await note.loadTracks(withMediaType: .audio).first else { continue }
            let at = CMTime(seconds: n.at, preferredTimescale: 600)
            let length = CMTime(seconds: n.seconds, preferredTimescale: 600)
            try voice.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: track, at: at)
            mix.setVolume(duckedVolume, at: at)
            mix.setVolume(clipVolume, at: at + length)
            narrated = true
        }
        // A track that holds nothing makes the whole item fail to play, so drop silent ones.
        let clipsHaveSound = sound.segments.contains { !$0.isEmpty }
        if !clipsHaveSound { composition.removeTrack(sound) }
        if !narrated { composition.removeTrack(voice) }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = clipsHaveSound ? [mix] : []

        let item = AVPlayerItem(asset: composition)
        item.videoComposition = try await videoComposition(for: composition, segments: segments)
        item.audioMix = audioMix
        return item
    }

    /// Every output frame: black for a card, otherwise the clip stood upright and framed.
    private static func videoComposition(for composition: AVComposition, segments: [Segment]) async throws -> AVVideoComposition {
        let size = renderSize
        let black = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        let draw: @Sendable (AVAsynchronousCIImageFilteringRequest) -> Void = { request in
            let time = request.compositionTime
            guard let segment = segments.first(where: { $0.range.containsTime(time) }), !segment.isCard else {
                return request.finish(with: black, context: nil)
            }
            request.finish(with: frame(request.sourceImage, orientation: segment.orientation, in: size), context: nil)
        }
        let made: AVMutableVideoComposition
        if #available(iOS 18, *) {
            made = try await AVMutableVideoComposition.videoComposition(with: composition, applyingCIFiltersWithHandler: draw)
        } else {
            made = AVMutableVideoComposition(asset: composition, applyingCIFiltersWithHandler: draw)
        }
        made.renderSize = size
        made.frameDuration = CMTime(value: 1, timescale: 30)
        return made
    }

    /// Fits a clip into the 16:9 frame. A clip that doesn't fill it — vertical phone video,
    /// mostly — sits over a blurred, darkened, enlarged copy of itself instead of black bars,
    /// the same treatment the film engine gives it (engine/yearfilm/render.py).
    static func frame(_ source: CIImage, orientation: CGImagePropertyOrientation, in size: CGSize) -> CIImage {
        let upright = source.oriented(orientation)
        let image = upright.transformed(by: CGAffineTransform(translationX: -upright.extent.minX, y: -upright.extent.minY))
        let w = image.extent.width, h = image.extent.height
        let canvas = CGRect(origin: .zero, size: size)
        guard w > 0, h > 0 else { return CIImage(color: .black).cropped(to: canvas) }

        func placed(_ scale: CGFloat) -> CIImage {
            image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: (size.width - w * scale) / 2, y: (size.height - h * scale) / 2))
        }
        let fit = min(size.width / w, size.height / h)
        let front = placed(fit)
        // Within a couple of pixels of filling the frame: nothing to put behind it.
        if size.width - w * fit < 2, size.height - h * fit < 2 { return front.cropped(to: canvas) }

        let fill = max(size.width / w, size.height / h)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = placed(fill).clampedToExtent()
        blur.radius = 28
        let dim = CIFilter.exposureAdjust()
        dim.inputImage = blur.outputImage?.cropped(to: canvas)
        dim.ev = -1.2
        let behind = dim.outputImage ?? CIImage(color: .black).cropped(to: canvas)
        return front.composited(over: behind).cropped(to: canvas)
    }

    /// The way a clip has to be turned to stand upright, from its track's preferred transform.
    /// An iPhone filming in portrait records landscape pixels and a 90° turn.
    static func orientation(of t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a.rounded(), t.b.rounded(), t.c.rounded(), t.d.rounded()) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
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
}
