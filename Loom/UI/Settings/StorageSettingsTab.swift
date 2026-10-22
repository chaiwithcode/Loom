//
//  StorageSettingsTab.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import SwiftUI
import AppKit
import LoomCore

struct StorageSettingsTab: View {
    let hidePaths: Bool
    @State private var measurements: [ProviderID: [StorageMeasurement]] = [:]
    @State private var scanning = false
    @State private var scannedAt: Date?
    @State private var scanID = UUID()
    private let providers = ProviderStorageLocations.local()

    var body: some View {
        SettingsForm {
            SettingsSection {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local data on disk").font(.headline)
                        Text("Known agent data and cache folders. App binaries and project files are excluded. Nothing is deleted.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if scanning { ProgressView().controlSize(.small) }
                    Button("Rescan") { scanID = UUID() }.disabled(scanning)
                }
                if let scannedAt {
                    Text("Measured \(scannedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(providers) { provider in
                SettingsSection(provider.name) {
                    if let results = measurements[provider.id] {
                        let bytes = results.reduce(Int64(0)) { $0 + $1.bytes }
                        let complete = results.allSatisfy { $0.status == .complete || $0.status == .missing }
                        let measured = results.contains { $0.status == .complete || $0.fileCount > 0 }
                        LabeledContent(complete ? "Known folders" : "Measured so far") {
                            Text(measured ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : "Unavailable")
                                .monospacedDigit()
                        }
                        ForEach(results) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(item.location.label)
                                    Spacer()
                                    Text(sizeLabel(item)).foregroundStyle(.secondary)
                                    if item.status == .complete || item.status == .partial {
                                        Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.location.url.path) } label: {
                                            Image(systemName: "folder")
                                        }.buttonStyle(.borderless).help("Reveal folder in Finder")
                                    }
                                }
                                if !hidePaths {
                                    Text(item.location.url.path).font(.caption2).foregroundStyle(.secondary)
                                        .textSelection(.enabled).lineLimit(2)
                                }
                            }
                        }
                        if !complete {
                            Text("Some folders could not be fully measured. Totals are partial; symbolic links are skipped.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(scanning ? "Measuring…" : "Not measured").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: scanID) { await scan() }
    }

    private func sizeLabel(_ item: StorageMeasurement) -> String {
        switch item.status {
        case .missing: return "Not found"
        case .inaccessible: return "Access unavailable"
        case .symbolicLink: return "Link skipped"
        case .partial: return "At least " + ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)
        case .complete: return ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)
        }
    }

    @MainActor private func scan() async {
        scanning = true
        defer { scanning = false }
        for provider in providers {
            let locations = provider.locations
            let worker = Task.detached(priority: .utility) { try StorageScanner().measure(locations) }
            let result = await withTaskCancellationHandler {
                try? await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            if let result { measurements[provider.id] = result }
        }
        scannedAt = Date()
    }
}
