import Foundation
import Observation

@MainActor
@Observable
final class TaskEditorViewModel {
    var title: String
    var details: String
    var assigneeId: UUID?          // a Member.id
    var hasDueDate: Bool
    var dueDate: Date
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var hasTriedSaving = false

    let existing: BoardTask?
    let members: [Member]
    private let boardId: UUID
    private let service: any TasksProviding

    init(service: any TasksProviding, boardId: UUID, members: [Member], existing: BoardTask? = nil) {
        self.service = service
        self.boardId = boardId
        self.members = members
        self.existing = existing
        self.title = existing?.title ?? ""
        self.details = existing?.description ?? ""
        self.assigneeId = existing?.assigneeId
        self.hasDueDate = existing?.dueDate != nil
        self.dueDate = existing?.dueDate.flatMap { DueDate.date(from: $0) }
            ?? Calendar.current.startOfDay(for: .now)
    }

    var screenTitle: String { existing == nil ? "New task" : "Edit task" }
    var visibleTitleError: String? { hasTriedSaving ? Validation.taskTitleError(title) : nil }
    var visibleDetailsError: String? { hasTriedSaving ? Validation.taskDescriptionError(details) : nil }

    /// Returns the saved task, or nil if validation or the server failed.
    func save() async -> BoardTask? {
        hasTriedSaving = true
        guard !isSaving,
              Validation.taskTitleError(title) == nil,
              Validation.taskDescriptionError(details) == nil else { return nil }

        // Editing with no changes: nothing to send.
        if let existing, makePatch(from: existing).isEmpty { return existing }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if let existing {
                return try await service.update(boardId: boardId, taskId: existing.id,
                                                with: makePatch(from: existing))
            }
            let notes = Validation.trimmed(details)
            let draft = TaskDraft(title: Validation.trimmed(title),
                                  description: notes.isEmpty ? nil : notes,
                                  assigneeId: assigneeId,
                                  dueDate: hasDueDate ? DueDate.string(from: dueDate) : nil)
            return try await service.create(boardId: boardId, draft)
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Only the fields that changed. Cleared fields become null.
    func makePatch(from existing: BoardTask) -> TaskPatch {
        var patch = TaskPatch()

        let newTitle = Validation.trimmed(title)
        if newTitle != existing.title { patch.title = newTitle }

        let newNotes = Validation.trimmed(details)
        if newNotes != (existing.description ?? "") {
            patch.description = newNotes.isEmpty ? .clear : .set(newNotes)
        }

        if assigneeId != existing.assigneeId {
            patch.assigneeId = assigneeId.map { .set($0.apiString) } ?? .clear
        }

        let newDue = hasDueDate ? DueDate.string(from: dueDate) : nil
        if newDue != existing.dueDate {
            patch.dueDate = newDue.map { .set($0) } ?? .clear
        }
        return patch
    }
}
