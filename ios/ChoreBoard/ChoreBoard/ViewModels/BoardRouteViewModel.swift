import Foundation
import Observation

/// Resolves a .board(id) route into a Board: uses the one already loaded
/// if there is one, otherwise fetches it from the server.
@MainActor
@Observable
final class BoardRouteViewModel {
    enum State: Equatable {
        case loading
        case loaded(Board)
        case notFound
        case failed(String)
    }

    private(set) var state: State
    let boardId: UUID
    private let service: any BoardsProviding

    init(boardId: UUID, cached: Board?, service: any BoardsProviding) {
        self.boardId = boardId
        self.service = service
        self.state = cached.map { .loaded($0) } ?? .loading
    }

    func load() async {
        if case .loaded = state { return }
        state = .loading
        do {
            state = .loaded(try await service.board(boardId))
        } catch is CancellationError {
        } catch APIError.notFound {
            // The server answers 404 both for deleted boards and for boards
            // you're not a member of, so we never reveal which.
            state = .notFound
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
