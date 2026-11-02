import Foundation
import Observation

/// Links the app understands. Links come from outside the app, so they're
/// parsed strictly and treated as untrusted input.
nonisolated enum DeepLink: Equatable, Sendable {
    case invite(token: String)

    /// Accepts only choreboard://invite/<token>, where the token is
    /// 1 to 200 URL-safe characters (letters, digits, - and _).
    init?(url: URL) {
        guard url.scheme?.lowercased() == "choreboard",
              url.host?.lowercased() == "invite" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let token = parts.first,
              (1...200).contains(token.count),
              token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        self = .invite(token: token)
    }
}

/// Receives links, joins boards, and navigates with the app router.
@MainActor
@Observable
final class DeepLinkHandler {
    enum Status: Equatable {
        case idle
        case joining
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// A link that arrived while logged out, used straight after login.
    private(set) var pendingInvite: String?
    /// The board most recently joined, so the boards list can add it.
    private(set) var lastJoinedBoard: Board?

    private let service: any InvitesProviding
    private let router: AppRouter

    init(service: any InvitesProviding, router: AppRouter) {
        self.service = service
        self.router = router
    }

    var errorMessage: String? {
        if case .failed(let message) = status { return message }
        return nil
    }

    func handle(_ url: URL, isLoggedIn: Bool) async {
        guard case .invite(let token)? = DeepLink(url: url) else {
            status = .failed("That link isn't a Chore Board invite.")
            return
        }
        pendingInvite = token
        if isLoggedIn {
            await acceptPendingInvite()
        }
    }

    func acceptPendingInvite() async {
        guard let token = pendingInvite, status != .joining else { return }
        pendingInvite = nil
        status = .joining
        do {
            let board = try await service.accept(token: token)
            lastJoinedBoard = board
            status = .idle
            router.showBoard(board.id)
        } catch APIError.notFound {
            status = .failed("This invite link is invalid or has expired. Ask for a new one.")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func dismissError() {
        status = .idle
    }
}
