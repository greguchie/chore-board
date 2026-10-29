import Foundation
import Observation

@MainActor
@Observable
final class BoardEditorViewModel {
    var name: String
    var details: String
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var hasTriedSaving = false

    let existing: Board?
    private let service: any BoardsProviding

    init(service: any BoardsProviding, existing: Board? = nil) {
        self.service = service
        self.existing = existing
        self.name = existing?.name ?? ""
        self.details = existing?.description ?? ""
    }

    var title: String { existing == nil ? "New board" : "Edit board" }
    var visibleNameError: String? { hasTriedSaving ? Validation.boardNameError(name) : nil }
    var visibleDetailsError: String? { hasTriedSaving ? Validation.boardDescriptionError(details) : nil }

    /// Returns the saved board, or nil if validation or the server failed.
    func save() async -> Board? {
        hasTriedSaving = true
        guard !isSaving,
              Validation.boardNameError(name) == nil,
              Validation.boardDescriptionError(details) == nil else { return nil }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let draft = BoardDraft(name: Validation.trimmed(name), description: descriptionToSend)
        do {
            if let existing {
                return try await service.update(existing.id, with: draft)
            }
            return try await service.create(draft)
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Empty means "no description". But the server's PATCH treats null as
    /// "leave unchanged", so clearing an existing description must send "".
    private var descriptionToSend: String? {
        let value = Validation.trimmed(details)
        if !value.isEmpty { return value }
        let hadDescription = !(existing?.description ?? "").isEmpty
        return hadDescription ? "" : nil
    }
}
