import SwiftUI

@main
struct ChoreBoardApp: App {
    @State private var session: AuthSession
    private let cache: SwiftDataCache

    init() {
        KeychainTokenStore.clearIfFreshInstall()
        _session = State(initialValue: AuthSession())
        cache = SwiftDataCache.onDisk()
    }

    var body: some Scene {
        WindowGroup {
            RootView(cache: cache)
                .environment(session)
        }
    }
}
