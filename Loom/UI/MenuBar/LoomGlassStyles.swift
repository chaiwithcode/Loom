//
//  LoomGlassStyles.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit

private struct LoomGlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var loomGlassEnabled: Bool {
        get { self[LoomGlassEnabledKey.self] }
        set { self[LoomGlassEnabledKey.self] = newValue }
    }
}

// MARK: - Liquid Glass Container

/// A container that coordinates Liquid Glass refraction on macOS 26+,
/// while gracefully passing through on earlier OS versions or when Reduce Transparency is active.
public struct LoomGlassContainer<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 0) {
                content
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Glass Surface Modifiers

/// Applies system Liquid Glass on macOS 26+ and adaptive materials on macOS 14/15.
/// Respects accessibility Reduce Transparency by falling back to solid system backgrounds.
public struct LoomGlassSurface<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S
    let tintColor: Color?

    public init(shape: S, tintColor: Color? = nil) {
        self.shape = shape
        self.tintColor = tintColor
    }

    public func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            let glass: Glass = tintColor.map { Glass.regular.tint($0) } ?? Glass.regular
            content.glassEffect(glass, in: shape)
        } else {
            fallback(content: content)
        }
        #else
        fallback(content: content)
        #endif
    }

    @ViewBuilder
    private func fallback(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

/// Applies interactive Liquid Glass on macOS 26+ (with bounce, refraction, and activation),
/// or ultra-thin material on macOS 14/15.
public struct LoomInteractiveGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    let tintColor: Color?

    public init(shape: S, tintColor: Color? = nil) {
        self.shape = shape
        self.tintColor = tintColor
    }

    public func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            let glass: Glass = tintColor.map { Glass.regular.interactive().tint($0) } ?? Glass.regular.interactive()
            content.glassEffect(glass, in: shape)
        } else {
            fallback(content: content)
        }
        #else
        fallback(content: content)
        #endif
    }

    @ViewBuilder
    private func fallback(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

// MARK: - Selected Provider Surface

/// The selected provider is a real system glass control on macOS 26.
/// Earlier systems retain a restrained material, and accessibility settings use solid fills.
public struct LoomFloatingLensModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let isSelected: Bool
    let isHovered: Bool
    let cornerRadius: CGFloat
    let tint: Color?

    public init(
        isSelected: Bool,
        isHovered: Bool = false,
        cornerRadius: CGFloat = 8,
        tint: Color? = nil
    ) {
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.cornerRadius = cornerRadius
        self.tint = tint
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if !isSelected {
                content.background(isHovered ? Color.primary.opacity(0.05) : .clear, in: shape)
            } else if reduceTransparency {
                content.background(Color(nsColor: .controlBackgroundColor), in: shape)
            } else {
                selectedSurface(content: content, shape: shape)
            }
        }
        .overlay {
            if isSelected && contrast == .increased {
                shape.strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func selectedSurface(content: Content, shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive()
            content.glassEffect(glass, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
        #else
        content.background(.regularMaterial, in: shape)
        #endif
    }
}

// MARK: - Compact Button Surface

/// Native interactive glass for compact actions, with adaptive older-system and accessibility fills.
public struct LoomGlassButtonModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let isHovered: Bool
    let cornerRadius: CGFloat

    public init(isHovered: Bool = false, cornerRadius: CGFloat = 6) {
        self.isHovered = isHovered
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if reduceTransparency {
                content.background(Color(nsColor: .controlBackgroundColor), in: shape)
            } else {
                glassOrMaterial(content: content, shape: shape)
            }
        }
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func glassOrMaterial(content: Content, shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
        #else
        content.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

// MARK: - Row Surface (Native List Row Presentation)

/// Clean native list row styling adhering to macOS Tahoe / Liquid Glass guidelines.
/// Replaces heavy opaque card containers with lightweight rows, subtle hover states,
/// and semantic accentuation for actionable sessions.
public struct LoomRowModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let isAttention: Bool
    let isSelected: Bool
    let isHovered: Bool

    public init(isAttention: Bool = false, isSelected: Bool = false, isHovered: Bool = false) {
        self.isAttention = isAttention
        self.isSelected = isSelected
        self.isHovered = isHovered
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        content
            .background {
                if isAttention {
                    shape.fill(Color.orange.opacity(0.07))
                } else if isSelected {
                    shape.fill(Color.primary.opacity(isHovered ? 0.08 : 0.06))
                } else if isHovered {
                    shape.fill(Color.primary.opacity(0.035))
                }
            }
            .overlay {
                if isAttention {
                    shape.strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                } else if isHovered && !isSelected {
                    shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                } else if contrast == .increased {
                    shape.strokeBorder(Color.primary.opacity(0.20), lineWidth: 0.5)
                }
            }
    }
}

// MARK: - Card Surface (Content Presentations)

/// Consistent card container adhering to Apple HIG:
/// Avoids nested blur layers and text-on-text translucency by using standard content materials
/// with high-contrast accessibility support and semantic alert borders.
public struct LoomCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let cornerRadius: CGFloat
    let accentBorderColor: Color?
    let isHighlighted: Bool

    public init(cornerRadius: CGFloat = 8, accentBorderColor: Color? = nil, isHighlighted: Bool = false) {
        self.cornerRadius = cornerRadius
        self.accentBorderColor = accentBorderColor
        self.isHighlighted = isHighlighted
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let border = accentBorderColor ?? (contrast == .increased ? Color.primary.opacity(0.35) : Color.primary.opacity(0.06))
        let lineWidth: CGFloat = accentBorderColor != nil ? 1.0 : 0.5

        content
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                } else {
                    shape.fill(Color.primary.opacity(isHighlighted ? 0.05 : 0.025))
                }
            }
            .overlay {
                shape.strokeBorder(border, lineWidth: lineWidth)
            }
    }
}

