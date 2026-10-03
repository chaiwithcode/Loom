import SwiftUI
import LoomCore

public struct ProviderSectionView: View {
    public let snapshot: ProviderSnapshot

    public init(snapshot: ProviderSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Provider header
            HStack(alignment: .center, spacing: 6) {
                Text(snapshot.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if snapshot.isRefreshing && snapshot.availability != .unknown {
                    ProgressView()
                        .controlSize(.mini)
                } else if snapshot.availability.isAvailable && snapshot.errorMessage == nil {
                    Text("\(snapshot.sessions.count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 4)

            // Provider content
            if snapshot.availability == .unknown {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Checking provider...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if !snapshot.availability.isAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(snapshot.availability.unavailabilityReason ?? "Provider unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            } else if let error = snapshot.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            } else if snapshot.sessions.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .strokeBorder(Color.secondary, lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text("Idle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(snapshot.sessions) { session in
                        SessionRowView(session: session)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(snapshot.displayName) section")
    }
}
