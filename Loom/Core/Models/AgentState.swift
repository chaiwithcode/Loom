import Foundation

public enum AgentState: String, Hashable, Equatable, Sendable, CaseIterable {
    case working
    case waiting
    case finished
    case failed
    case idle
    case unknown

    public var displayName: String {
        switch self {
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .finished: return "Finished"
        case .failed: return "Failed"
        case .idle: return "Idle"
        case .unknown: return "Unknown"
        }
    }
}
