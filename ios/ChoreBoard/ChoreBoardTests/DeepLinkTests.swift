import Foundation
import Testing
@testable import ChoreBoard

@MainActor
final class FakeInvitesService: InvitesProviding {
    var board = Board.sample(name: "Garage", role: .member)
    var error: Error?
    private(set) var acceptedTokens: [String] = []
    private(set) var createdFor: [UUID] = []

    func createInvite(boardId: UUID) async throws -> Invite {
        createdFor.append(boardId)
        if let error { throw error }
        return Invite(token: "abc123", url: URL(string: "choreboard://invite/abc123")!,
                      role: .member, boardId: boardId, expiresAt: .now.addingTimeInterval(7 * 86_400))
    }

    func accept(token: String) async throws -> Board {
        acceptedTokens.append(token)
        if let error { throw error }
        return board
    }
}

@MainActor
struct DeepLinkTests {
    private func url(_ text: String) -> URL { URL(string: text)! }

    @Test func parsesInviteLinks() {
        #expect(DeepLink(url: url("choreboard://invite/abc_DEF-123")) == .invite(token: "abc_DEF-123"))
        #expect(DeepLink(url: url("CHOREBOARD://INVITE/abc")) == .invite(token: "abc"))
    }

    @Test func rejectsAnythingElse() {
        #expect(DeepLink(url: url("https://example.com/invite/abc")) == nil)   // wrong scheme
        #expect(DeepLink(url: url("choreboard://boards/abc")) == nil)          // wrong host
        #expect(DeepLink(url: url("choreboard://invite/")) == nil)             // no token
        #expect(DeepLink(url: url("choreboard://invite/abc/extra")) == nil)    // extra path
        #expect(DeepLink(url: url("choreboard://invite/abc%20def")) == nil)    // unsafe characters
    }

    @Test func loggedInLinkJoinsAndOpensTheBoard() async {
        let service = FakeInvitesService()
        let router = AppRouter()
        let handler = DeepLinkHandler(service: service, router: router)

        await handler.handle(url("choreboard://invite/abc123"), isLoggedIn: true)

        #expect(service.acceptedTokens == ["abc123"])
        #expect(router.path == [.board(service.board.id)])
        #expect(handler.lastJoinedBoard?.id == service.board.id)
        #expect(handler.status == .idle)
        #expect(handler.pendingInvite == nil)
    }

    @Test func loggedOutLinkWaitsForLogin() async {
        let service = FakeInvitesService()
        let router = AppRouter()
        let handler = DeepLinkHandler(service: service, router: router)

        await handler.handle(url("choreboard://invite/abc123"), isLoggedIn: false)

        #expect(service.acceptedTokens.isEmpty)
        #expect(handler.pendingInvite == "abc123")
        #expect(router.path.isEmpty)

        await handler.acceptPendingInvite()   // what RootView does after login

        #expect(service.acceptedTokens == ["abc123"])
        #expect(router.path == [.board(service.board.id)])
    }

    @Test func expiredInviteExplainsWhatHappened() async {
        let service = FakeInvitesService()
        service.error = APIError.notFound("This invite link is invalid or has expired")
        let router = AppRouter()
        let handler = DeepLinkHandler(service: service, router: router)

        await handler.handle(url("choreboard://invite/old-token"), isLoggedIn: true)

        #expect(handler.errorMessage == "This invite link is invalid or has expired. Ask for a new one.")
        #expect(router.path.isEmpty)
    }

    @Test func unknownLinkShowsAMessage() async {
        let service = FakeInvitesService()
        let handler = DeepLinkHandler(service: service, router: AppRouter())

        await handler.handle(url("choreboard://something-else"), isLoggedIn: true)

        #expect(handler.errorMessage == "That link isn't a Chore Board invite.")
        #expect(service.acceptedTokens.isEmpty)
    }

    @Test func inviteSheetCreatesALink() async {
        let service = FakeInvitesService()
        let boardId = UUID()
        let viewModel = InviteLinkViewModel(boardId: boardId, service: service)

        await viewModel.create()

        #expect(viewModel.link?.absoluteString == "choreboard://invite/abc123")
        #expect(service.createdFor == [boardId])
        #expect(viewModel.errorMessage == nil)
    }

    @Test func inviteSheetShowsErrors() async {
        let service = FakeInvitesService()
        service.error = APIError.forbidden("Your role on this board doesn't allow this")
        let viewModel = InviteLinkViewModel(boardId: UUID(), service: service)

        await viewModel.create()

        #expect(viewModel.link == nil)
        #expect(viewModel.errorMessage == "Your role on this board doesn't allow this")
    }
}
