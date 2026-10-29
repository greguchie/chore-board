import SwiftUI

@main
struct ChoreBoardApp: App {
    @State private var session: AuthSession

    init() {
        KeychainTokenStore.clearIfFreshInstall()
        _session = State(initialValue: AuthSession())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
    }
}
