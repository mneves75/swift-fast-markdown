import SwiftUI

/// A view modifier that applies Liquid Glass effect on iOS 26+ with material fallback for earlier versions.
///
/// On iOS 26+: Uses the native `.glassEffect(.regular)` API for authentic translucent materials.
/// On iOS 18-25: Falls back to `.ultraThinMaterial` with a subtle border overlay.
struct LiquidGlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                glassBackground
            }
    }

    @ViewBuilder
    private var glassBackground: some View {
        if #available(iOS 26, macOS 26, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .glassEffect(.regular)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                )
        }
    }
}

/// A view modifier for prominent glass surfaces (e.g., cards, callouts).
struct LiquidGlassProminentSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                prominentBackground
            }
    }

    @ViewBuilder
    private var prominentBackground: some View {
        if #available(iOS 26, macOS 26, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .glassEffect(.regular.interactive())
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12))
                )
        }
    }
}

extension View {
    /// Applies a Liquid Glass surface effect with the specified corner radius.
    ///
    /// - Parameter cornerRadius: The corner radius for the rounded rectangle background. Default is 12.
    /// - Returns: A view with the Liquid Glass surface applied.
    ///
    /// On iOS 26+, this uses the native `glassEffect(.regular)` API.
    /// On earlier versions, it falls back to `.ultraThinMaterial`.
    func liquidGlassSurface(cornerRadius: CGFloat = 12) -> some View {
        modifier(LiquidGlassSurface(cornerRadius: cornerRadius))
    }

    /// Applies a prominent Liquid Glass surface effect for elevated UI elements.
    ///
    /// - Parameter cornerRadius: The corner radius for the rounded rectangle background. Default is 12.
    /// - Returns: A view with the prominent Liquid Glass surface applied.
    func liquidGlassProminentSurface(cornerRadius: CGFloat = 12) -> some View {
        modifier(LiquidGlassProminentSurface(cornerRadius: cornerRadius))
    }
}
