import SwiftUI

/// Decides what the app shows, owns navigation for the logged-in stack,
/// and receives choreboard:// links.
struct RootView: View {
    @Environment(AuthSession.self) private var session
    @State private var router: AppRouter
    @State private var deepLinks: DeepLinkHandler
    private let cache: any OfflineCaching
    private let invites: any InvitesProviding

    init(cache: any OfflineCaching) {
        self.cache = cache
        let invites = APIInvitesService(api: .shared)
        let router = AppRouter()
        self.invites = invites
        _router = State(initialValue: router)
        _deepLinks = State(initialValue: DeepLinkHandler(service: invites, router: router))
    }

    var body: some View {
        Group {
            if session.isLoggedIn {
                NavigationStack(path: $router.path) {
                    BoardsListView(service: APIBoardsService(api: .shared),
                                   tasksService: APITasksService(api: .shared),
                                   cache: cache,
                                   invites: invites)
                }
                .environment(router)
                .environment(deepLinks)
            } else {
                NavigationStack { LoginView(auth: session) }
                    .safeAreaInset(edge: .bottom) {
                        if deepLinks.pendingInvite != nil {
                            Label("Log in or create an account to join the board you were invited to.",
                                  systemImage: "envelope.open")
                                .font(.footnote)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(.thinMaterial)
                        }
                    }
            }
        }
        .animation(.default, value: session.isLoggedIn)
        .overlay {
            if deepLinks.status == .joining {
                ProgressView("Joining board…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Couldn't join the board",
               isPresented: Binding(get: { deepLinks.errorMessage != nil },
                                    set: { if !$0 { deepLinks.dismissError() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deepLinks.errorMessage ?? "")
        }
        .onOpenURL { url in
            Task { await deepLinks.handle(url, isLoggedIn: session.isLoggedIn) }
        }
        .onChange(of: session.isLoggedIn) { _, isLoggedIn in
            // Logging in or out always starts from the boards list.
            router.reset()
            if isLoggedIn {
                // An invite that arrived while logged out.
                Task { await deepLinks.acceptPendingInvite() }
            } else {
                // Never show one user's saved chores to the next person.
                cache.clear()
            }
        }
    }
}
