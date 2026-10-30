import Foundation
import SwiftData

/// A cached value and when it was saved.
nonisolated struct Cached<Value: Sendable>: Sendable {
    let value: Value
    let savedAt: Date
}

/// Everything the board screen shows.
nonisolated struct BoardContents: Equatable, Sendable {
    let tasks: [BoardTask]
    let members: [Member]
}

/// What the ViewModels need from the offline cache.
@MainActor
protocol OfflineCaching: AnyObject {
    func cachedBoards() -> Cached<[Board]>?
    func saveBoards(_ boards: [Board])
    func cachedContents(boardId: UUID) -> Cached<BoardContents>?
    func saveContents(_ contents: BoardContents, boardId: UUID)
    func clear()
}

@MainActor
final class SwiftDataCache: OfflineCaching {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    private init(container: ModelContainer) {
        self.container = container
    }

    /// The app's cache, saved in Application Support/OfflineCache.store.
    static func onDisk() -> SwiftDataCache { make(name: "OfflineCache", inMemory: false) }

    /// A throwaway cache for tests; each one is independent.
    static func inMemory() -> SwiftDataCache { make(name: UUID().uuidString, inMemory: true) }

    private static func make(name: String, inMemory: Bool) -> SwiftDataCache {
        let schema = Schema([CachedBoard.self, CachedTask.self, CachedMember.self, CacheStamp.self])
        do {
            let config = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: inMemory)
            return SwiftDataCache(container: try ModelContainer(for: schema, configurations: config))
        } catch {
            // A cache is disposable: if the store can't open, run with memory only.
            print("[Cache] Couldn't open the store, using memory instead: \(error)")
            let fallback = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
            return SwiftDataCache(container: try! ModelContainer(for: schema, configurations: fallback))
        }
    }

    // MARK: Boards

    func cachedBoards() -> Cached<[Board]>? {
        guard let savedAt = stamp(for: Self.boardsKey) else { return nil }
        let rows = fetch(FetchDescriptor<CachedBoard>(sortBy: [SortDescriptor(\.position)]))
        return Cached(value: rows.compactMap { $0.board }, savedAt: savedAt)
    }

    func saveBoards(_ boards: [Board]) {
        deleteAll(FetchDescriptor<CachedBoard>())
        for (index, board) in boards.enumerated() {
            context.insert(CachedBoard(board, position: index))
        }
        setStamp(Self.boardsKey)
        persist()
    }

    // MARK: Tasks and members of one board

    func cachedContents(boardId: UUID) -> Cached<BoardContents>? {
        guard let savedAt = stamp(for: Self.contentsKey(boardId)) else { return nil }
        let id = boardId
        let tasks = fetch(FetchDescriptor<CachedTask>(predicate: #Predicate { $0.boardId == id },
                                                      sortBy: [SortDescriptor(\.position)]))
        let members = fetch(FetchDescriptor<CachedMember>(predicate: #Predicate { $0.boardId == id },
                                                          sortBy: [SortDescriptor(\.position)]))
        return Cached(value: BoardContents(tasks: tasks.compactMap { $0.task },
                                           members: members.compactMap { $0.member }),
                      savedAt: savedAt)
    }

    func saveContents(_ contents: BoardContents, boardId: UUID) {
        let id = boardId
        deleteAll(FetchDescriptor<CachedTask>(predicate: #Predicate { $0.boardId == id }))
        deleteAll(FetchDescriptor<CachedMember>(predicate: #Predicate { $0.boardId == id }))
        for (index, task) in contents.tasks.enumerated() {
            context.insert(CachedTask(task, boardId: boardId, position: index))
        }
        for (index, member) in contents.members.enumerated() {
            context.insert(CachedMember(member, boardId: boardId, position: index))
        }
        setStamp(Self.contentsKey(boardId))
        persist()
    }

    // MARK: Logout

    func clear() {
        deleteAll(FetchDescriptor<CachedBoard>())
        deleteAll(FetchDescriptor<CachedTask>())
        deleteAll(FetchDescriptor<CachedMember>())
        deleteAll(FetchDescriptor<CacheStamp>())
        persist()
    }

    // MARK: Helpers

    private static let boardsKey = "boards"
    private static func contentsKey(_ boardId: UUID) -> String { "board-\(boardId.uuidString)" }

    private func stamp(for key: String) -> Date? {
        fetch(FetchDescriptor<CacheStamp>(predicate: #Predicate { $0.key == key })).first?.savedAt
    }

    private func setStamp(_ key: String) {
        deleteAll(FetchDescriptor<CacheStamp>(predicate: #Predicate { $0.key == key }))
        context.insert(CacheStamp(key: key, savedAt: .now))
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func deleteAll<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) {
        for item in fetch(descriptor) { context.delete(item) }
    }

    /// Best effort: a failed cache write must never break the app.
    private func persist() {
        do {
            try context.save()
        } catch {
            print("[Cache] Save failed: \(error)")
        }
    }
}
