import Foundation
import Observation

@MainActor
@Observable
final class TasksViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let board: Board
    private(set) var tasks: [BoardTask] = []
    private(set) var members: [Member] = []
    private(set) var state: State = .loading
    /// True when the server can't be reached and the tasks are the saved copy.
    private(set) var isOffline = false
    private(set) var cachedAt: Date?
    /// A failed refresh, status change or delete. Shown as an alert; the list stays.
    var actionError: String?

    private let service: any TasksProviding
    private let cache: (any OfflineCaching)?

    init(board: Board, service: any TasksProviding, cache: (any OfflineCaching)? = nil) {
        self.board = board
        self.service = service
        self.cache = cache
    }

    /// Owners and admins can delete tasks, matching the server's rule.
    var canDeleteTasks: Bool { board.myRole.canEditBoard }

    func tasks(in status: TaskStatus) -> [BoardTask] {
        tasks.filter { $0.status == status }
    }

    func assigneeName(for task: BoardTask) -> String? {
        guard let id = task.assigneeId else { return nil }
        return members.first { $0.id == id }?.name
    }

    /// Stale-while-revalidate: show the saved copy at once, then refresh.
    func load() async {
        if state == .loading, let cached = cache?.cachedContents(boardId: board.id) {
            tasks = cached.value.tasks
            members = cached.value.members
            state = .loaded
        }
        do {
            let newTasks = try await service.tasks(boardId: board.id)
            let newMembers = try await service.members(boardId: board.id)
            tasks = newTasks
            members = newMembers
            state = .loaded
            markOnline()
        } catch is CancellationError {
        } catch APIError.offline where state == .loaded {
            isOffline = true
            cachedAt = cache?.cachedContents(boardId: board.id)?.savedAt
        } catch {
            if state == .loaded {
                actionError = error.localizedDescription      // keep what's on screen
            } else {
                state = .failed(error.localizedDescription)   // nothing to show yet
            }
        }
    }

    func retry() async {
        state = .loading
        await load()
    }

    /// After the editor saves: replace the task if it's listed, otherwise add it.
    func upsert(_ task: BoardTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        markOnline()
    }

    func toggleDone(_ task: BoardTask) async {
        await setStatus(task, to: task.status == .done ? .todo : .done)
    }

    /// Optimistic: move the task right away, put it back if the server refuses.
    /// Writes need a connection; offline, this rolls back with an alert.
    func setStatus(_ task: BoardTask, to status: TaskStatus) async {
        guard task.status != status,
              let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previous = tasks[index]
        tasks[index] = previous.withStatus(status)

        do {
            let saved = try await service.update(boardId: board.id, taskId: task.id,
                                                 with: TaskPatch(status: status))
            upsert(saved)   // the server's version, with its real completedAt
        } catch {
            if let current = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[current] = previous
            }
            actionError = error.localizedDescription
        }
    }

    /// Optimistic delete with rollback, same as boards.
    func delete(_ task: BoardTask) async {
        guard canDeleteTasks, let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let removed = tasks.remove(at: index)
        do {
            try await service.delete(boardId: board.id, taskId: task.id)
            markOnline()
        } catch {
            tasks.insert(removed, at: min(index, tasks.count))
            actionError = error.localizedDescription
        }
    }

    /// A successful server response: clear the banner and save what's on screen.
    private func markOnline() {
        isOffline = false
        cachedAt = nil
        cache?.saveContents(BoardContents(tasks: tasks, members: members), boardId: board.id)
    }
}
