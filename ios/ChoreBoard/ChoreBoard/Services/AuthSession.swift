import Foundation
import Observation

/// Owns the login state: keeps tokens in the Keychain, survives app restarts,
/// and quietly renews the access token when it expires.
@MainActor
@Observable
final class AuthSession: AccessTokenProviding {
    private(set) var isLoggedIn: Bool
    private(set) var currentUser: User? = nil

    private let api: APIClient
    private let store: any TokenStore
    @ObservationIgnored private var tokens: StoredTokens?
    @ObservationIgnored private var refreshTask: Task<String, Error>? = nil

    init(api: APIClient = .shared, store: any TokenStore = KeychainTokenStore()) {
        self.api = api
        self.store = store
        let saved = store.load()
        self.tokens = saved
        self.isLoggedIn = saved != nil
        api.tokenProvider = self
    }

    // MARK: Used by APIClient

    var accessToken: String? { tokens?.accessToken }

    func refreshedAccessToken(after failedToken: String) async throws -> String {
        // Another request already refreshed while this one was in flight: use the new token.
        if let current = tokens?.accessToken, current != failedToken { return current }
        // A refresh is already running: wait for it instead of starting a second one.
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = tokens?.refreshToken else { throw APIError.unauthorized }

        let task = Task { try await self.performRefresh(using: refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    func sessionExpired() {
        endSession()
    }

    // MARK: Login and logout

    func login(email: String, password: String) async throws {
        let response: AuthTokens
        do {
            response = try await api.send(API.login(email: email, password: password), as: AuthTokens.self)
        } catch APIError.unauthorized {
            throw APIError.invalidCredentials   // a wrong password is not an "expired session"
        }
        try save(response)
        currentUser = response.user
    }

    func signUp(email: String, displayName: String, password: String) async throws {
        _ = try await api.send(API.signUp(email: email, displayName: displayName, password: password),
                               as: User.self)
        try await login(email: email, password: password)
    }

    func loadCurrentUser() async throws {
        currentUser = try await api.send(API.me, as: User.self)
    }

    func logout() async {
        // Tell the server to revoke the session. If that fails (offline), log out locally anyway.
        if let refreshToken = tokens?.refreshToken {
            try? await api.sendNoContent(API.logout(refreshToken: refreshToken))
        }
        endSession()
    }

    // MARK: Private

    private func save(_ response: AuthTokens) throws {
        let newTokens = StoredTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
        try store.save(newTokens)
        tokens = newTokens
        isLoggedIn = true
    }

    private func performRefresh(using refreshToken: String) async throws -> String {
        do {
            let response = try await api.send(API.refresh(refreshToken: refreshToken), as: AuthTokens.self)
            try save(response)
            #if DEBUG
            print("[Auth] Access token refreshed")   // never print the token itself
            #endif
            return response.accessToken
        } catch APIError.unauthorized {
            // Refresh token expired or revoked: the session is over.
            endSession()
            throw APIError.unauthorized
        }
        // Any other error (e.g. offline) keeps the session so the user can retry.
    }

    private func endSession() {
        store.clear()
        tokens = nil
        currentUser = nil
        isLoggedIn = false
    }
}
