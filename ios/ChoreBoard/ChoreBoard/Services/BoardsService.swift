import Foundation

/// What the boards screens need from the backend. Tests use a fake.
@MainActor
protocol BoardsProviding: AnyObject {
    func list() async throws -> [Board]
    func create(_ draft: BoardDraft) async throws -> Board
    func update(_ id: UUID, with draft: BoardDraft) async throws -> Board
    func delete(_ id: UUID) async throws
}

@MainActor
final class APIBoardsService: BoardsProviding {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func list() async throws -> [Board] {
        try await api.send(API.boards, as: [Board].self)
    }

    func create(_ draft: BoardDraft) async throws -> Board {
        try await api.send(API.createBoard(draft), as: Board.self)
    }

    func update(_ id: UUID, with draft: BoardDraft) async throws -> Board {
        try await api.send(API.updateBoard(id, draft), as: Board.self)
    }

    func delete(_ id: UUID) async throws {
        try await api.sendNoContent(API.deleteBoard(id))
    }
}
