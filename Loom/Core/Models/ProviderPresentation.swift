//
//  ProviderPresentation.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation
import AppKit

public enum ProviderIconRenderingMode: String, Sendable, Equatable {
    case template
    case original
}

public struct ProviderPresentation: Sendable, Equatable, Identifiable {
    public var id: ProviderID { providerID }
    public let providerID: ProviderID
    public let displayName: String
    public let iconAssetName: String?
    public let iconRenderingMode: ProviderIconRenderingMode

    public init(
        providerID: ProviderID,
        displayName: String,
        iconAssetName: String? = nil,
        iconRenderingMode: ProviderIconRenderingMode = .template
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.iconAssetName = iconAssetName
        self.iconRenderingMode = iconRenderingMode
    }

    public static func presentation(for id: ProviderID) -> ProviderPresentation {
        let normalized = id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "codex":
            return ProviderPresentation(
                providerID: .codex,
                displayName: "Codex",
                iconAssetName: "provider-codex",
                iconRenderingMode: .original
            )
        case "claude", "claude-code", "claudecode":
            return ProviderPresentation(
                providerID: .claude,
                displayName: "Claude Code",
                iconAssetName: "provider-claude",
                iconRenderingMode: .template
            )
        case "antigravity", "gemini-antigravity", "agy":
            return ProviderPresentation(
                providerID: .antigravity,
                displayName: "Antigravity",
                iconAssetName: "provider-antigravity",
                iconRenderingMode: .template
            )
        default:
            return ProviderPresentation(
                providerID: id,
                displayName: id.displayName,
                iconAssetName: nil,
                iconRenderingMode: .template
            )
        }
    }
}

/// Robust resource loader for provider brand icons across app bundles, frameworks, and test harnesses.
public enum ProviderIconImage {
    private static var memoryCache: [String: NSImage] = [:]

    public static func image(named name: String, template: Bool = false) -> NSImage? {
        let cacheKey = "\(name):\(template)"
        if let cached = memoryCache[cacheKey] {
            return cached
        }

        // 1. Direct AppKit named image lookup
        if let image = NSImage(named: NSImage.Name(name)) {
            if template { image.isTemplate = true }
            memoryCache[cacheKey] = image
            return image
        }

        // 2. Resolve URL through multiple search candidates
        if let url = resolveResourceURL(named: name) {
            if let image = NSImage(contentsOf: url), image.isValid, image.size.width > 0, image.size.height > 0 {
                if template { image.isTemplate = true }
                memoryCache[cacheKey] = image
                return image
            }
        }

        return nil
    }

    public static func resolveResourceURL(named name: String) -> URL? {
        let fm = FileManager.default
        let exts = ["png", "pdf"]

        // A. Check Bundle.main
        for ext in exts {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }

        // B. Check Bundle.main resourceURL
        if let resourceURL = Bundle.main.resourceURL {
            for ext in exts {
                let candidate = resourceURL.appendingPathComponent("\(name).\(ext)")
                if fm.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        // C. Check bundle of the current executable (Contents/Resources)
        if let exeURL = Bundle.main.executableURL {
            let bundleResources = exeURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
            for ext in exts {
                let candidate = bundleResources.appendingPathComponent("\(name).\(ext)")
                if fm.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        // D. Check all loaded bundles and frameworks (including LoomCore and test bundles)
        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            for ext in exts {
                if let url = bundle.url(forResource: name, withExtension: ext) {
                    return url
                }
                if let resURL = bundle.resourceURL {
                    let candidate = resURL.appendingPathComponent("\(name).\(ext)")
                    if fm.fileExists(atPath: candidate.path) {
                        return candidate
                    }
                }
            }
        }

        // E. Check standard app bundle locations on system
        let candidateAppDirs = [
            "/Applications/Loom.app/Contents/Resources",
            ".build/Loom.app/Contents/Resources"
        ]
        for dir in candidateAppDirs {
            for ext in exts {
                let path = "\(dir)/\(name).\(ext)"
                if fm.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }

        // F. Fallback for test harnesses / command-line probes running relative to repo root
        let repoSearchDirs = [
            "Resources",
            "../Resources",
            "../../Resources"
        ]
        for dir in repoSearchDirs {
            for ext in exts {
                let path = "\(dir)/\(name).\(ext)"
                if fm.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }

        return nil
    }
}
