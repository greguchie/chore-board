import Foundation

nonisolated enum BoardRole: String, Codable, Hashable, Sendable {
    case owner, admin, member

    /// Mirrors the server's rules. The server still enforces them;
    /// the app only uses these to hide buttons that would fail.
    var canEditBoard: Bool { self == .owner || self == .admin }
    var canDeleteBoard: Bool { self == .owner }

    var label: String { rawValue.capitalized }
}

nonisolated struct Board: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let description: String?
    let ownerId: UUID
    let createdAt: Date
    let updatedAt: Date
    let myRole: BoardRole   // every board endpoint includes the caller's role
}
