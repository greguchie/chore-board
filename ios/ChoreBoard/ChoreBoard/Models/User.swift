import Foundation

nonisolated struct User: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let email: String
    let displayName: String
    let createdAt: Date?   // not included in the user inside the login response
    let updatedAt: Date?
}
