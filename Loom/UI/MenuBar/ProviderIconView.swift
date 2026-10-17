//
//  ProviderIconView.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit
import LoomCore

public struct ProviderIconView: View {
    public let providerID: ProviderID
    public var size: CGFloat

    public init(providerID: ProviderID, size: CGFloat = 14) {
        self.providerID = providerID
        self.size = size
    }

    public var body: some View {
        let presentation = ProviderPresentation.presentation(for: providerID)
        if let assetName = presentation.iconAssetName {
            if let nsImage = ProviderIconImage.image(named: assetName, template: presentation.iconRenderingMode == .template) {
                if presentation.iconRenderingMode == .original {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .accessibilityHidden(true)
                } else {
                    Image(nsImage: nsImage)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            } else {
                // Known provider whose asset could not be loaded:
                // Must NOT silently collapse to EmptyView.
                knownProviderMissingAssetView(presentation: presentation)
            }
        } else {
            // Unknown/future provider fallback
            genericFallbackView
        }
    }

    @ViewBuilder
    private func knownProviderMissingAssetView(presentation: ProviderPresentation) -> some View {
        #if DEBUG
        let _ = {
            print("⚠️ [ProviderIconView] Missing asset '\(presentation.iconAssetName ?? "")' for known provider '\(presentation.providerID.rawValue)'")
        }()
        #endif
        Image(systemName: fallbackSymbol(for: providerID))
            .font(.system(size: size * 0.85))
            .frame(width: size, height: size)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var genericFallbackView: some View {
        Image(systemName: "cpu")
            .font(.system(size: size * 0.85))
            .frame(width: size, height: size)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private func fallbackSymbol(for id: ProviderID) -> String {
        switch id {
        case .codex: return "terminal"
        case .claude: return "bubble.left.and.text.bubble.right"
        case .antigravity: return "wand.and.stars"
        default: return "cpu"
        }
    }
}
