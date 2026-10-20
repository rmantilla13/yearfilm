import SwiftUI

struct OnboardingView: View {
    var finish: () -> Void

    @AppStorage("familyName") private var familyName = ""
    @AppStorage("remindersOn") private var remindersOn = false
    @State private var page = 0
    @FocusState private var nameFocused: Bool

    var body: some View {
        TabView(selection: $page) {
            intro.tag(0)
            name.tag(1)
            reminders.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Color.ground.ignoresSafeArea())
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Your family’s year,\nmade into a film.")
                .font(.system(.largeTitle, design: .serif))
            Text("Film a little every week. In December, sit down together and watch the movie of your year — cut, scored, and narrated in your own words.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Start") { withAnimation { page = 1 } }
                .buttonStyle(PrimaryButton())
        }
        .padding(28)
        .padding(.bottom, 32)
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Whose film is it?")
                .font(.system(.largeTitle, design: .serif))
            Text("It goes on the title card.")
                .foregroundStyle(.secondary)
            TextField("The Garcias", text: $familyName)
                .font(.title2)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($nameFocused)
                .padding()
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .onSubmit { withAnimation { page = 2 } }
            Spacer()
            Button("Next") { withAnimation { page = 2 } }
                .buttonStyle(PrimaryButton())
        }
        .padding(28)
        .padding(.bottom, 32)
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("A nudge each week")
                .font(.system(.largeTitle, design: .serif))
            Text("Sunday evening, with one shot to try — the first snow, a reaction, one wide shot of where you are. You can turn it off anytime in Settings.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Remind me weekly") {
                Task {
                    remindersOn = await Reminders.enable()
                    finish()
                }
            }
            .buttonStyle(PrimaryButton())
            Button("Not now", action: finish)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .padding(28)
        .padding(.bottom, 32)
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.ground)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.ember.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}
