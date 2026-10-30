import Foundation

nonisolated struct Member: Codable, Hashable, Identifiable, Sendable {
    let id: UUID              // the MEMBERSHIP id; tasks use this as assigneeId
    let userId: UUID
    let role: BoardRole
    let joinedAt: Date
    let displayName: String?  // only in GET /boards/:id/members
    let email: String?

    var name: String { displayName ?? email ?? "Member" }
}
