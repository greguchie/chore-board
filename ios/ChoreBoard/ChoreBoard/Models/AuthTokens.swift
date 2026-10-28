nonisolated struct AuthTokens: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let accessTokenExpiresIn: String   // e.g. "15m"
    let user: User?                    // sent by /auth/login, not by /auth/refresh
}
