import SwiftUI

/// Decides what the app shows, and owns the navigation path for the logged-in stack.
struct RootView: View {
    @Environment(AuthSession.self) private var session
    @State private var router = AppRouter()
    let cache: any OfflineCaching

    var body: some View {
        Group {
            if session.isLoggedIn {
                NavigationStack(path: $router.path) {
                    BoardsListView(service: APIBoardsService(api: .shared),
                                   tasksService: APITasksService(api: .shared),
                                   cache: cache)
                }
                .environment(router)
            } else {
                NavigationStack { LoginView(auth: session) }
            }
        }
        .animation(.default, value: session.isLoggedIn)
        .onChange(of: session.isLoggedIn) { _, isLoggedIn in
            // Logging in or out always starts from the boards list.
            router.reset()
            // Never show one user's saved chores to the next person.
            if !isLoggedIn { cache.clear() }
        }
    }
}
