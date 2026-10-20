//
//  LoomGlassStyles.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit

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
        #if compiler(>=6.0)
        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer {
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
        #if compiler(>=6.0)
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
        #if compiler(>=6.0)
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

// MARK: - Row Surface (Native List Row Presentation)

/// Clean native list row styling adhering to macOS Tahoe / Liquid Glass guidelines.
/// Replaces heavy opaque card containers with lightweight rows, subtle hover states,
/// and semantic accentuation for actionable sessions.
public struct LoomRowModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let isAttention: Bool
    let isSelected: Bool

    public init(isAttention: Bool = false, isSelected: Bool = false) {
        self.isAttention = isAttention
        self.isSelected = isSelected
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        content
            .background {
                if isAttention {
                    shape.fill(Color.orange.opacity(0.07))
                } else if isSelected {
                    shape.fill(Color.primary.opacity(0.06))
                }
            }
            .overlay {
                if isAttention {
                    shape.strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
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

    /// Applies a lightweight native list row styling with subtle hover and attention accents.
    func loomRow(isAttention: Bool = false, isSelected: Bool = false) -> some View {
        modifier(LoomRowModifier(isAttention: isAttention, isSelected: isSelected))
    }

    /// Applies a standard content card styling avoiding nested blur layers,
    /// with optional semantic alert border.
    func loomCard(cornerRadius: CGFloat = 8, accentBorderColor: Color? = nil, isHighlighted: Bool = false) -> some View {
        modifier(LoomCardModifier(cornerRadius: cornerRadius, accentBorderColor: accentBorderColor, isHighlighted: isHighlighted))
    }
}
