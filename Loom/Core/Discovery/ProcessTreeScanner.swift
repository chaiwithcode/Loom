//
//  ProcessTreeScanner.swift
//  Loom
//
//  Copyright © 2026 Deepak Sharma (ChaiWithCode).
//  Licensed under the MIT License. See LICENSE for details.
//

import Darwin
import Foundation

public struct MonitoredProcess: Sendable, Equatable {
    public let pid: pid_t
    public let ppid: pid_t
    public let name: String
    public let executablePath: String
    public let cwd: String?

    public init(
        pid: pid_t,
        ppid: pid_t,
        name: String,
        executablePath: String,
        cwd: String?
    ) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.executablePath = executablePath
        self.cwd = cwd
    }
}

public final class ProcessTreeScanner: Sendable {
    public init() {}

    public func scanProcessTable() -> [pid_t: MonitoredProcess] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [:] }

        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let actualBytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        let pidCount = Int(actualBytes) / MemoryLayout<pid_t>.stride

        var table: [pid_t: MonitoredProcess] = [:]
        table.reserveCapacity(pidCount)

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            // 1. Get BSD Info (PPID & Process Name)
            var bsdInfo = proc_bsdinfo()
            let bsdSize = proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                &bsdInfo,
                Int32(MemoryLayout<proc_bsdinfo>.stride)
            )
            guard bsdSize == MemoryLayout<proc_bsdinfo>.stride else { continue }

            let ppid = pid_t(bsdInfo.pbi_ppid)
            let name = withUnsafePointer(to: &bsdInfo.pbi_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                    String(cString: $0)
                }
            }

            // 2. Get Executable Path
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let execPath = pathLen > 0 ? String(cString: pathBuffer) : ""

            // 3. Only resolve CWD for candidate processes to save syscalls
            let isCandidate = Self.isCandidateProcess(name: name, execPath: execPath)
            let cwd = isCandidate ? Self.resolveCWD(for: pid) : nil

            table[pid] = MonitoredProcess(
                pid: pid,
                ppid: ppid,
                name: name,
                executablePath: execPath,
                cwd: cwd
            )
        }
        return table
    }

    static func isCandidateProcess(name: String, execPath: String) -> Bool {
        let lowerName = name.lowercased()
        let lowerPath = execPath.lowercased()
        let targets = ["t3", "t3code", "codex", "claude", "agy", "agy_acp_server", "antigravity", "node", "bun"]
        return targets.contains { lowerName.contains($0) || lowerPath.contains($0) }
    }

    public static func resolveCWD(for pid: pid_t) -> String? {
        var vnodeInfo = proc_vnodepathinfo()
        let size = proc_pidinfo(
            pid,
            PROC_PIDVNODEPATHINFO,
            0,
            &vnodeInfo,
            Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        )
        guard size == MemoryLayout<proc_vnodepathinfo>.stride else { return nil }
        return withUnsafePointer(to: &vnodeInfo.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                let str = String(cString: $0)
                return str.isEmpty ? nil : str
            }
        }
    }

    /// Walks up the PPID chain (max depth 8) to check if `pid` is a descendant of `ancestorPIDs`.
    public static func findAncestor(
        of pid: pid_t,
        in table: [pid_t: MonitoredProcess],
        matching ancestorPIDs: Set<pid_t>
    ) -> pid_t? {
        var currentPID = pid
        for _ in 0..<8 {
            guard let proc = table[currentPID], proc.ppid > 1 else { return nil }
            if ancestorPIDs.contains(proc.ppid) {
                return proc.ppid
            }
            currentPID = proc.ppid
        }
        return nil
    }
}
