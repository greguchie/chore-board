import Foundation
import Testing
@testable import ChoreBoard

@MainActor
struct NavigationTests {

    @Test func openPushesRoutesInOrder() {
        let router = AppRouter()
        let first = UUID(), second = UUID()

        router.open(.board(first))
        router.open(.board(second))

        #expect(router.path == [.board(first), .board(second)])
    }

    @Test func showBoardReplacesTheWholeStack() {
        let router = AppRouter()
        router.open(.board(UUID()))
        router.open(.board(UUID()))
        let target = UUID()

        router.showBoard(target)

        #expect(router.path == [.board(target)])
    }

    @Test func resetClearsHistory() {
        let router = AppRouter()
        router.open(.board(UUID()))

        router.reset()

        #expect(router.path.isEmpty)
    }

    @Test func routesSurviveEncoding() throws {
        let path: [Route] = [.board(UUID())]
        let data = try JSONEncoder().encode(path)
        #expect(try JSONDecoder().decode([Route].self, from: data) == path)
    }

    @Test func cachedBoardOpensWithoutARequest() async {
        let board = Board.sample()
        let service = FakeBoardsService()
        let viewModel = BoardRouteViewModel(boardId: board.id, cached: board, service: service)

        await viewModel.load()

        #expect(viewModel.state == .loaded(board))
        #expect(service.boardRequests == 0)
    }

    @Test func missingBoardIsFetchedById() async {
        let board = Board.sample()
        let service = FakeBoardsService()
        service.boards = [board]
        let viewModel = BoardRouteViewModel(boardId: board.id, cached: nil, service: service)
        #expect(viewModel.state == .loading)

        await viewModel.load()

        #expect(viewModel.state == .loaded(board))
        #expect(service.boardRequests == 1)
    }

    @Test func unknownBoardShowsNotFound() async {
        let service = FakeBoardsService()
        let viewModel = BoardRouteViewModel(boardId: UUID(), cached: nil, service: service)

        await viewModel.load()

        #expect(viewModel.state == .notFound)
    }

    @Test func offlineErrorCanBeRetried() async {
        let board = Board.sample()
        let service = FakeBoardsService()
        service.error = APIError.offline
        let viewModel = BoardRouteViewModel(boardId: board.id, cached: nil, service: service)

        await viewModel.load()
        #expect(viewModel.state == .failed(APIError.offline.localizedDescription))

        service.error = nil
        service.boards = [board]
        await viewModel.load()
        #expect(viewModel.state == .loaded(board))
    }
}
