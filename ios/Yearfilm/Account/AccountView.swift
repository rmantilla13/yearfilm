import SwiftUI

/// Settings → Backup → Account: your name, your family, who's in it, invite links, and
/// signing out or deleting the account.
struct AccountView: View {
    @AppStorage(Uploader.enabledKey) private var backupOn = false
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var familyName = ""
    @State private var members: [Account.Member] = []
    @State private var invites: [Account.Invite] = []
    @State private var inviting = false
    @State private var confirmDelete = false
    @State private var failure: String?

    private var account: Account { .shared }

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $name)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .onSubmit { Task { await run { try await account.setDisplayName(name) } } }
            } header: {
                Text("Profile")
            } footer: {
                Text("Your family sees this next to the clips you add.")
            }

            if let family = account.family {
                Section {
                    if family.isProducer {
                        TextField("Family name", text: $familyName)
                            .submitLabel(.done)
                            .onSubmit { Task { await run { try await account.renameFamily(familyName) } } }
                    } else {
                        LabeledContent("Film", value: family.name)
                    }
                    LabeledContent("You", value: roleText(family.role, weeks: family.weeks, year: family.year))
                } header: {
                    Text("Family")
                }

                Section("Who’s in it") {
                    ForEach(members) { member in
                        LabeledContent(
                            (member.name ?? "Someone") + (member.isYou ? " (you)" : ""),
                            value: roleText(member.role, weeks: member.weeks, year: member.year)
                        )
                    }
                }

                if family.isProducer {
                    Section {
                        Button {
                            inviting = true
                        } label: {
                            Label("Invite family", systemImage: "person.badge.plus")
                        }
                        ForEach(invites.filter { $0.state == "open" }) { invite in
                            LabeledContent(
                                weeksLabel(invite.weeks, year: invite.year).capitalizedFirst,
                                value: invite.uses == 1 ? "1 joined" : "\(invite.uses) joined"
                            )
                            .swipeActions {
                                Button("Turn off", role: .destructive) {
                                    Task { await run { try await account.revokeInvite(invite.id); await load() } }
                                }
                            }
                        }
                    } header: {
                        Text("Invite links")
                    } footer: {
                        Text("Anyone with a link can join until it expires or you turn it off. Swipe a link to turn it off; people who already joined stay.")
                    }
                }
            }

            Section {
                Button("Sign out") {
                    Task {
                        await account.signOut()
                        backupOn = false
                        dismiss()
                    }
                }
                Button("Delete account", role: .destructive) { confirmDelete = true }
            }
        }
        .memoryPoolBackground(intensity: 0.5)
        .navigationTitle("Account")
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $inviting, onDismiss: { Task { await load() } }) {
            InviteSheet()
        }
        .confirmationDialog("Delete your Yearfilm account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account and backups", role: .destructive) {
                Task {
                    await run {
                        try await account.deleteAccount()
                        backupOn = false
                        dismiss()
                    }
                }
            }
        } message: {
            Text("If you’re the film’s only producer, every backed-up clip and voice note in your family’s film is deleted from Yearfilm’s servers. The copies on this iPhone stay. This can’t be undone.")
        }
        .alert("Something went wrong", isPresented: .constant(failure != nil), presenting: failure) { _ in
            Button("OK") { failure = nil }
        } message: { Text($0) }
    }

    private func load() async {
        await run {
            try await account.refresh()
            name = account.displayName ?? ""
            familyName = account.family?.name ?? ""
            guard let family = account.family else { return }
            members = try await account.members()
            invites = family.isProducer ? try await account.invites() : []
        }
    }

    private func run(_ work: () async throws -> Void) async {
        do { try await work() } catch { failure = error.localizedDescription }
    }

    private func roleText(_ role: String, weeks: [Int]?, year: Int?) -> String {
        switch role {
        case "producer": "Producer"
        case "viewer": "Viewer"
        default: weeks == nil ? "Contributor" : "Contributor, \(weeksLabel(weeks, year: nil))"
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
