import SwiftUI
import AppKit
import LoomCore

public struct MenuBarRootView: View {
    @Bindable var store: SessionStore

    public init(store: SessionStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            MenuBarHeaderView(store: store)

            Divider()

            // Sessions list
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.providerSnapshots.isEmpty {
                        Text("No providers registered")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(store.providerSnapshots) { snapshot in
                            ProviderSectionView(snapshot: snapshot)
                            if snapshot.id != store.providerSnapshots.last?.id {
                                Divider()
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 380)

            Divider()

            // Footer
            MenuBarFooterView(store: store)
        }
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            // Initial session discovery on launch
            await store.refresh()
        }
    }
}

private struct MenuBarHeaderView: View {
    let store: SessionStore

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            LoomIconView(size: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Loom")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("MOCK")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.secondary)
                }
                Text("Local AI Control Surface")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Manual Refresh action
            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .accessibilityLabel("Refresh sessions")
            .help("Refresh agent sessions")

            // Quit action
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quit Loom")
            .help("Quit Loom")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct MenuBarFooterView: View {
    let store: SessionStore

    var body: some View {
        HStack(alignment: .center) {
            if store.isRefreshing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Refreshing...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let lastRefreshed = store.lastRefreshedAt {
                Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Ready")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }
}
