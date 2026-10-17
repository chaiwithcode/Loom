//
//  AppVersion.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Foundation

public struct AppVersion: Equatable, Hashable, Sendable {
    public let marketingVersion: String
    public let buildVersion: String?
    public let isDevelopmentBuild: Bool

    public static let fallbackMarketingVersion = "1.0"

    public init(
        marketingVersion: String,
        buildVersion: String? = nil,
        isDevelopmentBuild: Bool = false
    ) {
        self.marketingVersion = marketingVersion
        let trimmedBuild = buildVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.buildVersion = (trimmedBuild?.isEmpty ?? true) ? nil : trimmedBuild
        self.isDevelopmentBuild = isDevelopmentBuild
    }

    /// Canonical shared instance resolved from Bundle.main.
    public static let current: AppVersion = resolve(from: .main)

    /// Resolves an AppVersion instance from a bundle's infoDictionary.
    public static func resolve(from bundle: Bundle = .main) -> AppVersion {
        resolve(infoDictionary: bundle.infoDictionary)
    }

    /// Pure resolver accepting an infoDictionary for testability and headless environments.
    public static func resolve(infoDictionary: [String: Any]?) -> AppVersion {
        guard let dict = infoDictionary else {
            return AppVersion(
                marketingVersion: fallbackMarketingVersion,
                buildVersion: "dev",
                isDevelopmentBuild: true
            )
        }

        let rawMarketing = (dict["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawBuild = (dict["CFBundleVersion"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let marketing: String
        let isDev: Bool
        if let rawMarketing, !rawMarketing.isEmpty {
            marketing = rawMarketing
            isDev = false
        } else {
            marketing = fallbackMarketingVersion
            isDev = true
        }

        let build: String?
        if let rawBuild, !rawBuild.isEmpty {
            build = rawBuild
        } else if isDev {
            build = "dev"
        } else {
            build = nil
        }

        return AppVersion(
            marketingVersion: marketing,
            buildVersion: build,
            isDevelopmentBuild: isDev
        )
    }

    /// Compact representation for menu bar: e.g. "v0.1.1" or "v0.1.1-dev"
    public var menuBarString: String {
        if isDevelopmentBuild {
            return "v\(marketingVersion)-dev"
        }
        return "v\(marketingVersion)"
    }

    /// Plain marketing version string: e.g. "0.1.1"
    public var shortString: String {
        marketingVersion
    }

    /// Quiet marketing version string for the popover header: e.g. "0.1.1" (no "v" prefix, no build number)
    public var headerVersionString: String {
        marketingVersion
    }

    /// Full representation for About settings tab: e.g. "Version 0.1.1 (2)" or "Version 0.1.1 (Dev)"
    public var aboutString: String {
        if isDevelopmentBuild {
            return "Version \(marketingVersion) (Dev)"
        }
        if let build = buildVersion, build != marketingVersion {
            return "Version \(marketingVersion) (\(build))"
        }
        return "Version \(marketingVersion)"
    }

    /// Accessibility label for menu bar item
    public var menuBarAccessibilityLabel: String {
        if isDevelopmentBuild {
            return "Loom, version \(marketingVersion) development"
        }
        return "Loom, version \(marketingVersion)"
    }
}
