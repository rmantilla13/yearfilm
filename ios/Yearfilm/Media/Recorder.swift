import AVFoundation
import Observation

/// Records one voice note at a time, capped at a minute: a note is a few sentences
/// over a chapter card, not a podcast.
@Observable
final class Recorder: NSObject, AVAudioRecorderDelegate {
    static let maxLength: TimeInterval = 60

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// Called with the file name and length once a recording is finished and on disk.
    @ObservationIgnored var onFinish: ((String, TimeInterval) -> Void)?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var fileName: String?

    enum StartResult { case started, denied }

    @MainActor
    func start() async throws -> StartResult {
        // Asked here, at the moment of recording, never at launch.
        guard await AVAudioApplication.requestRecordPermission() else { return .denied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)
        try MediaStore.ensureDirectories()

        let name = MediaStore.newNoteName()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: MediaStore.noteURL(name), settings: settings)
        recorder.delegate = self
        recorder.record(forDuration: Self.maxLength)

        self.recorder = recorder
        fileName = name
        elapsed = 0
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder else { return }
            self.elapsed = recorder.currentTime
        }
        return .started
    }

    func stop() {
        guard let recorder else { return }
        elapsed = recorder.currentTime  // currentTime resets once stopped
        recorder.stop()  // -> audioRecorderDidFinishRecording
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        timer?.invalidate()
        timer = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let length = elapsed > 0 ? elapsed : Self.maxLength
        if flag, let fileName, length >= 1 {
            onFinish?(fileName, length)
        } else if let fileName {
            MediaStore.remove(MediaStore.noteURL(fileName))  // a tap, not a note
        }
        self.recorder = nil
        self.fileName = nil
    }
}

/// Plays one voice note at a time.
@Observable
final class NotePlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var playing: URL?
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playing == url {
            stop()
            return
        }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.play()
        self.player = player
        playing = url
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stop()
    }
}
