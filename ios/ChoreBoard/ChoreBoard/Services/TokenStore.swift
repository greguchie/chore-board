import Foundation

nonisolated struct StoredTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
}

/// Where tokens are kept. The app uses the Keychain; tests use memory.
@MainActor
protocol TokenStore: AnyObject {
    func load() -> StoredTokens?
    func save(_ tokens: StoredTokens) throws
    func clear()
}

@MainActor
final class InMemoryTokenStore: TokenStore {
    private var tokens: StoredTokens?

    init(_ tokens: StoredTokens? = nil) {
        self.tokens = tokens
    }

    func load() -> StoredTokens? { tokens }
    func save(_ tokens: StoredTokens) throws { self.tokens = tokens }
    func clear() { tokens = nil }
}
