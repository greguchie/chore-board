import Foundation

nonisolated enum BoardRole: String, Codable, Hashable, Sendable {
    case owner, admin, member
}

nonisolated struct Board: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let description: String?
    let ownerId: UUID
    let createdAt: Date
    let updatedAt: Date
    let myRole: BoardRole?   // the caller's role; PATCH /boards/:id doesn't return it yet
}
