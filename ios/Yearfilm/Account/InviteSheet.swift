import SwiftUI

/// Makes a link a producer can send to family: for the whole year, or just some weeks
/// ("send us your Thanksgiving clips").
struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var specificWeeks = false
    @State private var weeks: Set<Int> = [FilmWeek(date: .now).week]
    @State private var viewer = false
    @State private var link: URL?
    @State private var busy = false
    @State private var failure: String?

    private let year = Calendar.current.component(.year, from: .now)
    private var family: Account.Family? { Account.shared.family }

    var body: some View {
        NavigationStack {
            Form {
                if let link {
                    Section {
                        Text(summary)
                        ShareLink(item: link, message: Text(shareMessage)) {
                            Label("Share link", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButton())
                        .listRowBackground(Color.clear)
                    } footer: {
                        Text("The link works for 14 days. Whoever opens it signs in with Apple and joins \(family?.name ?? "your family")’s film.")
                    }
                } else {
                    Section {
                        Toggle("Just watch, don’t add clips", isOn: $viewer)
                        if !viewer {
                            Toggle("Only certain weeks", isOn: $specificWeeks)
                        }
                    } footer: {
                        Text(viewer
                             ? "They’ll be able to see the film, not add to it."
                             : specificWeeks
                             ? "They can add clips filmed in the weeks you pick, and nothing else."
                             : "They can add clips from any week of the year.")
                    }
                    if specificWeeks && !viewer {
                        Section("Weeks of \(String(year))") {
                            WeekPicker(selection: $weeks, year: year)
                                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                        }
                    }
                    Section {
                        Button(busy ? "Making link…" : "Make link") { Task { await make() } }
                            .buttonStyle(PrimaryButton())
                            .listRowBackground(Color.clear)
                            .disabled(busy || (specificWeeks && !viewer && weeks.isEmpty))
                    }
                }
            }
            .memoryPoolBackground(intensity: 0.4)
            .navigationTitle("Invite family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .alert("Couldn’t make the link", isPresented: .constant(failure != nil), presenting: failure) { _ in
                Button("OK") { failure = nil }
            } message: { Text($0) }
        }
    }

    private var chosenWeeks: [Int]? { specificWeeks && !viewer ? weeks.sorted() : nil }

    private var summary: String {
        viewer ? "A link to watch the film." : "A link to add clips from \(weeksLabel(chosenWeeks, year: chosenWeeks == nil ? nil : year))."
    }

    private var shareMessage: String {
        let name = family?.name ?? "our family"
        return viewer
            ? "Watch \(name)’s \(year) film with us on Yearfilm."
            : "Help make \(name)’s \(year) film — send your videos from \(weeksLabel(chosenWeeks, year: nil)) on Yearfilm."
    }

    private func make() async {
        busy = true
        defer { busy = false }
        do {
            link = try await Account.shared.createInvite(role: viewer ? "viewer" : "contributor", weeks: chosenWeeks, year: year).url
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// 52 week chips; past and current weeks are tappable, future weeks too (a trip coming up).
struct WeekPicker: View {
    @Binding var selection: Set<Int>
    let year: Int
    private let current = FilmWeek(date: .now)

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(1...FilmWeek.count, id: \.self) { w in
                let on = selection.contains(w)
                Button {
                    if on { selection.remove(w) } else { selection.insert(w) }
                } label: {
                    Text("\(w)")
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(on ? Color.ground : Color.primary)
                        .background(on ? Color.glow : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            if FilmWeek(year: year, week: w) == current {
                                RoundedRectangle(cornerRadius: 8).stroke(Color.glow.opacity(0.8), lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Week \(w)\(on ? ", selected" : "")")
            }
        }
    }
}
