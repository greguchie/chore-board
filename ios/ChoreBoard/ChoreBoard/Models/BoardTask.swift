import Foundation

nonisolated enum TaskStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case todo
    case inProgress = "in_progress"
    case done

    var title: String {
        switch self {
        case .todo: "To do"
        case .inProgress: "In progress"
        case .done: "Done"
        }
    }

    var symbol: String {
        switch self {
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        }
    }

    /// Label for the swipe button that moves a task INTO this status.
    var moveLabel: String {
        switch self {
        case .todo: "To do"
        case .inProgress: "Start"
        case .done: "Done"
        }
    }
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

    /// A copy with a new status, used to update the screen before the server answers.
    /// completedAt mirrors the server rule: set when done, cleared otherwise.
    func withStatus(_ newStatus: TaskStatus) -> BoardTask {
        BoardTask(id: id, boardId: boardId, title: title, description: description,
                  status: newStatus, assigneeId: assigneeId, dueDate: dueDate,
                  completedAt: newStatus == .done ? (completedAt ?? .now) : nil,
                  createdAt: createdAt, updatedAt: .now)
    }
}
