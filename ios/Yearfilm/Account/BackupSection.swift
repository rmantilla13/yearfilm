import AuthenticationServices
import SwiftUI

/// Settings → Backup. Signing in uploads nothing; turning on backup is the explicit "yes",
/// and the footer says exactly what that sends and to whom.
struct BackupSection: View {
    @AppStorage(Uploader.enabledKey) private var backupOn = false
    @AppStorage("familyName") private var familyName = ""
    @State private var busy = false
    @State private var failure: String?

    private var account: Account { .shared }
    private var uploader: Uploader { .shared }

    var body: some View {
        Section {
            if account.isSignedIn {
                NavigationLink {
                    AccountView()
                } label: {
                    LabeledContent("Account", value: account.displayName ?? account.family?.name ?? "")
                }
                Toggle("Back up to Yearfilm", isOn: Binding(get: { backupOn }, set: { on in Task { await setBackup(on) } }))
                    .disabled(busy || account.family?.role == "viewer")
                if backupOn {
                    LabeledContent("Waiting to back up", value: uploader.pending == 0 ? "Nothing" : "\(uploader.pending)")
                    if uploader.tooLarge > 0 {
                        Text("\(uploader.tooLarge) long \(uploader.tooLarge == 1 ? "clip is" : "clips are") over 500 MB and will back up in a later version.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error = uploader.lastError {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Keep your year safe if something happens to this iPhone, and make the film together with your family.")
                SignInWithAppleButton(.signIn) { request in
                    account.prepare(request)
                } onCompletion: { result in
                    Task { await signIn(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 48)
                .disabled(busy)
            }
        } header: {
            Text("Backup")
        } footer: {
            Text(footer)
        }
        .alert("Something went wrong", isPresented: .constant(failure != nil), presenting: failure) { _ in
            Button("OK") { failure = nil }
        } message: { Text($0) }
    }

    private var footer: String {
        guard account.isSignedIn else { return "Signing in uploads nothing by itself. You choose when backup starts." }
        guard let family = account.family else {
            return backupOn ? "" : "Turning on backup starts your family’s film on Yearfilm, with you as its producer."
        }
        if family.role == "viewer" { return "You’re watching \(family.name)’s film. Viewers don’t send clips." }
        guard backupOn else { return "Nothing is uploaded until you turn on backup." }
        if family.isProducer {
            return "Every clip and voice note, including the ones already on this iPhone, is uploaded to private storage only your family can reach. Uploads continue in the background."
        }
        return "Your clips from \(weeksLabel(family.weeks, year: family.year)) go to \(family.name)’s film, and its producers can see them. Uploads continue in the background."
    }

    private func setBackup(_ on: Bool) async {
        guard on else { backupOn = false; return }
        busy = true
        defer { busy = false }
        do {
            if account.family == nil { try await account.startFamily(named: familyName) }
            backupOn = true
            await uploader.sync()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func signIn(_ result: Result<ASAuthorization, Error>) async {
        if case .failure(let error as ASAuthorizationError) = result, error.code == .canceled { return }
        busy = true
        defer { busy = false }
        do {
            try await account.signIn(result)
        } catch {
            failure = error.localizedDescription
        }
    }
}
