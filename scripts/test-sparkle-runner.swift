//
//  test-sparkle-runner.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import AppKit
import Foundation
import Sparkle

@MainActor
final class HeadlessUserDriver: NSObject, SPUUserDriver {
    var onUpdateFound: ((SUAppcastItem) -> Void)?
    var onExtracting: (() -> Void)?
    var onReadyToInstall: (() -> Void)?
    var onError: ((Error) -> Void)?

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        print("==> [Sparkle Driver] Update found: \(appcastItem.displayVersionString) (build: \(appcastItem.versionString))")
        onUpdateFound?(appcastItem)
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        print("==> [Sparkle Driver] Update not found: \(error)")
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        print("==> [Sparkle Driver] Updater error: \(error)")
        onError?(error)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        print("==> [Sparkle Driver] Download initiated...")
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        print("==> [Sparkle Driver] Expected content length: \(expectedContentLength) bytes")
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {
        print("==> [Sparkle Driver] Download finished. Extracting update...")
        onExtracting?()
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        print("==> [Sparkle Driver] Update extracted and verified! Ready to install & relaunch.")
        onReadyToInstall?()
        reply(.dismiss)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }
    func dismissUpdateInstallation() {}
}

@MainActor
final class UpgradeTestController: NSObject, SPUUpdaterDelegate {
    let hostBundlePath: String
    let expectFailure: Bool
    let driver = HeadlessUserDriver()
    var updater: SPUUpdater?
    var succeeded = false
    var failureError: Error?

    init(hostBundlePath: String, expectFailure: Bool = false) {
        self.hostBundlePath = hostBundlePath
        self.expectFailure = expectFailure
        super.init()
    }

    func run() {
        guard let bundle = Bundle(path: hostBundlePath) else {
            print("==> [Test] ERROR: Invalid host bundle: \(hostBundlePath)")
            exit(1)
        }

        driver.onUpdateFound = { item in
            print("==> [Test] Verified update version in appcast: \(item.displayVersionString)")
        }

        let expectFailure = self.expectFailure
        driver.onReadyToInstall = { [weak self] in
            if expectFailure {
                print("==> [Test] FAILED: Tampered update reached install unexpectedly!")
                exit(1)
            }
            print("==> [Test] SUCCESS: Update downloaded, EdDSA verified, and extracted!")
            self?.succeeded = true
            exit(0)
        }

        driver.onError = { [weak self] error in
            if expectFailure {
                print("==> [Test] SUCCESS: Sparkle correctly rejected invalid/tampered update: \(error.localizedDescription)")
                exit(0)
            }
            print("==> [Test] ERROR received: \(error)")
            let ns = error as NSError
            for (k, v) in ns.userInfo {
                print("    UserInfo[\(k)]: \(v)")
            }
            self?.failureError = error
            exit(1)
        }

        let updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: driver,
            delegate: self
        )
        self.updater = updater

        do {
            try updater.start()
            print("==> [Test] SPUUpdater started. Triggering checkForUpdates()...")
            updater.checkForUpdates()
        } catch {
            print("==> [Test] SPUUpdater failed to start: \(error)")
            exit(1)
        }

        // Set a 20 second timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            print("==> [Test] ERROR: Timed out waiting for Sparkle update completion!")
            exit(1)
        }
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        if expectFailure {
            print("==> [Test] FAILED: Tampered update was unexpectedly extracted!")
            exit(1)
        }
        print("==> [Delegate] SUCCESS: Update didExtractUpdate invoked!")
        print("==> [Delegate] Verified target version: \(item.displayVersionString) (build: \(item.versionString))")
        print("==> [Delegate] EdDSA signature and archive payload verified by Sparkle 2 engine.")
        self.succeeded = true
        exit(0)
    }
}

@main
struct TestApp {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            print("Usage: test-sparkle-runner <host-bundle-path> [--expect-failure]")
            exit(1)
        }
        let hostBundlePath = args[1]
        let expectFailure = args.contains("--expect-failure")
        let app = NSApplication.shared
        let controller = UpgradeTestController(hostBundlePath: hostBundlePath, expectFailure: expectFailure)
        controller.run()
        app.run()
    }
}
