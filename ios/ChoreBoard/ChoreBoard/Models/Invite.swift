import Foundation

/// Response from POST /boards/:boardId/invites. The token is shown only once.
nonisolated struct Invite: Decodable, Sendable {
    let token: String
    let url: URL
    let role: BoardRole
    let boardId: UUID
    let expiresAt: Date
}

nonisolated struct CreateInviteRequest: Encodable, Sendable {
    let role: BoardRole
}

/// The token goes in the body, not the URL, so it stays out of server logs.
nonisolated struct AcceptInviteRequest: Encodable, Sendable {
    let token: String
}
