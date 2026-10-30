import Foundation
import Testing
@testable import ChoreBoard

extension BoardTask {
    static func sample(id: UUID = UUID(), title: String = "Take out bins", status: TaskStatus = .todo,
                       assigneeId: UUID? = nil, dueDate: String? = nil,
                       description: String? = nil) -> BoardTask {
        BoardTask(id: id, boardId: UUID(), title: title, description: description, status: status,
                  assigneeId: assigneeId, dueDate: dueDate,
                  completedAt: status == .done ? .now : nil, createdAt: .now, updatedAt: .now)
    }
}

extension Member {
    static func sample(id: UUID = UUID(), name: String = "Sam", role: BoardRole = .member) -> Member {
        Member(id: id, userId: UUID(), role: role, joinedAt: .now, displayName: name, email: nil)
    }
}

@MainActor
final class FakeTasksService: TasksProviding {
    var tasks: [BoardTask] = []
    var members: [Member] = []
    var error: Error?
    private(set) var updateCalls = 0
    private(set) var lastPatch: TaskPatch?
    private(set) var lastDraft: TaskDraft?
    private(set) var deletedIds: [UUID] = []

    func tasks(boardId: UUID) async throws -> [BoardTask] {
        if let error { throw error }
        return tasks
    }

    func members(boardId: UUID) async throws -> [Member] {
        if let error { throw error }
        return members
    }

    func create(boardId: UUID, _ draft: TaskDraft) async throws -> BoardTask {
        lastDraft = draft
        if let error { throw error }
        return .sample(title: draft.title, dueDate: draft.dueDate)
    }

    func update(boardId: UUID, taskId: UUID, with patch: TaskPatch) async throws -> BoardTask {
        updateCalls += 1
        lastPatch = patch
        if let error { throw error }
        let current = tasks.first { $0.id == taskId } ?? .sample(id: taskId)
        return current.withStatus(patch.status ?? current.status)
    }

    func delete(boardId: UUID, taskId: UUID) async throws {
        if let error { throw error }
        deletedIds.append(taskId)
    }
}

@MainActor
struct TasksTests {

    @Test func groupsByStatusAndNamesAssignees() async {
        let sam = Member.sample(name: "Sam")
        let service = FakeTasksService()
        service.members = [sam]
        service.tasks = [.sample(title: "Bins", assigneeId: sam.id),
                         .sample(title: "Dishes", status: .inProgress),
                         .sample(title: "Laundry", status: .done)]
        let viewModel = TasksViewModel(board: .sample(), service: service)

        await viewModel.load()

        #expect(viewModel.state == .loaded)
        #expect(viewModel.tasks(in: .todo).map(\.title) == ["Bins"])
        #expect(viewModel.tasks(in: .inProgress).map(\.title) == ["Dishes"])
        #expect(viewModel.tasks(in: .done).map(\.title) == ["Laundry"])
        #expect(viewModel.assigneeName(for: viewModel.tasks[0]) == "Sam")
        #expect(viewModel.assigneeName(for: viewModel.tasks[1]) == nil)
    }

    @Test func toggleDoneSendsOnlyTheStatus() async {
        let task = BoardTask.sample()
        let service = FakeTasksService()
        service.tasks = [task]
        let viewModel = TasksViewModel(board: .sample(), service: service)
        await viewModel.load()

        await viewModel.toggleDone(task)

        #expect(viewModel.tasks(in: .done).count == 1)
        #expect(viewModel.tasks.first?.completedAt != nil)
        #expect(service.lastPatch == TaskPatch(status: .done))
    }

    @Test func failedStatusChangeRollsBack() async {
        let task = BoardTask.sample()
        let service = FakeTasksService()
        service.tasks = [task]
        let viewModel = TasksViewModel(board: .sample(), service: service)
        await viewModel.load()

        service.error = APIError.offline
        await viewModel.setStatus(task, to: .inProgress)

        #expect(viewModel.tasks.first?.status == .todo)
        #expect(viewModel.actionError == APIError.offline.localizedDescription)
    }

