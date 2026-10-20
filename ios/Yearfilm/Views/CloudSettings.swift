import CloudKit
import SwiftUI

/// Settings → iCloud: backing up to the person's own iCloud, and deleting that backup.
struct BackupSection: View {
    @State private var confirmDeleteBackup = false
    @State private var on = CloudBackup.shared.isOn

    private var backup: CloudBackup { .shared }

    var body: some View {
        Section {
            Toggle("Back up to iCloud", isOn: Binding(get: { on }, set: { value in
                on = value
                if value { backup.turnOn() } else { backup.turnOff() }
            }))
            if on {
                LabeledContent("Status", value: statusText)
            }
            if on || backup.status != .off {
                Button("Delete iCloud backup", role: .destructive) { confirmDeleteBackup = true }
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text(on
                 ? "Your clips and voice notes are copied to your own iCloud, so a new iPhone signed in with your Apple ID gets them back. Yearfilm never sees them. They use your iCloud storage."
                 : "Everything stays on this iPhone. Turn this on to keep a copy in your own iCloud.")
        }
        .confirmationDialog("Delete your iCloud backup?", isPresented: $confirmDeleteBackup, titleVisibility: .visible) {
            Button("Delete iCloud backup", role: .destructive) {
                Task {
                    await backup.deleteBackup()
                    on = backup.isOn
                }
            }
        } message: {
            Text("Every year’s backup is removed from your iCloud. A year you shared with family ends for everyone in it, including the clips they added. Everything on this iPhone stays.")
        }
    }

    private var statusText: String {
        switch backup.status {
        case .off, .starting: "Starting…"
        case .upToDate: "Up to date"
        case .sending(let n): "Backing up \(n) \(n == 1 ? "item" : "items")…"
        case .noAccount: "Sign in to iCloud in Settings"
        case .full: "iCloud is full — nothing new is backed up"
        case .failed(let message): message
        }
    }
}

/// Settings → Family: inviting relatives to a year's film, or the film this person helps make.
struct FamilySection: View {
    @AppStorage("familyName") private var familyName = ""
    @AppStorage("yourName") private var yourName = ""
    @State private var askForWeeks = false
    @State private var weeks: Set<Int> = [FilmWeek(date: .now).week]
    @State private var confirmLeave = false

    private let year = Calendar.current.component(.year, from: .now)
    private var family: FamilyShare { .shared }

    var body: some View {
        Section {
            TextField("Your name", text: $yourName)
                .textContentType(.givenName)
            if let joined = family.membership {
                LabeledContent("Helping make", value: "\(joined.familyName)’s \(String(joined.year)) film")
                LabeledContent("Asking for", value: weeksLabel(joined.weeks, year: nil).capitalizedFirst)
                Button(family.sending ? "Sending…" : "Send my clips now") { Task { await family.send() } }
                    .disabled(family.sending)
                Button("Leave this film", role: .destructive) { confirmLeave = true }
            } else if CloudBackup.shared.isOn && CloudRecords.isAvailable {
                Toggle("Only certain weeks", isOn: $askForWeeks)
                if askForWeeks {
                    WeekPicker(selection: $weeks, year: year)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }
                ShareLink(
                    item: FilmInvite(year: year, familyName: familyName.isEmpty ? "Our family" : familyName, weeks: askForWeeks ? weeks.sorted() : nil),
                    preview: SharePreview("\(familyName.isEmpty ? "Our family" : familyName)’s \(String(year)) film", image: Image("Mark"))
                ) {
                    Label("Invite family to the \(String(year)) film", systemImage: "person.badge.plus")
                }
            } else {
                Text("Turn on iCloud backup to invite family. Their clips arrive in your backup.")
                    .foregroundStyle(.secondary)
            }
            if let error = family.lastError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Family")
        } footer: {
            Text(family.membership != nil
                 ? "Your clips from those weeks go to their film through iCloud, and they can see them. Nothing else on this iPhone is sent."
                 : "Relatives who accept send their clips from this year into your film through iCloud. Their clips use your iCloud storage. Your name shows next to what you add.")
        }
        .confirmationDialog("Leave this film?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await family.leave() } }
        } message: {
            Text("You stop sending clips. What you already sent stays in the film.")
        }
    }
}

/// What the share sheet sends: an iCloud share for this year's film, made when it's needed.
struct FilmInvite: Transferable {
    let year: Int
    let familyName: String
    let weeks: [Int]?

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { invite in
            .prepareShare(
                container: CKContainer(identifier: CloudRecords.containerID),
                // Invited people only, who can add clips: no "anyone with the link" option.
                allowedSharingOptions: CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readWrite, allowedParticipantAccessOptions: .specifiedRecipientsOnly)
            ) {
                try await FamilyShare.shared.share(year: invite.year, familyName: invite.familyName, weeks: invite.weeks)
            }
        }
    }
}

/// 52 week chips for choosing which weeks to ask family for.
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

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
