import Foundation

public enum ProviderAvailability: Hashable, Equatable, Sendable {
    case unknown
    case available
    case unavailable(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }

    public var unavailabilityReason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}