    @Test func membersCannotDeleteTasks() async {
        let task = BoardTask.sample()
        let service = FakeTasksService()
        service.tasks = [task]
        let viewModel = TasksViewModel(board: .sample(role: .member), service: service)
        await viewModel.load()

        await viewModel.delete(task)

        #expect(!viewModel.canDeleteTasks)
        #expect(service.deletedIds.isEmpty)
        #expect(viewModel.tasks.count == 1)
    }

    @Test func adminDeletesTask() async {
        let task = BoardTask.sample()
        let service = FakeTasksService()
        service.tasks = [task]
        let viewModel = TasksViewModel(board: .sample(role: .admin), service: service)
        await viewModel.load()

        await viewModel.delete(task)

        #expect(viewModel.tasks.isEmpty)
        #expect(service.deletedIds == [task.id])
    }

    @Test func patchSendsNullToClearAndOmitsUnchangedFields() throws {
        let patch = TaskPatch(title: "Bins", assigneeId: .clear)
        let data = try JSONCoding.makeEncoder().encode(patch)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json.keys.sorted() == ["assigneeId", "title"])   // dueDate etc. left out
        #expect(json["assigneeId"] is NSNull)                    // explicit null
        #expect(json["title"] as? String == "Bins")
    }

    @Test func editorCreatesTaskWithMemberIdAndCalendarDay() async throws {
        let sam = Member.sample()
        let service = FakeTasksService()
        let viewModel = TaskEditorViewModel(service: service, boardId: UUID(), members: [sam])
        viewModel.title = "  Take out bins  "
        viewModel.assigneeId = sam.id
        viewModel.hasDueDate = true
        viewModel.dueDate = try #require(DueDate.date(from: "2026-11-01"))

        let saved = await viewModel.save()

        #expect(saved != nil)
        #expect(service.lastDraft?.title == "Take out bins")
        #expect(service.lastDraft?.assigneeId == sam.id.apiString)
        #expect(service.lastDraft?.dueDate == "2026-11-01")
        #expect(service.lastDraft?.description == nil)
    }

    @Test func editorSendsOnlyChangedFields() async {
        let sam = Member.sample()
        let existing = BoardTask.sample(assigneeId: sam.id, dueDate: "2026-11-01")
        let service = FakeTasksService()
        let viewModel = TaskEditorViewModel(service: service, boardId: UUID(),
                                            members: [sam], existing: existing)
        #expect(viewModel.assigneeId == sam.id)
        #expect(viewModel.hasDueDate)

        viewModel.assigneeId = nil
        viewModel.hasDueDate = false
        _ = await viewModel.save()

        #expect(service.lastPatch == TaskPatch(assigneeId: .clear, dueDate: .clear))
    }

    @Test func editorWithNoChangesSkipsTheRequest() async {
        let existing = BoardTask.sample(dueDate: "2026-11-01", description: "Blue bin")
        let service = FakeTasksService()
        let viewModel = TaskEditorViewModel(service: service, boardId: UUID(),
                                            members: [], existing: existing)

        let saved = await viewModel.save()

        #expect(saved == existing)
        #expect(service.updateCalls == 0)
    }

    @Test func editorRequiresATitle() async {
        let service = FakeTasksService()
        let viewModel = TaskEditorViewModel(service: service, boardId: UUID(), members: [])
        viewModel.title = "   "

        let saved = await viewModel.save()

        #expect(saved == nil)
        #expect(viewModel.visibleTitleError == "Enter a task title")
        #expect(service.lastDraft == nil)
    }

    @Test func dueDateRoundTripsInLocalCalendar() throws {
        let date = try #require(DueDate.date(from: "2026-11-01"))
        #expect(DueDate.string(from: date) == "2026-11-01")
        #expect(DueDate.date(from: "not-a-date") == nil)
    }
}
