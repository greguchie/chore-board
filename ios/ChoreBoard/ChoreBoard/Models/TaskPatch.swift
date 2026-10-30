import Foundation

/// One field in a PATCH request. The server treats these three cases differently:
/// key missing = leave it alone, null = clear it, value = set it.
nonisolated enum FieldUpdate: Equatable, Sendable {
    case unchanged
    case clear
    case set(String)
}

/// Body for PATCH /boards/:boardId/tasks/:taskId.
/// Swift's default encoder drops nil values, so it can't send null.
/// This custom encode(to:) writes exactly what the server needs.
nonisolated struct TaskPatch: Encodable, Equatable, Sendable {
    var title: String? = nil            // nil = unchanged (a title can't be cleared)
    var description: FieldUpdate = .unchanged
    var status: TaskStatus? = nil       // nil = unchanged
    var assigneeId: FieldUpdate = .unchanged
    var dueDate: FieldUpdate = .unchanged

    var isEmpty: Bool { self == TaskPatch() }

    nonisolated enum CodingKeys: String, CodingKey {
        case title, description, status, assigneeId, dueDate
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(status, forKey: .status)
        try encode(description, as: .description, in: &container)
        try encode(assigneeId, as: .assigneeId, in: &container)
        try encode(dueDate, as: .dueDate, in: &container)
    }

    private func encode(_ update: FieldUpdate, as key: CodingKeys,
                        in container: inout KeyedEncodingContainer<CodingKeys>) throws {
        switch update {
        case .unchanged: break
        case .clear: try container.encodeNil(forKey: key)
        case .set(let value): try container.encode(value, forKey: key)
        }
    }
}
