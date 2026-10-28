import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE"
}

nonisolated struct Endpoint: Sendable {
    var method: HTTPMethod = .get
    var path: String
    var query: [URLQueryItem] = []
    var body: (any Encodable & Sendable)? = nil
    var requiresAuth = true
}

extension UUID {
    /// The API compares ids in lowercase; Swift prints them in UPPERCASE.
    nonisolated var apiString: String { uuidString.lowercased() }
}

nonisolated enum API {
    // MARK: Health and auth (public)
    static var health: Endpoint {
        Endpoint(path: "health", requiresAuth: false)
    }
    static func login(email: String, password: String) -> Endpoint {
        Endpoint(method: .post, path: "auth/login",
                 body: LoginRequest(email: email, password: password), requiresAuth: false)
    }
    static func signUp(email: String, displayName: String, password: String) -> Endpoint {
        Endpoint(method: .post, path: "users",
                 body: SignUpRequest(email: email, displayName: displayName, password: password),
                 requiresAuth: false)
    }
    static func refresh(refreshToken: String) -> Endpoint {
        Endpoint(method: .post, path: "auth/refresh",
                 body: RefreshRequest(refreshToken: refreshToken), requiresAuth: false)
    }
    static func logout(refreshToken: String) -> Endpoint {
        Endpoint(method: .post, path: "auth/logout",
                 body: RefreshRequest(refreshToken: refreshToken), requiresAuth: false)
    }

    // MARK: Current user
    static var me: Endpoint { Endpoint(path: "users/me") }

    // MARK: Boards
    static var boards: Endpoint { Endpoint(path: "boards") }
    static func board(_ id: UUID) -> Endpoint {
        Endpoint(path: "boards/\(id.apiString)")
    }
    static func createBoard(_ draft: BoardDraft) -> Endpoint {
        Endpoint(method: .post, path: "boards", body: draft)
    }
    static func updateBoard(_ id: UUID, _ draft: BoardDraft) -> Endpoint {
        Endpoint(method: .patch, path: "boards/\(id.apiString)", body: draft)
    }
    static func deleteBoard(_ id: UUID) -> Endpoint {
        Endpoint(method: .delete, path: "boards/\(id.apiString)")
    }

    // MARK: Members
    static func members(boardId: UUID) -> Endpoint {
        Endpoint(path: "boards/\(boardId.apiString)/members")
    }
    static func addMember(boardId: UUID, userId: UUID, role: BoardRole = .member) -> Endpoint {
        Endpoint(method: .post, path: "boards/\(boardId.apiString)/members",
                 body: AddMemberRequest(userId: userId.apiString, role: role))
    }
    static func changeRole(boardId: UUID, memberId: UUID, role: BoardRole) -> Endpoint {
        Endpoint(method: .patch, path: "boards/\(boardId.apiString)/members/\(memberId.apiString)",
                 body: RoleChangeRequest(role: role))
    }
    static func removeMember(boardId: UUID, memberId: UUID) -> Endpoint {
        Endpoint(method: .delete, path: "boards/\(boardId.apiString)/members/\(memberId.apiString)")
    }

    // MARK: Tasks
    static func tasks(boardId: UUID, status: TaskStatus? = nil, assigneeId: UUID? = nil) -> Endpoint {
        var query: [URLQueryItem] = []
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let assigneeId { query.append(URLQueryItem(name: "assigneeId", value: assigneeId.apiString)) }
        return Endpoint(path: "boards/\(boardId.apiString)/tasks", query: query)
    }
    static func task(boardId: UUID, taskId: UUID) -> Endpoint {
        Endpoint(path: "boards/\(boardId.apiString)/tasks/\(taskId.apiString)")
    }
    static func createTask(boardId: UUID, _ draft: TaskDraft) -> Endpoint {
        Endpoint(method: .post, path: "boards/\(boardId.apiString)/tasks", body: draft)
    }
    static func deleteTask(boardId: UUID, taskId: UUID) -> Endpoint {
        Endpoint(method: .delete, path: "boards/\(boardId.apiString)/tasks/\(taskId.apiString)")
    }
    // Task updates (PATCH with explicit nulls to clear fields) come in Step 6.
}
