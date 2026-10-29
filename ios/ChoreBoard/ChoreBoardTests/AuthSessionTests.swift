import Foundation
import Testing
@testable import ChoreBoard

/// A pretend API server, so session logic can be tested without a network.
@MainActor
final class FakeServer {
    enum RefreshResult { case success, rejected, offline }
    var refreshResult: RefreshResult = .success
    private(set) var refreshCalls = 0
    private(set) var logoutCalls = 0

    private let userJSON = #"{"id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b","email":"greg@example.test","displayName":"Greg","createdAt":"2026-10-20T10:00:00.000Z","updatedAt":"2026-10-20T10:00:00.000Z"}"#
    private let loginJSON = #"{"accessToken":"new-access","refreshToken":"new-refresh","tokenType":"Bearer","accessTokenExpiresIn":"15m","user":{"id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b","email":"greg@example.test","displayName":"Greg"}}"#
    private let refreshJSON = #"{"accessToken":"new-access","refreshToken":"new-refresh","tokenType":"Bearer","accessTokenExpiresIn":"15m"}"#

    func handle(_ request: URLRequest) async throws -> (Data, URLResponse) {
        await Task.yield()   // like a real network: let other requests run meanwhile

        switch request.url?.path() ?? "" {
        case "/auth/login":
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: String]
            return body?["password"] == "right-password"
                ? reply(200, loginJSON, request)
                : reply(401, #"{"error":"Invalid email or password"}"#, request)
        case "/auth/refresh":
            refreshCalls += 1
            switch refreshResult {
            case .success: return reply(200, refreshJSON, request)
            case .rejected: return reply(401, #"{"error":"Invalid refresh token"}"#, request)
            case .offline: throw URLError(.cannotConnectToHost)
            }
        case "/auth/logout":
            logoutCalls += 1
            return reply(204, "", request)
        case "/users/me":
            let valid = request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access"
            return valid
                ? reply(200, userJSON, request)
                : reply(401, #"{"error":"Invalid or expired token"}"#, request)
        default:
            return reply(404, #"{"error":"Not found"}"#, request)
        }
    }

    private func reply(_ status: Int, _ json: String, _ request: URLRequest) -> (Data, URLResponse) {
        (Data(json.utf8),
         HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
struct AuthSessionTests {
    private let oldTokens = StoredTokens(accessToken: "old-access", refreshToken: "old-refresh")

    private func makeClient(_ server: FakeServer) -> APIClient {
        APIClient(baseURL: URL(string: "http://example.test")!,
                  transport: { try await server.handle($0) })
    }

    @Test func loginStoresTokensAndUser() async throws {
        let server = FakeServer()
        let store = InMemoryTokenStore()
        let session = AuthSession(api: makeClient(server), store: store)
        #expect(!session.isLoggedIn)

        try await session.login(email: "greg@example.test", password: "right-password")

        #expect(session.isLoggedIn)
        #expect(session.currentUser?.displayName == "Greg")
        #expect(store.load()?.refreshToken == "new-refresh")
    }

    @Test func wrongPasswordGivesClearError() async {
        let session = AuthSession(api: makeClient(FakeServer()), store: InMemoryTokenStore())

        await #expect(throws: APIError.invalidCredentials) {
            try await session.login(email: "greg@example.test", password: "wrong")
        }
        #expect(!session.isLoggedIn)
    }

    @Test func expiredAccessTokenIsRefreshedOnceAndRetried() async throws {
        let server = FakeServer()
        let api = makeClient(server)
        let store = InMemoryTokenStore(oldTokens)
        let session = AuthSession(api: api, store: store)

        let user = try await api.send(API.me, as: User.self)

        #expect(user.displayName == "Greg")
        #expect(server.refreshCalls == 1)
        #expect(store.load()?.refreshToken == "new-refresh")
        #expect(session.isLoggedIn)
    }

    @Test func simultaneousFailuresShareOneRefresh() async throws {
        let server = FakeServer()
        let api = makeClient(server)
        let session = AuthSession(api: api, store: InMemoryTokenStore(oldTokens))

        async let first = api.send(API.me, as: User.self)
        async let second = api.send(API.me, as: User.self)
        let users = try await [first, second]

        #expect(users.count == 2)
        #expect(server.refreshCalls == 1)   // two would trip the server's reuse alarm
        #expect(session.isLoggedIn)
    }

    @Test func rejectedRefreshEndsSession() async {
        let server = FakeServer()
        server.refreshResult = .rejected
        let api = makeClient(server)
        let store = InMemoryTokenStore(oldTokens)
        let session = AuthSession(api: api, store: store)

        await #expect(throws: APIError.unauthorized) {
            _ = try await api.send(API.me, as: User.self)
        }
        #expect(!session.isLoggedIn)
        #expect(store.load() == nil)
    }

    @Test func offlineDuringRefreshKeepsSession() async {
        let server = FakeServer()
        server.refreshResult = .offline
        let api = makeClient(server)
        let store = InMemoryTokenStore(oldTokens)
        let session = AuthSession(api: api, store: store)

        await #expect(throws: APIError.offline) {
            _ = try await api.send(API.me, as: User.self)
        }
        #expect(session.isLoggedIn)          // a subway tunnel shouldn't log you out
        #expect(store.load() == oldTokens)
    }

    @Test func logoutRevokesOnServerAndClearsTokens() async {
        let server = FakeServer()
        let store = InMemoryTokenStore(oldTokens)
        let session = AuthSession(api: makeClient(server), store: store)

        await session.logout()

        #expect(server.logoutCalls == 1)
        #expect(!session.isLoggedIn)
        #expect(store.load() == nil)
    }

    @Test func keychainSavesUpdatesAndClears() throws {
        let store = KeychainTokenStore(service: "com.greguchie.ChoreBoard.tests")
        store.clear()
        #expect(store.load() == nil)

        try store.save(StoredTokens(accessToken: "a1", refreshToken: "r1"))
        #expect(store.load() == StoredTokens(accessToken: "a1", refreshToken: "r1"))

        try store.save(StoredTokens(accessToken: "a2", refreshToken: "r2"))   // update path
        #expect(store.load()?.refreshToken == "r2")

        store.clear()
        #expect(store.load() == nil)
    }
}
