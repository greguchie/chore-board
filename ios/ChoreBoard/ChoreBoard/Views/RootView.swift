import SwiftUI

/// Decides what the app shows, and owns the navigation path for the logged-in stack.
struct RootView: View {
    @Environment(AuthSession.self) private var session
    @State private var router = AppRouter()

    var body: some View {
        Group {
            if session.isLoggedIn {
                NavigationStack(path: $router.path) {
                    BoardsListView(service: APIBoardsService(api: .shared),
                                   tasksService: APITasksService(api: .shared))
                }
                .environment(router)
            } else {
                NavigationStack { LoginView(auth: session) }
            }
        }
        .animation(.default, value: session.isLoggedIn)
        // Logging in or out always starts from the boards list,
        // never on the previous user's screen.
        .onChange(of: session.isLoggedIn) { router.reset() }
    }
}
