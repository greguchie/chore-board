import Foundation
import Observation

/// Every screen the logged-in stack can push. Routes carry ids, never whole
/// models: a route can be built from a URL or a notification, stays valid if
/// the board changes, and is Codable for state restoration.
nonisolated enum Route: Hashable, Codable, Sendable {
    case board(UUID)
}

/// Owns the logged-in navigation path. Screens ask the router to navigate
/// instead of pushing views themselves.
@MainActor
@Observable
final class AppRouter {
    var path: [Route] = []

    func open(_ route: Route) {
        path.append(route)
    }

    /// Jump straight to a board from anywhere: invite links (Step 9)
    /// and push notification taps (Phase 4).
    func showBoard(_ id: UUID) {
        path = [.board(id)]
    }

    func reset() {
        path.removeAll()
    }
}
