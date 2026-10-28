import Foundation
import Testing
@testable import ChoreBoard

struct APIDecodingTests {

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONCoding.makeDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func readsDatesWithMilliseconds() throws {
        let health = try decode(HealthStatus.self,
            from: #"{"status":"ok","dbTime":"2026-10-28T19:38:50.214Z"}"#)
        #expect(abs(health.dbTime.timeIntervalSince1970 - 1_793_216_330.214) < 0.001)
    }

    @Test func readsBoardWithRoleAndNullDescription() throws {
        let board = try decode(Board.self, from: """
            {"id":"8d6f5a1e-2b3c-4d5e-8f90-1a2b3c4d5e6f","name":"Home","description":null,
             "ownerId":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b",
             "createdAt":"2026-10-20T10:00:00.000Z","updatedAt":"2026-10-20T10:00:00.000Z",
             "myRole":"admin"}
            """)
        #expect(board.name == "Home")
        #expect(board.description == nil)
        #expect(board.myRole == .admin)
    }

    @Test func readsTaskStatusAndCalendarDueDate() throws {
        let task = try decode(BoardTask.self, from: """
            {"id":"6a7b8c9d-0e1f-4a2b-9c3d-4e5f6a7b8c9d",
             "boardId":"8d6f5a1e-2b3c-4d5e-8f90-1a2b3c4d5e6f",
             "title":"Take out bins","description":null,"status":"in_progress",
             "assigneeId":null,"dueDate":"2026-11-01","completedAt":null,
             "createdAt":"2026-10-20T10:00:00.000Z","updatedAt":"2026-10-21T08:30:00.000Z"}
            """)
        #expect(task.status == .inProgress)
        #expect(task.dueDate == "2026-11-01")
        #expect(task.assigneeId == nil)
    }

    @Test func readsMemberListRow() throws {
        let member = try decode(Member.self, from: """
            {"id":"2c3d4e5f-6a7b-4c8d-9e0f-1a2b3c4d5e6f",
             "userId":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b",
             "displayName":"Greg","email":"greg@example.test",
             "role":"owner","joinedAt":"2026-10-20T10:00:00.000Z"}
            """)
        #expect(member.role == .owner)
        #expect(member.displayName == "Greg")
    }

    @Test func readsLoginResponseWithUser() throws {
        let tokens = try decode(AuthTokens.self, from: """
            {"accessToken":"a.b.c","refreshToken":"r-token","tokenType":"Bearer",
             "accessTokenExpiresIn":"15m",
             "user":{"id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b",
                     "email":"greg@example.test","displayName":"Greg"}}
            """)
        #expect(tokens.user?.displayName == "Greg")
        #expect(tokens.user?.createdAt == nil)
    }

    @Test func turnsHTTPStatusesIntoAPIErrors() {
        let body = Data(#"{"error":"Your role on this board doesn't allow this"}"#.utf8)
        #expect(APIError(statusCode: 403, body: body) == .forbidden("Your role on this board doesn't allow this"))
        #expect(APIError(statusCode: 401, body: Data()) == .unauthorized)
        #expect(APIError(statusCode: 404, body: Data()) == .notFound("Not found"))
        #expect(APIError(statusCode: 429, body: Data()) == .rateLimited)
        #expect(APIError(statusCode: 503, body: Data()) == .server(statusCode: 503))
    }

    @Test func treatsUnreachableServerAsOffline() {
        #expect(APIError(urlError: URLError(.cannotConnectToHost)) == .offline)
        #expect(APIError(urlError: URLError(.notConnectedToInternet)) == .offline)
    }

    @Test @MainActor func buildsAuthorizedRequestWithLowercaseIds() throws {
        let client = APIClient(baseURL: URL(string: "http://example.test")!)
        client.accessTokenProvider = { "test-token" }
        let boardId = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!

        let request = try client.makeRequest(for: API.tasks(boardId: boardId, status: .inProgress))

        #expect(request.url?.absoluteString ==
            "http://example.test/boards/3f2504e0-4f89-41d3-9a0c-0305e82c3301/tasks?status=in_progress")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test @MainActor func refusesProtectedRequestWithoutToken() {
        let client = APIClient(baseURL: URL(string: "http://example.test")!)
        #expect(throws: APIError.unauthorized) {
            try client.makeRequest(for: API.boards)
        }
    }

    @Test @MainActor func sendsLoginAsJSONWithoutToken() throws {
        let client = APIClient(baseURL: URL(string: "http://example.test")!)
        let request = try client.makeRequest(for: API.login(email: "a@b.test", password: "pw"))

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        #expect(body == ["email": "a@b.test", "password": "pw"])
    }
}
