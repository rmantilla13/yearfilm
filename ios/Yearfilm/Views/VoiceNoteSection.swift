import AVKit
import SwiftData
import SwiftUI

struct VoiceNoteSection: View {
    let notes: [VoiceNote]

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var recorder = Recorder()
    @State private var player = NotePlayer()
    @State private var micDenied = false
    @State private var failure: String?

    var body: some View {
        ForEach(notes) { note in
            HStack {
                Button {
                    player.toggle(note.url)
                } label: {
                    Label(
                        note.recordedOn.formatted(.dateTime.weekday(.wide).hour().minute()),
                        systemImage: player.playing == note.url ? "stop.circle.fill" : "play.circle.fill"
                    )
                }
                Spacer()
                Text(TimeText.duration(note.durationSeconds))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .onDelete { offsets in
            for index in offsets {
                let note = notes[index]
                if player.playing == note.url { player.stop() }
                Library.remove(note, from: context)
            }
        }

        Group {
            if recorder.isRecording {
                HStack {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative)
                        .foregroundStyle(.red)
                    Text("\(TimeText.duration(recorder.elapsed)) / \(TimeText.duration(Recorder.maxLength))")
                        .monospacedDigit()
                    Spacer()
                    Button("Stop") { recorder.stop() }
                        .bold()
                }
            } else {
                Button {
                    Task { await startRecording() }
                } label: {
                    Label(notes.isEmpty ? "Record this week’s note" : "Record another", systemImage: "mic.circle.fill")
                }
            }
        }
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
