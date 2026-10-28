import Foundation

nonisolated struct LoginRequest: Encodable, Sendable {
    let email: String
    let password: String
}

nonisolated struct SignUpRequest: Encodable, Sendable {
    let email: String
    let displayName: String
    let password: String
}

nonisolated struct RefreshRequest: Encodable, Sendable {
    let refreshToken: String
}

nonisolated struct BoardDraft: Encodable, Sendable {
    var name: String
    var description: String?
}

nonisolated struct AddMemberRequest: Encodable, Sendable {
    let userId: String
    let role: BoardRole
}

nonisolated struct RoleChangeRequest: Encodable, Sendable {
    let role: BoardRole
}

nonisolated struct TaskDraft: Encodable, Sendable {
    let title: String
    let description: String?
    let assigneeId: String?
    let dueDate: String?   // "YYYY-MM-DD"

    init(title: String, description: String? = nil, assigneeId: UUID? = nil, dueDate: String? = nil) {
        self.title = title
        self.description = description
        self.assigneeId = assigneeId?.apiString
        self.dueDate = dueDate
    }
}
