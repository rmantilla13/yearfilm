import SwiftUI

/// The animated backdrop: memories drifting in a pool of light (MemoryPool.metal).
/// Holds still with Reduce Motion on, and stops drawing while off screen.
struct MemoryPool: View {
    var intensity: Double = 1
    var center: UnitPoint = .center
    /// Where the water is being stirred, as a fraction of the view, and when it last was.
    /// The stir fades out over a second or two after `stirredAt`.
    var stir: Stir? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var visible = false
    private var shader: PoolShader { .shared }

    var body: some View {
        ZStack {
            // A still pool until the shader is compiled, so the first frame never waits on Metal.
            PoolStill(center: center, intensity: intensity)
            if shader.ready {
                animated.transition(.opacity.animation(.easeIn(duration: 0.5)))
            }
        }
        .ignoresSafeArea()
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityHidden(true)
    }

    private var animated: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !visible)) { context in
            let time = context.date.timeIntervalSince(start)
            let strength = reduceMotion ? 0 : stir?.strength(at: context.date) ?? 0
            let point = stir?.point ?? center
            GeometryReader { geo in
                Rectangle()
                    .colorEffect(ShaderLibrary.memoryPool(
                        .float2(geo.size), .float(time), .float(intensity), .float2(center.x, center.y),
                        .float2(point.x, point.y), .float(strength)
                    ))
            }
        }
    }
}

/// Compiles the pool shader off the main thread at launch. On iOS 17, where SwiftUI can't
/// precompile, the shader compiles on first use as before.
@MainActor
@Observable
final class PoolShader {
    static let shared = PoolShader()
    private(set) var ready = false

    func warmUp() {
        guard !ready else { return }
        if #available(iOS 18, *) {
            let shader = ShaderLibrary.memoryPool(
                .float2(CGSize(width: 1, height: 1)), .float(0), .float(1), .float2(0.5, 0.5), .float2(0.5, 0.5), .float(0)
            )
            Task.detached(priority: .userInitiated) {
                try? await shader.compile(as: .colorEffect)
                await MainActor.run { PoolShader.shared.ready = true }
            }
        } else {
            ready = true
        }
    }
}

/// The pool's colours without the motion: dark water with a soft ring of light.
private struct PoolStill: View {
    let center: UnitPoint
    let intensity: Double

    var body: some View {
        GeometryReader { geo in
            RadialGradient(
                colors: [
                    Color(red: 0.016, green: 0.031, blue: 0.059),
                    Color(red: 0.06, green: 0.24, blue: 0.42).opacity(0.55 * intensity),
                    Color(red: 0.016, green: 0.031, blue: 0.059),
                ],
                center: center,
                startRadius: geo.size.width * 0.08,
                endRadius: geo.size.width * 0.75
            )
        }
        .background(Color(red: 0.016, green: 0.031, blue: 0.059))
    }
}

/// A disturbance in the pool: a finger, or a memory sinking into it.
struct Stir: Equatable {
    var point: UnitPoint
    var at: Date
    /// Held at full strength while a finger is down.
    var holding = false

    func strength(at now: Date) -> Double {
        if holding { return 1 }
        let elapsed = now.timeIntervalSince(at)
        return elapsed < 0 ? 0 : exp(-elapsed * 1.6)
    }
}

extension View {
    /// Puts the memory pool behind a screen. Lists and forms drop their own background so it shows through.
    func memoryPoolBackground(intensity: Double = 0.9, stir: Stir? = nil) -> some View {
        scrollContentBackground(.hidden)
            .background { MemoryPool(intensity: intensity, center: UnitPoint(x: 0.5, y: 0.6), stir: stir) }
    }
}
