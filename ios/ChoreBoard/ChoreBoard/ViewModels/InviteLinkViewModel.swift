import Foundation
import Observation

@MainActor
@Observable
final class InviteLinkViewModel {
    private(set) var link: URL?
    private(set) var isCreating = false
    private(set) var errorMessage: String?

    private let boardId: UUID
    private let service: any InvitesProviding

    init(boardId: UUID, service: any InvitesProviding) {
        self.boardId = boardId
        self.service = service
    }

    func create() async {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            link = try await service.createInvite(boardId: boardId).url
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
