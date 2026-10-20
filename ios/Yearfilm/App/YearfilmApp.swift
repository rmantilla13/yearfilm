import CloudKit
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
        // Handed over, not started: neither touches iCloud until backup is on or a share is accepted.
        CloudBackup.shared.container = container
        FamilyShare.shared.container = container
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
        }
        .modelContainer(container)
    }
}

/// Registers for CloudKit pushes and sets up the scene delegate that receives family invites.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Accepting a family invite arrives here: on a running app, or as the app launches from the link.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in await FamilyShare.shared.accept(metadata) }
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { @MainActor in await FamilyShare.shared.accept(metadata) }
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
            CloudBackup.shared.resume()
            await syncCloud()
        }
        // Back up and share what was just added, and whatever was waiting when the app comes back.
        .onChange(of: clips.count + notes.count) { Task { await syncCloud() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await syncCloud() } }
        }
    }

    private func syncCloud() async {
        await CloudBackup.shared.sync()
        await FamilyShare.shared.send()
    }
}

extension Color {
    static let ground = Color("Ground")
}
