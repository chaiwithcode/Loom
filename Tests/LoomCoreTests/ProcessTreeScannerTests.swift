//
//  ProcessTreeScannerTests.swift
//  LoomCoreTests
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation
@testable import LoomCore
import XCTest

final class ProcessTreeScannerTests: XCTestCase {
    func testScanProcessTableFindsCurrentProcess() {
        let scanner = ProcessTreeScanner()
        let table = scanner.scanProcessTable()
        let myPID = getpid()

        XCTAssertFalse(table.isEmpty, "Process table should not be empty")
        guard let myProc = table[myPID] else {
            XCTFail("Process table should contain the running test process (PID \(myPID))")
            return
        }

        XCTAssertEqual(myProc.pid, myPID)
        XCTAssertEqual(myProc.ppid, getppid())
        XCTAssertFalse(myProc.name.isEmpty, "Process name should not be empty")
        XCTAssertFalse(myProc.executablePath.isEmpty, "Executable path should not be empty")
    }

    func testResolveCWDForCurrentProcess() {
        let myPID = getpid()
        let cwd = ProcessTreeScanner.resolveCWD(for: myPID)
        XCTAssertNotNil(cwd, "Current process CWD should be resolvable")
        if let cwd = cwd {
            XCTAssertTrue(FileManager.default.fileExists(atPath: cwd), "Resolved CWD path should exist")
        }
    }

    func testFindAncestorWalkingPPIDChain() {
        let rootPID: pid_t = 100
        let midPID: pid_t = 200
        let leafPID: pid_t = 300
        let otherPID: pid_t = 400

        let table: [pid_t: MonitoredProcess] = [
            rootPID: MonitoredProcess(pid: rootPID, ppid: 1, name: "t3code", executablePath: "/usr/local/bin/t3code", cwd: "/tmp"),
            midPID: MonitoredProcess(pid: midPID, ppid: rootPID, name: "sh", executablePath: "/bin/sh", cwd: "/tmp"),
            leafPID: MonitoredProcess(pid: leafPID, ppid: midPID, name: "codex", executablePath: "/usr/local/bin/codex", cwd: "/tmp"),
            otherPID: MonitoredProcess(pid: otherPID, ppid: 1, name: "safari", executablePath: "/Applications/Safari.app", cwd: nil)
        ]

        let ancestor = ProcessTreeScanner.findAncestor(of: leafPID, in: table, matching: [rootPID])
        XCTAssertEqual(ancestor, rootPID, "Should find ancestor rootPID via midPID")

        let noAncestor = ProcessTreeScanner.findAncestor(of: otherPID, in: table, matching: [rootPID])
        XCTAssertNil(noAncestor, "Unrelated process should not match ancestor")
    }

    func testIsCandidateProcessMatchesAgyAcpServer() {
        XCTAssertTrue(ProcessTreeScanner.isCandidateProcess(name: "agy_acp_server.par", execPath: "/opt/bin/agy_acp_server.par"))
        XCTAssertTrue(ProcessTreeScanner.isCandidateProcess(name: "python", execPath: "/usr/local/bin/agy_acp_server"))
        XCTAssertTrue(ProcessTreeScanner.isCandidateProcess(name: "agy", execPath: "/usr/local/bin/agy"))
        XCTAssertFalse(ProcessTreeScanner.isCandidateProcess(name: "finder", execPath: "/System/Library/CoreServices/Finder.app"))
    }
}
