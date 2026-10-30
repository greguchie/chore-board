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
    /// True when the server can't be reached and the list is the saved copy.
    private(set) var isOffline = false
    private(set) var cachedAt: Date?
    /// A failed refresh or delete. Shown as an alert while the list stays visible.
    var actionError: String?

    private let service: any BoardsProviding
    private let cache: (any OfflineCaching)?

    init(service: any BoardsProviding, cache: (any OfflineCaching)? = nil) {
        self.service = service
        self.cache = cache
    }

    /// Stale-while-revalidate: show the saved copy at once, then refresh.
    func load() async {
        if state == .loading, let cached = cache?.cachedBoards() {
            boards = cached.value
            state = .loaded
        }
        do {
            boards = try await service.list()
            state = .loaded
            markOnline()
        } catch is CancellationError {
        } catch APIError.offline where state == .loaded {
            // Offline but we have something to show: a banner, not an alert.
            isOffline = true
            cachedAt = cache?.cachedBoards()?.savedAt
        } catch {
            if state == .loaded {
                actionError = error.localizedDescription      // keep the list, show an alert
            } else {
                state = .failed(error.localizedDescription)   // nothing to show: full-screen error
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
        markOnline()
    }

    /// Optimistic: remove the row right away, put it back if the server refuses.
    func delete(_ board: Board) async {
        guard board.myRole.canDeleteBoard else { return }
        let previous = boards
        boards.removeAll { $0.id == board.id }
        do {
            try await service.delete(board.id)
            markOnline()
        } catch {
            boards = previous
            actionError = error.localizedDescription
        }
    }

    /// A successful server response: clear the banner and save what's on screen.
    private func markOnline() {
        isOffline = false
        cachedAt = nil
        cache?.saveBoards(boards)
    }
}
