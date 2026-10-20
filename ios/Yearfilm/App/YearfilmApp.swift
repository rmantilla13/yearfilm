import SwiftData
import SwiftUI

@main
struct YearfilmApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @AppStorage("onboarded") private var onboarded = false
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Clip.self, VoiceNote.self)
        } catch {
            fatalError("Couldn’t open the library: \(error)")
        }
        Uploader.shared.container = container
        Uploader.shared.reconnect()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded {
                    RootView()
                } else {
                    OnboardingView { onboarded = true }
                }
            }
            .preferredColorScheme(.dark)
            // Invite links: yearfilm://join/<token>, or the web link once universal links are set up.
            .onOpenURL { url in Account.shared.pendingInvite = Account.PendingInvite(url: url) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { Account.shared.pendingInvite = Account.PendingInvite(url: url) }
            }
            .sheet(item: Binding(get: { Account.shared.pendingInvite }, set: { Account.shared.pendingInvite = $0 })) {
                JoinView(invite: $0)
                    .preferredColorScheme(.dark)
            }
        }
        .modelContainer(container)
    }
}

/// Only for background uploads: the system relaunches the app to report finished ones.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == Uploader.sessionIdentifier else { return completionHandler() }
        MainActor.assumeIsolated {
            Uploader.shared.backgroundEventsDone = completionHandler
            Uploader.shared.reconnect()
        }
    }
}

struct RootView: View {
    @AppStorage("remindersOn") private var remindersOn = false
    @Environment(\.scenePhase) private var scenePhase
    @Query private var clips: [Clip]
    @Query private var notes: [VoiceNote]

    var body: some View {
        TabView {
            ThisWeekView()
                .tabItem { Label("This week", systemImage: "video.badge.plus") }
            YearView()
                .tabItem { Label("Year", systemImage: "square.grid.3x3") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task {
            // Keep the next few weekly prompts queued; they are one-off notifications.
            if remindersOn { await Reminders.schedule() }
            await Account.shared.restore()
            await Uploader.shared.sync()
        }
        // Back up what was just added, and whatever was waiting when the app comes back.
        .onChange(of: clips.count + notes.count) { Task { await Uploader.shared.sync() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await Uploader.shared.sync() } }
        }
    }
}

extension Color {
    static let ground = Color("Ground")
}
