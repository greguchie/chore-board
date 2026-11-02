import Foundation

extension API {
    static func createInvite(boardId: UUID, role: BoardRole = .member) -> Endpoint {
        Endpoint(method: .post, path: "boards/\(boardId.apiString)/invites",
                 body: CreateInviteRequest(role: role))
    }

    static func acceptInvite(token: String) -> Endpoint {
        Endpoint(method: .post, path: "invites/accept", body: AcceptInviteRequest(token: token))
    }
}

/// What the invite features need from the backend. Tests use a fake.
@MainActor
protocol InvitesProviding: AnyObject {
    func createInvite(boardId: UUID) async throws -> Invite
    func accept(token: String) async throws -> Board
}

@MainActor
final class APIInvitesService: InvitesProviding {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func createInvite(boardId: UUID) async throws -> Invite {
        try await api.send(API.createInvite(boardId: boardId), as: Invite.self)
    }

    func accept(token: String) async throws -> Board {
        try await api.send(API.acceptInvite(token: token), as: Board.self)
    }
}
