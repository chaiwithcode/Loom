#!/usr/bin/env swift
//
//  verify-ds-store.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

//
// NOTE / LIMITATION:
// This tool performs an on-disk metadata sanity check by locating embedded 'icvpblob'
// payloads in .DS_Store and deserializing the exact binary property list slice.
// It does not parse the proprietary DS_Store B-tree structures or guarantee record
// liveness against deleted/stale block allocations in un-cleared stores.
// Complete proof of layout and visual fidelity relies on:
// 1. Cleaning pre-existing .DS_Store prior to configuration.
// 2. Active assertions against the reopened Finder container window.
// 3. Independent visual and programmatic inspection of the final mounted DMG.
//

import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: verify-ds-store.swift <path/to/.DS_Store>\n", stderr)
    exit(1)
}

let dsStorePath = CommandLine.arguments[1]
let dsStoreURL = URL(fileURLWithPath: dsStorePath)

guard let data = try? Data(contentsOf: dsStoreURL) else {
    fputs("Error: Could not read .DS_Store at \(dsStorePath)\n", stderr)
    exit(1)
}

// 1. Verify DSStore header (0x00000001 followed by "Bud1")
guard data.count >= 32 else {
    fputs("Assertion failed: .DS_Store file is too small (\(data.count) bytes)\n", stderr)
    exit(1)
}

let bud1Magic = Data([0x00, 0x00, 0x00, 0x01]) + Data("Bud1".utf8)
guard data.prefix(8) == bud1Magic else {
    fputs("Assertion failed: Missing .DS_Store 'Bud1' header magic\n", stderr)
    exit(1)
}

// 2. Locate icvp blob and parse exact slice
let bplistMagic = Data("bplist00".utf8)
let icvpBlobTag = Data("icvpblob".utf8)
var foundValidRecord = false

var searchRange = data.startIndex..<data.endIndex
while let magicRange = data.range(of: bplistMagic, options: [], in: searchRange) {
    let magicOffset = magicRange.lowerBound

    // Require preceding 12 bytes: 8 bytes 'icvpblob' + 4 bytes big-endian UInt32 length
    if magicOffset >= 12 {
        let tagRange = (magicOffset - 12)..<(magicOffset - 4)
        if data.subdata(in: tagRange) == icvpBlobTag {
            let lengthBytes = [UInt8](data.subdata(in: (magicOffset - 4)..<magicOffset))
            let blobLength = Int(UInt32(lengthBytes[0]) << 24 | UInt32(lengthBytes[1]) << 16 | UInt32(lengthBytes[2]) << 8 | UInt32(lengthBytes[3]))

            guard blobLength > 0, magicOffset + blobLength <= data.count else {
                fputs("Assertion failed: Invalid blob length (\(blobLength)) for icvp blob\n", stderr)
                exit(1)
            }

            let exactBlob = data.subdata(in: magicOffset..<(magicOffset + blobLength))
            guard let plist = try? PropertyListSerialization.propertyList(from: exactBlob, options: [], format: nil) as? [String: Any] else {
                fputs("Assertion failed: Failed to deserialize exact icvp binary property list\n", stderr)
                exit(1)
            }

            // 3. Assertions matching exact specifications
            guard let bgType = (plist["backgroundType"] as? NSNumber)?.intValue, bgType == 2 else {
                fputs("Assertion failed: backgroundType is not 2 (got \(String(describing: plist["backgroundType"]))\n", stderr)
                exit(1)
            }

            guard let iconSizeNum = plist["iconSize"] as? NSNumber, iconSizeNum.doubleValue == 96.0 else {
                fputs("Assertion failed: iconSize is not 96 (got \(String(describing: plist["iconSize"]))\n", stderr)
                exit(1)
            }

            guard let arrangeBy = plist["arrangeBy"] as? String, arrangeBy == "none" else {
                fputs("Assertion failed: arrangeBy is not 'none' (got \(String(describing: plist["arrangeBy"]))\n", stderr)
                exit(1)
            }

            guard let labelOnBottom = (plist["labelOnBottom"] as? NSNumber)?.boolValue, labelOnBottom == true else {
                fputs("Assertion failed: labelOnBottom is not true (got \(String(describing: plist["labelOnBottom"]))\n", stderr)
                exit(1)
            }

            guard let aliasData = plist["backgroundImageAlias"] as? Data, !aliasData.isEmpty else {
                fputs("Assertion failed: backgroundImageAlias is missing or empty\n", stderr)
                exit(1)
            }

            let tiffUtf8 = Data("background.tiff".utf8)
            let tiffUtf16BE = Data("background.tiff".utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] })
            guard aliasData.range(of: tiffUtf8) != nil || aliasData.range(of: tiffUtf16BE) != nil else {
                fputs("Assertion failed: backgroundImageAlias does not reference 'background.tiff'\n", stderr)
                exit(1)
            }

            print("SUCCESS: Validated .DS_Store icvp properties:")
            print("  header: Bud1 (valid)")
            print("  blob: exact length \(blobLength) bytes")
            print("  backgroundType: \(bgType)")
            print("  iconSize: \(iconSizeNum.doubleValue)")
            print("  arrangeBy: \(arrangeBy)")
            print("  labelOnBottom: \(labelOnBottom)")
            print("  backgroundImageAlias: \(aliasData.count) bytes (verified background.tiff reference)")

            foundValidRecord = true
            break
        }
    }

    searchRange = magicRange.upperBound..<data.endIndex
}

if !foundValidRecord {
    fputs("Assertion failed: No 'icvpblob' record found in .DS_Store\n", stderr)
    exit(1)
}

exit(0)
