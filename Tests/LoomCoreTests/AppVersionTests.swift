//
//  AppVersionTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
@testable import LoomCore

final class AppVersionTests: XCTestCase {
    func testResolveFromStandardInfoDictionary() {
        let dict: [String: Any] = [
            "CFBundleShortVersionString": "0.1.1",
            "CFBundleVersion": "2"
        ]
        let version = AppVersion.resolve(infoDictionary: dict)

        XCTAssertEqual(version.marketingVersion, "0.1.1")
        XCTAssertEqual(version.buildVersion, "2")
        XCTAssertFalse(version.isDevelopmentBuild)
        XCTAssertEqual(version.menuBarString, "v0.1.1")
        XCTAssertEqual(version.shortString, "0.1.1")
        XCTAssertEqual(version.headerVersionString, "0.1.1")
        XCTAssertEqual(version.aboutString, "Version 0.1.1 (2)")
        XCTAssertEqual(version.menuBarAccessibilityLabel, "Loom, version 0.1.1")
    }

    func testResolveWhenBuildMatchesMarketingVersion() {
        let dict: [String: Any] = [
            "CFBundleShortVersionString": "0.1.1",
            "CFBundleVersion": "0.1.1"
        ]
        let version = AppVersion.resolve(infoDictionary: dict)

        XCTAssertEqual(version.marketingVersion, "0.1.1")
        XCTAssertEqual(version.buildVersion, "0.1.1")
        XCTAssertFalse(version.isDevelopmentBuild)
        XCTAssertEqual(version.aboutString, "Version 0.1.1")
    }

    func testResolveFromNilInfoDictionaryGracefulFallback() {
        let version = AppVersion.resolve(infoDictionary: nil)

        XCTAssertEqual(version.marketingVersion, AppVersion.fallbackMarketingVersion)
        XCTAssertEqual(version.buildVersion, "dev")
        XCTAssertTrue(version.isDevelopmentBuild)
        XCTAssertEqual(version.menuBarString, "v1.0-dev")
        XCTAssertEqual(version.aboutString, "Version 1.0 (Dev)")
        XCTAssertEqual(version.menuBarAccessibilityLabel, "Loom, version 1.0 development")
    }

    func testResolveFromEmptyInfoDictionaryGracefulFallback() {
        let version = AppVersion.resolve(infoDictionary: [:])

        XCTAssertEqual(version.marketingVersion, AppVersion.fallbackMarketingVersion)
        XCTAssertEqual(version.buildVersion, "dev")
        XCTAssertTrue(version.isDevelopmentBuild)
        XCTAssertEqual(version.menuBarString, "v1.0-dev")
        XCTAssertEqual(version.aboutString, "Version 1.0 (Dev)")
    }

    func testResolveWithWhitespaceTrimming() {
        let dict: [String: Any] = [
            "CFBundleShortVersionString": "  1.2.0 \n",
            "CFBundleVersion": "  42  "
        ]
        let version = AppVersion.resolve(infoDictionary: dict)

        XCTAssertEqual(version.marketingVersion, "1.2.0")
        XCTAssertEqual(version.buildVersion, "42")
        XCTAssertFalse(version.isDevelopmentBuild)
        XCTAssertEqual(version.menuBarString, "v1.2.0")
        XCTAssertEqual(version.aboutString, "Version 1.2.0 (42)")
    }
}
