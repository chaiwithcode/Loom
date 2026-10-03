import Foundation

public struct ProviderID: Hashable, Equatable, Sendable, RawRepresentable, Identifiable, CustomStringConvertible {
    public let rawValue: String

    public var id: String { rawValue }
    public var description: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let codex = ProviderID("codex")
    public static let claude = ProviderID("claude")
    public static let antigravity = ProviderID("antigravity")
}
