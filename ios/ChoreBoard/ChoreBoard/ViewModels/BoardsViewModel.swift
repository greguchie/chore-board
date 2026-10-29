import Foundation
import Observation

@MainActor
@Observable
final class BoardsViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var boards: [Board] = []
    private(set) var state: State = .loading
    /// A failed refresh or delete. Shown as an alert while the list stays visible.
    var actionError: String?

    private let service: any BoardsProviding

    init(service: any BoardsProviding) {
        self.service = service
    }

    func load() async {
        do {
            boards = try await service.list()
            state = .loaded
        } catch is CancellationError {
        } catch {
            if boards.isEmpty {
                state = .failed(error.localizedDescription)   // nothing to show: full-screen error
            } else {
                actionError = error.localizedDescription       // keep the list, show an alert
            }
        }
    }

    func retry() async {
        state = .loading
        await load()
    }

    /// After the editor saves: replace the board if it's listed, otherwise add it.
    func upsert(_ board: Board) {
        if let index = boards.firstIndex(where: { $0.id == board.id }) {
            boards[index] = board
        } else {
            boards.append(board)
        }
        state = .loaded
    }

    /// Optimistic: remove the row right away, put it back if the server refuses.
    func delete(_ board: Board) async {
        guard board.myRole.canDeleteBoard else { return }
        let previous = boards
        boards.removeAll { $0.id == board.id }
        do {
            try await service.delete(board.id)
        } catch {
            boards = previous
            actionError = error.localizedDescription
        }
    }
}
