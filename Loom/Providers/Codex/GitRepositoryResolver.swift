import Foundation

public struct GitHEADParser: Sendable {
    public static func parseBranch(headContent: String) -> String? {
        let trimmed = headContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("ref: refs/heads/") {
            let branch = String(trimmed.dropFirst("ref: refs/heads/".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return branch.isEmpty ? nil : branch
        }

        // Detached HEAD commit hash
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        if trimmed.count >= 7 && trimmed.unicodeScalars.allSatisfy({ hexChars.contains($0) }) {
            return String(trimmed.prefix(7))
        }

        return nil
    }

    public static func parseWorktreeGitDir(gitFileContent: String, relativeTo baseURL: URL) -> URL? {
        let trimmed = gitFileContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("gitdir:") else { return nil }
        let rawPath = String(trimmed.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespaces)
        guard !rawPath.isEmpty else { return nil }

        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath).standardizedFileURL
        } else {
            return baseURL.appendingPathComponent(rawPath).standardizedFileURL
        }
    }
}

public protocol FileSystemInspecting: Sendable {
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool
    func readFile(atPath path: String) throws -> String
}

public final class DefaultFileSystemInspector: FileSystemInspecting, Sendable {
    public init() {}

    public func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        FileManager.default.fileExists(atPath: path, isDirectory: isDirectory)
    }

    public func readFile(atPath path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }
}

public final class DefaultGitRepositoryResolver: GitRepositoryResolving, Sendable {
    private let fileSystem: any FileSystemInspecting

    public init(fileSystem: any FileSystemInspecting = DefaultFileSystemInspector()) {
        self.fileSystem = fileSystem
    }

    public func resolveRepository(for directoryURL: URL) async -> GitRepositoryInfo? {
        var current = directoryURL.standardizedFileURL

        while current.pathComponents.count > 1 {
            let gitPath = current.appendingPathComponent(".git").path
            var isDir: ObjCBool = false

            if fileSystem.fileExists(atPath: gitPath, isDirectory: &isDir) {
                let projectName = current.lastPathComponent
                var branch: String? = nil

                if isDir.boolValue {
                    // Regular .git directory
                    let headPath = (gitPath as NSString).appendingPathComponent("HEAD")
                    if let headContent = try? fileSystem.readFile(atPath: headPath) {
                        branch = GitHEADParser.parseBranch(headContent: headContent)
                    }
                } else {
                    // .git file (worktree or submodule)
                    if let gitFileContent = try? fileSystem.readFile(atPath: gitPath),
                       let resolvedGitDir = GitHEADParser.parseWorktreeGitDir(gitFileContent: gitFileContent, relativeTo: current) {
                        let headPath = resolvedGitDir.appendingPathComponent("HEAD").path
                        if let headContent = try? fileSystem.readFile(atPath: headPath) {
                            branch = GitHEADParser.parseBranch(headContent: headContent)
                        }
                    }
                }

                return GitRepositoryInfo(
                    rootURL: current,
                    projectName: projectName,
                    branch: branch
                )
            }

            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                break
            }
            current = parent
        }

        return nil
    }
}
