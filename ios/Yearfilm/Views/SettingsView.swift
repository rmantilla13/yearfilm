import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage("familyName") private var familyName = ""
    @AppStorage("remindersOn") private var remindersOn = false
    @State private var confirmDelete = false
    @State private var notificationsDenied = false
    @State private var deleteError: String?

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your film") {
                    TextField("Family name", text: $familyName)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    Toggle("Weekly reminder", isOn: Binding(
                        get: { remindersOn },
                        set: { on in Task { await setReminders(on) } }
                    ))
                } footer: {
                    Text("Sunday at 6pm, with a shot to try.")
                }

                BackupSection()

                Section {
                    Text("Your clips and voice notes stay on this iPhone unless you turn on backup. Backups go to private storage that only your family can reach.")
                    Text("If a future feature needs an outside service — including an AI service — the app will show you exactly what would be sent and to whom, and ask first.")
                    Link("Privacy policy", destination: URL(string: "https://yearfilm.com/privacy")!)
                    Link("Support", destination: URL(string: "https://yearfilm.com/support")!)
                } header: {
                    Text("Privacy")
                }

                Section {
                    Button("Delete all my data", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Removes every clip and voice note from Yearfilm on this iPhone. Videos still in your photo library aren’t touched. To remove backups too, delete your account under Backup.")
                }

                Section {
                    LabeledContent("Version", value: version)
                }
            }
            .memoryPoolBackground(intensity: 0.6)
            .navigationTitle("Settings")
            .confirmationDialog("Delete everything?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all clips and voice notes", role: .destructive, action: deleteAll)
            } message: {
                Text("This can’t be undone.")
            }
            .alert("Notifications are off for Yearfilm", isPresented: $notificationsDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("Not now", role: .cancel) {}
            }
            .alert("Couldn’t delete everything", isPresented: .constant(deleteError != nil), presenting: deleteError) { _ in
                Button("OK") { deleteError = nil }
            } message: { Text($0) }
        }
    }

    @MainActor
    private func setReminders(_ on: Bool) async {
        if on {
            let granted = await Reminders.enable()
            remindersOn = granted
            if !granted { notificationsDenied = true }
        } else {
            Reminders.disable()
            remindersOn = false
        }
    }

    private func deleteAll() {
        do {
            try context.delete(model: Clip.self)
            try context.delete(model: VoiceNote.self)
            try context.save()
            try MediaStore.deleteEverything()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
