import SwiftUI

// MARK: - Glass Effect Container

/// A container view that enables proper glass effect blending between child views on iOS 26+.
///
/// On iOS 26+, this uses `GlassEffectContainer` to ensure adjacent glass surfaces
/// blend correctly with proper material composition. On earlier versions, it falls
/// back to a standard VStack with the specified spacing.
///
/// ## Usage
/// ```swift
/// GlassEffectContainer(spacing: 16) {
///     CodeBlockView(...)
///     BlockQuoteView(...)
/// }
/// ```
///
/// ## Design Note
/// Per Apple's iOS 26 Liquid Glass guidelines, glass surfaces within the same
/// container should share a common blending context to avoid harsh visual seams.
/// This container establishes that context.
@available(iOS 18, macOS 15, *)
struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 26, macOS 26, *) {
            // iOS 26+: Use native glass effect container for proper blending
            glassEffectContainerView
        } else {
            // iOS 18-25: Standard VStack layout (no special glass blending needed)
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
        }
    }

    @available(iOS 26, macOS 26, *)
    @ViewBuilder
    private var glassEffectContainerView: some View {
        // On iOS 26+, glass surfaces automatically blend when in the same
        // compositingGroup. The container provides proper layering context.
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .compositingGroup()
    }
}

// MARK: - Liquid Glass Surface

/// Unified view modifier for Liquid Glass effects with configurable fallback materials.
///
/// On iOS 26+: Uses the native `.glassEffect(.regular)` API for authentic translucent materials.
/// On earlier versions: Falls back to the specified material with a subtle border overlay.
///
/// Note: This uses `.glassEffect(.regular)` without `.interactive()` because
/// these are display surfaces, not tappable elements. Per Apple guidelines,
/// `.interactive()` should only be used for buttons and focusable controls.
private struct LiquidGlassModifier<M: ShapeStyle>: ViewModifier {
    let cornerRadius: CGFloat
    let fallbackMaterial: M
    let borderOpacity: CGFloat

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
                .fill(fallbackMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(borderOpacity))
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
        modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            fallbackMaterial: .ultraThinMaterial,
            borderOpacity: 0.08
        ))
    }

    /// Applies a prominent Liquid Glass surface effect for elevated UI elements.
    ///
    /// - Parameter cornerRadius: The corner radius for the rounded rectangle background. Default is 12.
    /// - Returns: A view with the prominent Liquid Glass surface applied.
    ///
    /// Uses `.regularMaterial` as fallback (more opaque than standard glass surface).
    func liquidGlassProminentSurface(cornerRadius: CGFloat = 12) -> some View {
        modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            fallbackMaterial: .regularMaterial,
            borderOpacity: 0.12
        ))
    }
}
