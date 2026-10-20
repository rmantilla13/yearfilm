import PhotosUI
import SwiftData
import SwiftUI

// The app's building blocks, in one visual language: serif display type, glass surfaces over
// the pool, and footage shown as frames of film rather than rows in a list.

/// A screen's title: a small glowing eyebrow over a serif headline.
struct ScreenHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(Color.glow)
            Text(title)
                .font(.system(size: 40, weight: .regular, design: .serif))
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

/// A section title in the same voice as the header, with an optional count on the right.
struct SectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title3, design: .serif))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

extension FilmWeek {
    /// "Oct 15 – 21", or "Dec 24 – 31" for the last week, which takes in the year's last days.
    func dateRange(calendar: Calendar = .current) -> String {
        let start = start(calendar: calendar)
        let end: Date = week == FilmWeek.count
            ? calendar.date(from: DateComponents(year: year, month: 12, day: 31))!
            : calendar.date(byAdding: .day, value: 6, to: start)!
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        let first = start.formatted(.dateTime.month(.abbreviated).day())
        let last = sameMonth ? end.formatted(.dateTime.day()) : end.formatted(.dateTime.month(.abbreviated).day())
        return "\(first) – \(last)"
    }
}

/// A week's footage as a strip of 16:9 frames, ending in a tile that adds more.
struct Filmstrip: View {
    let clips: [Clip]
    @Binding var picked: [PhotosPickerItem]
    var play: (Clip) -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        if clips.isEmpty {
            // Nothing to scroll through yet: one full-width invitation instead of a lone tile.
            PhotosPicker(selection: $picked, maxSelectionCount: nil, matching: .videos, preferredItemEncoding: .current) {
                AddClipsTile(wide: true)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        } else {
            strip
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(clips) { clip in
                    Button { play(clip) } label: { ClipFrame(clip: clip) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove from your film", systemImage: "trash", role: .destructive) {
                                Library.remove(clip, from: context)
                            }
                        }
                }
                // PhotosPicker runs out of process: the app sees only what is picked, so it
                // needs no photo library permission. No limit: pick a whole year at once and each
                // clip is filed under the week it was filmed. `.current` hands over the original
                // file, so its filming date survives.
                PhotosPicker(selection: $picked, maxSelectionCount: nil, matching: .videos, preferredItemEncoding: .current) {
                    AddClipsTile(wide: false)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }
}

/// One clip: its frame, when it was filmed, and how long it runs.
struct ClipFrame: View {
    let clip: Clip
    @State private var image: UIImage?

    var body: some View {
        // The frame's size is fixed first and the picture fills it from behind, so a tall
        // (portrait) thumbnail can't stretch the frame and push the labels out of view.
        ZStack(alignment: .bottomLeading) {
            Color.white.opacity(0.06)
                .overlay {
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                }
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            HStack {
                Text(clip.capturedOn, format: .dateTime.weekday(.abbreviated).day())
                Spacer()
                Text(TimeText.duration(clip.durationSeconds)).monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(10)
        }
        .frame(width: 208, height: 117)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.glow.opacity(0.25), lineWidth: 1))
        .task(id: clip.url) { image = await MovieInfo.thumbnail(clip.url) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clip from \(clip.capturedOn.formatted(.dateTime.weekday(.wide).month().day())), \(TimeText.duration(clip.durationSeconds))")
        .accessibilityHint("Plays the clip")
    }
}

/// The last frame in the strip. On an empty week it's wide and says what to do.
struct AddClipsTile: View {
    var wide: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.glow)
                .softGlow(radius: 10, opacity: 0.5)
            Text(wide ? "Add this week’s clips" : "Add clips")
                .font(.subheadline.weight(.semibold))
            if wide {
                Text("Or a whole batch from any time — each goes to the week it was filmed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: wide ? .infinity : 120, minHeight: 117)
        .frame(width: wide ? nil : 120)
        .glassCard(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.glow.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
