import Foundation
import Testing
@testable import ChoreBoard

@MainActor
struct OfflineCacheTests {

    // MARK: The SwiftData store itself

    @Test func savesAndReadsBoardsInOrder() throws {
        let cache = SwiftDataCache.inMemory()
        #expect(cache.cachedBoards() == nil)   // never saved yet

        cache.saveBoards([.sample(name: "Home", description: nil, role: .owner),
                          .sample(name: "Office", description: "Kitchen", role: .member)])

        let cached = try #require(cache.cachedBoards())
        #expect(cached.value.map(\.name) == ["Home", "Office"])
        #expect(cached.value.map(\.myRole) == [.owner, .member])
        #expect(cached.value[0].description == nil)
        #expect(cached.value[1].description == "Kitchen")
    }

    @Test func emptyBoardListIsStillCached() throws {
        let cache = SwiftDataCache.inMemory()
        cache.saveBoards([])

        let cached = try #require(cache.cachedBoards())
        #expect(cached.value.isEmpty)
    }

    @Test func tasksAndMembersAreStoredPerBoard() throws {
        let cache = SwiftDataCache.inMemory()
        let boardA = UUID(), boardB = UUID()
        let sam = Member.sample(name: "Sam")
        cache.saveContents(BoardContents(tasks: [.sample(title: "Bins", status: .inProgress,
                                                         assigneeId: sam.id, dueDate: "2026-11-01")],
                                         members: [sam]),
                           boardId: boardA)
        cache.saveContents(BoardContents(tasks: [.sample(title: "Fridge")], members: []), boardId: boardB)

        let a = try #require(cache.cachedContents(boardId: boardA))
        #expect(a.value.tasks.map(\.title) == ["Bins"])
        #expect(a.value.tasks[0].status == .inProgress)
        #expect(a.value.tasks[0].assigneeId == sam.id)
        #expect(a.value.tasks[0].dueDate == "2026-11-01")
        #expect(a.value.members.map(\.name) == ["Sam"])

        let b = try #require(cache.cachedContents(boardId: boardB))
        #expect(b.value.tasks.map(\.title) == ["Fridge"])
    }

    @Test func clearRemovesEverything() {
        let cache = SwiftDataCache.inMemory()
        let boardId = UUID()
        cache.saveBoards([.sample()])
        cache.saveContents(BoardContents(tasks: [.sample()], members: []), boardId: boardId)

        cache.clear()

        #expect(cache.cachedBoards() == nil)
        #expect(cache.cachedContents(boardId: boardId) == nil)
    }

    // MARK: ViewModels using the cache

    @Test func boardsComeFromCacheWhenOffline() async {
        let cache = SwiftDataCache.inMemory()
        cache.saveBoards([.sample(name: "Home")])
        let service = FakeBoardsService()
        service.error = APIError.offline
        let viewModel = BoardsViewModel(service: service, cache: cache)

        await viewModel.load()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.boards.map(\.name) == ["Home"])
        #expect(viewModel.isOffline)
        #expect(viewModel.cachedAt != nil)
        #expect(viewModel.actionError == nil)
    }

    @Test func successfulLoadUpdatesTheCache() async throws {
        let cache = SwiftDataCache.inMemory()
        cache.saveBoards([.sample(name: "Old")])
        let service = FakeBoardsService()
        service.boards = [.sample(name: "New")]
        let viewModel = BoardsViewModel(service: service, cache: cache)

        await viewModel.load()

        #expect(viewModel.boards.map(\.name) == ["New"])
        #expect(!viewModel.isOffline)
        #expect(try #require(cache.cachedBoards()).value.map(\.name) == ["New"])
    }

    @Test func serverErrorsStillAlertEvenWithCachedData() async {
        let cache = SwiftDataCache.inMemory()
        cache.saveBoards([.sample()])
        let service = FakeBoardsService()
        service.error = APIError.server(statusCode: 500)
        let viewModel = BoardsViewModel(service: service, cache: cache)

        await viewModel.load()

        #expect(viewModel.boards.count == 1)
        #expect(!viewModel.isOffline)
        #expect(viewModel.actionError == APIError.server(statusCode: 500).localizedDescription)
    }

    @Test func tasksAndAssigneesComeFromCacheWhenOffline() async throws {
        let cache = SwiftDataCache.inMemory()
        let board = Board.sample()
        let sam = Member.sample(name: "Sam")
        cache.saveContents(BoardContents(tasks: [.sample(title: "Bins", assigneeId: sam.id)],
                                         members: [sam]),
                           boardId: board.id)
        let service = FakeTasksService()
        service.error = APIError.offline
        let viewModel = TasksViewModel(board: board, service: service, cache: cache)

        await viewModel.load()

        #expect(viewModel.tasks.map(\.title) == ["Bins"])
        let first = try #require(viewModel.tasks.first)   // fails cleanly instead of crashing
        #expect(viewModel.assigneeName(for: first) == "Sam")
        #expect(viewModel.isOffline)
    }

    @Test func statusChangeIsSavedToTheCache() async throws {
        let cache = SwiftDataCache.inMemory()
        let board = Board.sample()
        let task = BoardTask.sample()
        let service = FakeTasksService()
        service.tasks = [task]
        let viewModel = TasksViewModel(board: board, service: service, cache: cache)
        await viewModel.load()

        await viewModel.toggleDone(task)

        let cached = try #require(cache.cachedContents(boardId: board.id))
        #expect(cached.value.tasks.first?.status == .done)
    }
}