// MARK: - View Extensions

public extension View {
    /// Wraps content with a Liquid Glass surface on macOS 26+ or standard material fallback.
    func loomGlassSurface<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(LoomGlassSurface(shape: shape, tintColor: tint))
    }

    /// Wraps interactive elements with interactive Liquid Glass on macOS 26+.
    func loomInteractiveGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(LoomInteractiveGlass(shape: shape, tintColor: tint))
    }

    /// Applies system glass to a selected provider with adaptive fallbacks.
    func loomFloatingLens(
        isSelected: Bool,
        isHovered: Bool = false,
        cornerRadius: CGFloat = 8,
        tint: Color? = nil
    ) -> some View {
        modifier(
            LoomFloatingLensModifier(
                isSelected: isSelected,
                isHovered: isHovered,
                cornerRadius: cornerRadius,
                tint: tint
            )
        )
    }

    /// Applies native glass to a compact action with adaptive fallbacks.
    func loomGlassButton(
        isHovered: Bool = false,
        cornerRadius: CGFloat = 6
    ) -> some View {
        modifier(
            LoomGlassButtonModifier(
                isHovered: isHovered,
                cornerRadius: cornerRadius
            )
        )
    }

    /// Applies a lightweight native list row styling with subtle hover and attention accents.
    func loomRow(isAttention: Bool = false, isSelected: Bool = false, isHovered: Bool = false) -> some View {
        modifier(LoomRowModifier(isAttention: isAttention, isSelected: isSelected, isHovered: isHovered))
    }

    /// Applies a standard content card styling avoiding nested blur layers,
    /// with optional semantic alert border.
    func loomCard(cornerRadius: CGFloat = 8, accentBorderColor: Color? = nil, isHighlighted: Bool = false) -> some View {
        modifier(LoomCardModifier(cornerRadius: cornerRadius, accentBorderColor: accentBorderColor, isHighlighted: isHighlighted))
    }
}
