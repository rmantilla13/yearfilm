import AVKit
import SwiftData
import SwiftUI

/// The week's voice notes: a glass card with one big record button and the notes so far.
/// Recording is only offered for the current week — a note is filed under the week it was
/// recorded in, so recording from an older week's page would land it in this one.
struct VoiceNoteSection: View {
    let notes: [VoiceNote]
    var canRecord = true

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var recorder = Recorder()
    @State private var player = NotePlayer()
    @State private var micDenied = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if canRecord {
                HStack(spacing: 16) {
                    RecordButton(isRecording: recorder.isRecording) {
                        if recorder.isRecording { recorder.stop() } else { Task { await startRecording() } }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if recorder.isRecording {
                            Text("Listening…").font(.system(.title3, design: .serif))
                            Text("\(TimeText.duration(recorder.elapsed)) of \(TimeText.duration(Recorder.maxLength)) · tap to stop")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Text(notes.isEmpty ? "What happened this week?" : "Add another note")
                                .font(.system(.title3, design: .serif))
                            Text("Up to a minute, in your own words. In December, these become the narration.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !notes.isEmpty {
                VStack(spacing: 8) {
                    ForEach(notes) { note in
                        NoteRow(note: note, playing: player.playing == note.url) { player.toggle(note.url) }
                            .contextMenu {
                                Button("Remove from your film", systemImage: "trash", role: .destructive) {
                                    if player.playing == note.url { player.stop() }
                                    Library.remove(note, from: context)
                                }
                            }
                    }
                }
            } else if !canRecord {
                Text("No voice note this week.").foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
        .alert("Microphone is off for Yearfilm", isPresented: $micDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Voice notes need the microphone. You can turn it on in Settings.")
        }
        .alert("Couldn’t record", isPresented: .constant(failure != nil), presenting: failure) { _ in
            Button("OK") { failure = nil }
        } message: { Text($0) }
    }

    @MainActor
    private func startRecording() async {
        player.stop()
        recorder.onFinish = { name, length in
            context.insert(VoiceNote(fileName: name, durationSeconds: length))
            try? context.save()
        }
        do {
            if try await recorder.start() == .denied { micDenied = true }
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// A round, glowing button: a microphone, or a stop square that pulses while recording.
private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(isRecording ? Color.red.opacity(0.85) : Color.glow)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(isRecording ? .white : Color.ground)
            }
            .frame(width: 64, height: 64)
            .softGlow(radius: isRecording ? 18 : 12, opacity: isRecording ? 0.2 : 0.55)
            .shadow(color: .red.opacity(isRecording ? 0.6 : 0), radius: 16)
            .phaseAnimator(isRecording && !reduceMotion ? [1.0, 1.08] : [1.0]) { view, scale in
                view.scaleEffect(scale)
            } animation: { _ in .easeInOut(duration: 0.8) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record a voice note")
    }
}

private struct NoteRow: View {
    let note: VoiceNote
    let playing: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: playing ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.glow)
                Text(note.recordedOn, format: .dateTime.weekday(.wide).hour().minute())
                Spacer()
                Text(TimeText.duration(note.durationSeconds))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice note from \(note.recordedOn.formatted(.dateTime.weekday(.wide).hour().minute())), \(TimeText.duration(note.durationSeconds))")
        .accessibilityHint(playing ? "Stops it" : "Plays it")
    }
}

struct ClipPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .ignoresSafeArea(edges: .bottom)
                .background(.black)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                }
        }
        .onAppear {
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}
