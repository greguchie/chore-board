import Foundation

nonisolated enum TaskStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case todo
    case inProgress = "in_progress"
    case done
}

nonisolated struct BoardTask: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let boardId: UUID
    let title: String
    let description: String?
    let status: TaskStatus
    let assigneeId: UUID?     // a Member.id, not a User.id
    let dueDate: String?      // "YYYY-MM-DD": a calendar day, not a moment in time
    let completedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}
