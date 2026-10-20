import AuthenticationServices
import SwiftUI

/// Shown when the app opens from an invite link. Says whose film it is and what joining
/// sends, then signs in and joins. Works before onboarding, so a fresh install can join.
struct JoinView: View {
    let invite: Account.PendingInvite

    @AppStorage(Uploader.enabledKey) private var backupOn = false
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("familyName") private var localFamilyName = ""
    @Environment(\.dismiss) private var dismiss
    @State private var preview: Account.InvitePreview?
    @State private var failure: String?
    @State private var busy = false
    @State private var joined = false

    private var account: Account { .shared }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Spacer()
                if let preview {
                    card(for: preview)
                } else if let failure {
                    message("This link doesn’t work", failure)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                Spacer()
                actions
            }
            .padding(24)
            .background { MemoryPool(center: UnitPoint(x: 0.5, y: 0.35)) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(joined ? "Done" : "Not now") { dismiss() } }
            }
            .task { await load() }
            .alert("Couldn’t join", isPresented: .constant(failure != nil && preview != nil), presenting: failure) { _ in
                Button("OK") { failure = nil }
            } message: { Text($0) }
        }
    }

    @ViewBuilder
    private func card(for p: Account.InvitePreview) -> some View {
        if joined {
            message("You’re in", p.role == "viewer"
                ? "You’ll be able to watch \(p.familyName)’s film."
                : "Add clips from \(weeksLabel(p.weeks, year: p.year)) and they’ll go to \(p.familyName)’s film. Yearfilm files each one under the week it was filmed.")
        } else if p.state != "open" {
            message("This link has \(p.state == "expired" ? "expired" : "been turned off")", "Ask \(p.invitedBy ?? "whoever sent it") for a new one.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("YOU’RE INVITED").font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(Color.glow)
                Text("Help make \(p.familyName)’s film").font(.system(.largeTitle, design: .serif))
                Text(p.role == "viewer"
                     ? "\(p.invitedBy ?? "Someone") invited you to watch it when it premieres."
                     : "\(p.invitedBy ?? "Someone") invited you to add your videos from \(weeksLabel(p.weeks, year: p.year)).")
                    .foregroundStyle(.secondary)
                if p.role != "viewer" {
                    Text("When you join, backup turns on: your clips from those weeks are uploaded to \(p.familyName)’s film, and its producers can see them. Nothing else on this iPhone is sent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 28)
        }
    }

    private func message(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(.title, design: .serif))
            Text(body).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 28)
    }

    @ViewBuilder
    private var actions: some View {
        if let preview, preview.state == "open", !joined {
            if account.isSignedIn {
                Button(busy ? "Joining…" : "Join \(preview.familyName)’s film") { Task { await join(preview) } }
                    .buttonStyle(PrimaryButton())
                    .disabled(busy)
            } else {
                SignInWithAppleButton(.continue) { request in
                    account.prepare(request)
                } onCompletion: { result in
                    Task { await signInAndJoin(result, preview) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .clipShape(Capsule())
                .disabled(busy)
            }
        }
    }

    private func load() async {
        do { preview = try await account.previewInvite(invite) } catch { failure = error.localizedDescription }
    }

    private func signInAndJoin(_ result: Result<ASAuthorization, Error>, _ preview: Account.InvitePreview) async {
        if case .failure(let error as ASAuthorizationError) = result, error.code == .canceled { return }
        do {
            try await account.signIn(result)
            await join(preview)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func join(_ preview: Account.InvitePreview) async {
        busy = true
        defer { busy = false }
        do {
            try await account.acceptInvite(invite)
            if preview.role != "viewer" {
                backupOn = true  // the consent text above said so
                await Uploader.shared.sync()
            }
            if localFamilyName.isEmpty { localFamilyName = preview.familyName }
            onboarded = true  // a contributor doesn't need the producer's onboarding
            joined = true
        } catch {
            failure = error.localizedDescription
        }
    }
}
