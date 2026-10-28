import Foundation

nonisolated private struct ServerErrorBody: Decodable {
    let error: String
}

nonisolated enum APIError: LocalizedError, Equatable, Sendable {
    case offline
    case unauthorized
    case forbidden(String)
    case notFound(String)
    case conflict(String)
    case invalidInput(String)
    case rateLimited
    case server(statusCode: Int)
    case decoding(String)
    case unexpected(String)

    /// Maps an HTTP error response, using the server's {"error": "..."} message when present.
    init(statusCode: Int, body: Data) {
        let message = (try? JSONDecoder().decode(ServerErrorBody.self, from: body))?.error
        switch statusCode {
        case 400, 413, 422: self = .invalidInput(message ?? "Invalid input")
        case 401: self = .unauthorized
        case 403: self = .forbidden(message ?? "You don't have permission to do that")
        case 404: self = .notFound(message ?? "Not found")
        case 409: self = .conflict(message ?? "That conflicts with existing data")
        case 429: self = .rateLimited
        case 500...599: self = .server(statusCode: statusCode)
        default: self = .unexpected("HTTP \(statusCode)")
        }
    }

    /// Maps network-level failures (no connection, server down, timeout).
    init(urlError: URLError) {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .timedOut, .dataNotAllowed:
            self = .offline
        default:
            self = .unexpected(urlError.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .offline: "Can't reach the server. Check your connection and try again."
        case .unauthorized: "Your session has expired. Please log in again."
        case .forbidden(let message), .notFound(let message),
             .conflict(let message), .invalidInput(let message): message
        case .rateLimited: "Too many attempts. Please wait a few minutes and try again."
        case .server: "Something went wrong on our side. Please try again."
        case .decoding: "The app received data it didn't understand."
        case .unexpected: "Something unexpected happened. Please try again."
        }
    }
}
