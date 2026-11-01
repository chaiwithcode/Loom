//
//  AgentSessionsSectionViewTests.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import XCTest
import SwiftUI
@testable import LoomCore

@MainActor
final class AgentSessionsSectionViewTests: XCTestCase {

    func testAgentSessionsSectionViewInstantiation() {
        let coordinator = AgentMonitoringCoordinator()
        let view = AgentSessionsSectionView(coordinator: coordinator)
        XCTAssertNotNil(view)
        XCTAssertNotNil(view.body)
    }

    func testTokenFormatting() {
        XCTAssertEqual(AgentSessionsSectionView.formatTokens(0), "0")
        XCTAssertEqual(AgentSessionsSectionView.formatTokens(999), "999")
        XCTAssertEqual(AgentSessionsSectionView.formatTokens(1_000), "1.0K")
        XCTAssertEqual(AgentSessionsSectionView.formatTokens(47_100), "47.1K")
        XCTAssertEqual(AgentSessionsSectionView.formatTokens(1_200_000), "1.2M")
        XCTAssertEqual(AgentSessionsSectionView.formatTokens(2_500_000), "2.5M")
    }
}
