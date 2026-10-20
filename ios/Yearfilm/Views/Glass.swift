import SwiftUI

// Liquid Glass over the memory pool, so text and buttons stay readable while the
// wisps move behind them. iOS 26 gets real glass; earlier versions a frosted material.

extension View {
    /// A glass panel behind a block of text.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.tint(tint), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .background(tint ?? .clear, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// A glass capsule for a button; `tint` colors it for the primary action.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.tint(tint).interactive(), in: Capsule())
        } else {
            background(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.ultraThinMaterial), in: Capsule())
        }
    }
}

extension Color {
    /// The accent: the pale cyan light of the memory pool (the AccentColor asset).
    static let glow = Color("AccentColor")
}

extension View {
    /// A soft bloom of pool light around a shape, as if it were lit from inside.
    func softGlow(radius: CGFloat = 14, opacity: Double = 0.55) -> some View {
        shadow(color: Color.glow.opacity(opacity), radius: radius)
            .shadow(color: Color.glow.opacity(opacity * 0.4), radius: radius * 2.5)
    }
}

/// The main call to action: glowing glass in the pool's light.
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.ground)
            .frame(maxWidth: .infinity, minHeight: 54)
            .glassCapsule(tint: Color.glow.opacity(configuration.isPressed ? 0.7 : 0.9))
            .softGlow(opacity: configuration.isPressed ? 0.8 : 0.5)
    }
}

/// The quieter choice next to a PrimaryButton: clear glass.
struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .glassCapsule()
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
