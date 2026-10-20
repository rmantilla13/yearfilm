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

    var body: some View {
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
        .ignoresSafeArea()
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityHidden(true)
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
