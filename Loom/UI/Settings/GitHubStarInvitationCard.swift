//
//  GitHubStarInvitationCard.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit

public struct GitHubStarInvitationCard: View {
    @Environment(\.colorSchemeContrast) private var contrast
    public let onDismiss: () -> Void
    public let onStar: () -> Void

    public init(
        onDismiss: @escaping () -> Void,
        onStar: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
        self.onStar = onStar
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)

                Text("Enjoying Loom?")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)
            }

            Text("If Loom makes managing your coding agents easier, consider giving it a star on GitHub. It helps others discover the project.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Spacer(minLength: 0)

                Button("Not now", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .accessibilityIdentifier("button-star-invitation-dismiss")
                    .accessibilityLabel("Not now, dismiss star invitation")

                Button(action: onStar) {
                    HStack(spacing: 5) {
                        Image(systemName: "star")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Star on GitHub")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("button-star-invitation-star")
                .accessibilityLabel("Star Loom on GitHub")
            }
            .padding(.top, 2)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomGlassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card-github-star-invitation")
    }
}
