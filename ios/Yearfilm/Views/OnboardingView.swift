import SwiftUI

struct OnboardingView: View {
    var finish: () -> Void

    @AppStorage("familyName") private var familyName = ""
    @AppStorage("remindersOn") private var remindersOn = false
    @State private var page = 0
    @FocusState private var nameFocused: Bool
    @State private var stir: Stir?
    @State private var screen: CGSize = .zero

    var body: some View {
        TabView(selection: $page) {
            intro.tag(0)
            name.tag(1)
            reminders.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background {
            MemoryPool(center: UnitPoint(x: 0.5, y: 0.42), stir: stir)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
        }
        // Touch the water and the wisps swirl around your finger. Simultaneous, so paging and
        // the buttons work as usual.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { stir = Stir(point: unit($0.location), at: .now, holding: true) }
                .onEnded { stir = Stir(point: unit($0.location), at: .now) }
        )
    }

    private func unit(_ location: CGPoint) -> UnitPoint {
        guard screen.width > 0, screen.height > 0 else { return .center }
        return UnitPoint(x: location.x / screen.width, y: location.y / screen.height)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image("Mark")
                        .resizable()
                        .frame(width: 34, height: 34)
                        .accessibilityHidden(true)
                    (Text("year") + Text("film").foregroundStyle(Color.glow))
                        .font(.system(.title3, design: .serif))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Yearfilm")
                Text("Your family’s year,\nmade into a film.")
                    .font(.system(.largeTitle, design: .serif))
                Text("Film a little every week. In December, sit down together and watch the movie of your year — cut, scored, and narrated in your own words.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .onboardingCard()
            Text("Touch the water.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Spacer()
            Button("Start") { withAnimation { page = 1 } }
                .buttonStyle(PrimaryButton())
        }
        .padding(24)
        .padding(.bottom, 32)
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
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
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .onSubmit { withAnimation { page = 2 } }
            }
            .onboardingCard()
            Spacer()
            Button("Next") { withAnimation { page = 2 } }
                .buttonStyle(PrimaryButton())
        }
        .padding(24)
        .padding(.bottom, 32)
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Text("A nudge each week")
                    .font(.system(.largeTitle, design: .serif))
                Text("Sunday evening, with one shot to try — the first snow, a reaction, one wide shot of where you are. You can turn it off anytime in Settings.")
                    .foregroundStyle(.secondary)
            }
            .onboardingCard()
            Spacer()
            Button("Remind me weekly") {
                Task {
                    remindersOn = await Reminders.enable()
                    finish()
                }
            }
            .buttonStyle(PrimaryButton())
            Button("Not now", action: finish)
                .buttonStyle(SecondaryButton())
        }
        .padding(24)
        .padding(.bottom, 32)
    }
}

private extension View {
    func onboardingCard() -> some View {
        padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 28)
    }
}
