import Foundation
import Testing
@testable import ChoreBoard

extension Board {
    static func sample(id: UUID = UUID(), name: String = "Home",
                       description: String? = nil, role: BoardRole = .owner) -> Board {
        Board(id: id, name: name, description: description, ownerId: UUID(),
              createdAt: .now, updatedAt: .now, myRole: role)
    }
}

@MainActor
final class FakeBoardsService: BoardsProviding {
    var boards: [Board] = []
    var error: Error?
    private(set) var deletedIds: [UUID] = []
    private(set) var updatedId: UUID?
    private(set) var lastDraft: BoardDraft?

    func list() async throws -> [Board] {
        if let error { throw error }
        return boards
    }

    func create(_ draft: BoardDraft) async throws -> Board {
        lastDraft = draft
        if let error { throw error }
        return .sample(name: draft.name, description: draft.description, role: .owner)
    }

    func update(_ id: UUID, with draft: BoardDraft) async throws -> Board {
        lastDraft = draft
        updatedId = id
        if let error { throw error }
        return .sample(id: id, name: draft.name, description: draft.description, role: .admin)
    }

    func delete(_ id: UUID) async throws {
        if let error { throw error }
        deletedIds.append(id)
    }
}

@MainActor
struct BoardsTests {

    @Test func permissionsMirrorServerRoles() {
        #expect(BoardRole.owner.canEditBoard && BoardRole.owner.canDeleteBoard)
        #expect(BoardRole.admin.canEditBoard && !BoardRole.admin.canDeleteBoard)
        #expect(!BoardRole.member.canEditBoard && !BoardRole.member.canDeleteBoard)
    }

    @Test func loadShowsBoards() async {
        let service = FakeBoardsService()
        service.boards = [.sample(name: "Home"), .sample(name: "Office", role: .member)]
        let viewModel = BoardsViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.boards.map(\.name) == ["Home", "Office"])
    }

    @Test func firstLoadFailureShowsErrorScreen() async {
        let service = FakeBoardsService()
        service.error = APIError.offline
        let viewModel = BoardsViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.state == .failed(APIError.offline.localizedDescription))
        #expect(viewModel.actionError == nil)
    }

    @Test func failedRefreshKeepsBoardsOnScreen() async {
        let service = FakeBoardsService()
        service.boards = [.sample()]
        let viewModel = BoardsViewModel(service: service)
        await viewModel.load()

        service.error = APIError.offline
        await viewModel.load()

        #expect(viewModel.boards.count == 1)
        #expect(viewModel.state == .loaded)
        #expect(viewModel.actionError == APIError.offline.localizedDescription)
    }

    @Test func deleteRemovesBoard() async {
        let board = Board.sample(role: .owner)
        let service = FakeBoardsService()
        service.boards = [board]
        let viewModel = BoardsViewModel(service: service)
        await viewModel.load()

        await viewModel.delete(board)

        #expect(viewModel.boards.isEmpty)
        #expect(service.deletedIds == [board.id])
    }

    @Test func failedDeletePutsBoardBack() async {
        let board = Board.sample(role: .owner)
        let service = FakeBoardsService()
        service.boards = [board]
        let viewModel = BoardsViewModel(service: service)
        await viewModel.load()

        service.error = APIError.forbidden("Your role on this board doesn't allow this")
        await viewModel.delete(board)

        #expect(viewModel.boards == [board])
        #expect(viewModel.actionError == "Your role on this board doesn't allow this")
    }

    @Test func membersCannotDelete() async {
        let board = Board.sample(role: .member)
        let service = FakeBoardsService()
        service.boards = [board]
        let viewModel = BoardsViewModel(service: service)
        await viewModel.load()

        await viewModel.delete(board)

        #expect(service.deletedIds.isEmpty)
        #expect(viewModel.boards.count == 1)
    }

    @Test func editorRequiresAName() async {
        let service = FakeBoardsService()
        let viewModel = BoardEditorViewModel(service: service)
        viewModel.name = "   "

        let saved = await viewModel.save()

        #expect(saved == nil)
        #expect(viewModel.visibleNameError == "Enter a board name")
        #expect(service.lastDraft == nil)
    }

    @Test func editorCreatesTrimmedBoardWithoutEmptyDescription() async {
        let service = FakeBoardsService()
        let viewModel = BoardEditorViewModel(service: service)
        viewModel.name = "  Home  "
        viewModel.details = "   "

        let saved = await viewModel.save()

        #expect(saved?.name == "Home")
        #expect(service.lastDraft?.name == "Home")
        #expect(service.lastDraft?.description == nil)
    }

    @Test func editorClearsAnExistingDescription() async {
        let existing = Board.sample(description: "Old notes", role: .admin)
        let service = FakeBoardsService()
        let viewModel = BoardEditorViewModel(service: service, existing: existing)
        #expect(viewModel.name == "Home")
        #expect(viewModel.details == "Old notes")

        viewModel.details = ""
        let saved = await viewModel.save()

        #expect(saved != nil)
        #expect(service.updatedId == existing.id)
        #expect(service.lastDraft?.description == "")   // "" clears it; nil would leave it unchanged
    }
}
