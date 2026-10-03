import Foundation

public final class DefaultAntigravityProcessDiscoverer: AntigravityProcessDiscovering, Sendable {
    private let executor: any ProcessExecuting
    private let psPath: String

    public init(
        executor: any ProcessExecuting = DefaultProcessExecutor(),
        psPath: String = "/bin/ps"
    ) {
        self.executor = executor
        self.psPath = psPath
    }

    public func isAntigravityRunning() async -> Bool {
        let psOutput: String
        do {
            psOutput = try await executor.execute(
                executablePath: psPath,
                arguments: ["-ax", "-o", "command="]
            )
        } catch {
            return false
        }

        let lines = psOutput.components(separatedBy: .newlines)
        for line in lines {
            if AntigravityParser.isAntigravityProcessCommand(line) {
                return true
            }
        }

        return false
    }
}
