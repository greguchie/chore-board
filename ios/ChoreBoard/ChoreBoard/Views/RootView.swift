import SwiftUI

/// Decides what the app shows: Login when logged out, Boards when logged in.
struct RootView: View {
    @Environment(AuthSession.self) private var session

    var body: some View {
        Group {
            if session.isLoggedIn {
                NavigationStack { BoardsListView(service: APIBoardsService(api: .shared)) }
            } else {
                NavigationStack { LoginView(auth: session) }
            }
        }
        .animation(.default, value: session.isLoggedIn)
    }
}
