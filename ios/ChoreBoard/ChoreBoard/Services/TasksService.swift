import Foundation

/// What the task screens need from the backend. Tests use a fake.
@MainActor
protocol TasksProviding: AnyObject {
    func tasks(boardId: UUID) async throws -> [BoardTask]
    func members(boardId: UUID) async throws -> [Member]
    func create(boardId: UUID, _ draft: TaskDraft) async throws -> BoardTask
    func update(boardId: UUID, taskId: UUID, with patch: TaskPatch) async throws -> BoardTask
    func delete(boardId: UUID, taskId: UUID) async throws
}

@MainActor
final class APITasksService: TasksProviding {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func tasks(boardId: UUID) async throws -> [BoardTask] {
        try await api.send(API.tasks(boardId: boardId), as: [BoardTask].self)
    }

    func members(boardId: UUID) async throws -> [Member] {
        try await api.send(API.members(boardId: boardId), as: [Member].self)
    }

    func create(boardId: UUID, _ draft: TaskDraft) async throws -> BoardTask {
        try await api.send(API.createTask(boardId: boardId, draft), as: BoardTask.self)
    }

    func update(boardId: UUID, taskId: UUID, with patch: TaskPatch) async throws -> BoardTask {
        try await api.send(API.updateTask(boardId: boardId, taskId: taskId, patch), as: BoardTask.self)
    }

    func delete(boardId: UUID, taskId: UUID) async throws {
        try await api.sendNoContent(API.deleteTask(boardId: boardId, taskId: taskId))
    }
}
