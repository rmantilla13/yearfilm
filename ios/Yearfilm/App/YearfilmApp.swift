import SwiftData
import SwiftUI

@main
struct YearfilmApp: App {
    @AppStorage("onboarded") private var onboarded = false

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
        .modelContainer(for: [Clip.self, VoiceNote.self])
    }
}

struct RootView: View {
    @AppStorage("remindersOn") private var remindersOn = false

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
        }
    }
}

extension Color {
    static let ember = Color("AccentColor")
    static let ground = Color("Ground")
}
