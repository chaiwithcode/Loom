//
//  SettingsTests.swift
//  Loom
//
//  Created by Deepak Sharma on 03/10/2026.
//  Copyright © 2026 ChaiWithCode. All rights reserved.
//

import XCTest
@testable import LoomCore

final class SettingsTests: XCTestCase {
    private var suiteName: String!
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.loom.settings.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        if let suiteName, let testDefaults {
            testDefaults.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    @MainActor
    func testDefaultValuesWhenNoPriorStorage() {
        let settings = LoomSettings(defaults: testDefaults)
        XCTAssertFalse(settings.showInDock, "Default showInDock must be false")
        XCTAssertEqual(settings.refreshIntervalSeconds, 60, "Default refresh interval must be 60 seconds")
    }

    @MainActor
    func testShowInDockPersistenceAndCallback() {
        let settings = LoomSettings(defaults: testDefaults)
        var callbackValue: Bool?
        settings.onShowInDockChanged = { val in
            callbackValue = val
        }

        settings.showInDock = true
        XCTAssertTrue(testDefaults.bool(forKey: LoomSettings.showInDockKey))
        XCTAssertEqual(callbackValue, true)

        let reloaded = LoomSettings(defaults: testDefaults)
        XCTAssertTrue(reloaded.showInDock, "Persisted showInDock value should load on re-initialization")
    }

    @MainActor
    func testRefreshIntervalPersistenceAndSanitization() {
        let settings = LoomSettings(defaults: testDefaults)

        settings.refreshIntervalSeconds = 120
        XCTAssertEqual(testDefaults.integer(forKey: LoomSettings.refreshIntervalKey), 120)

        let reloaded = LoomSettings(defaults: testDefaults)
        XCTAssertEqual(reloaded.refreshIntervalSeconds, 120)

        // Invalid interval resets to default (60)
        settings.refreshIntervalSeconds = 999
        XCTAssertEqual(settings.refreshIntervalSeconds, 60, "Unsupported interval should sanitize to 60")
    }

    @MainActor
    func testResetToDefaults() {
        let settings = LoomSettings(defaults: testDefaults)
        settings.showInDock = true
        settings.refreshIntervalSeconds = 300

        settings.resetToDefaults()
        XCTAssertFalse(settings.showInDock)
        XCTAssertEqual(settings.refreshIntervalSeconds, 60)
    }
}
