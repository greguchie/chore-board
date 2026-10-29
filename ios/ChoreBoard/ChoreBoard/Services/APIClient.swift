import Foundation

/// Supplies access tokens to APIClient and renews them when they expire.
/// AuthSession is the real one.
@MainActor
protocol AccessTokenProviding: AnyObject {
    var accessToken: String? { get }
    /// Called after a 401. Returns a working access token, refreshing if needed.
    func refreshedAccessToken(after failedToken: String) async throws -> String
    /// Called when the server still says 401 even after a refresh.
    func sessionExpired()
}

/// The one place the app talks to the backend: builds the request,
/// attaches the access token, sends it, and returns a model or an APIError.
@MainActor
final class APIClient {
    /// Sends a request. The real app uses URLSession; tests plug in a fake server.
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    static let shared = APIClient()

    private let baseURL: URL
    private let transport: Transport

    /// Weak so APIClient and AuthSession don't keep each other alive forever.
    weak var tokenProvider: (any AccessTokenProviding)?

    init(baseURL: URL = AppConfig.apiBaseURL,
         transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// Sends a request and decodes the JSON response.
    func send<Response: Decodable>(_ endpoint: Endpoint,
                                   as type: Response.Type = Response.self) async throws -> Response {
        let data = try await perform(endpoint)
        do {
            return try JSONCoding.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// For endpoints that answer 204 No Content (deletes, logout).
    func sendNoContent(_ endpoint: Endpoint) async throws {
        _ = try await perform(endpoint)
    }

    /// Builds the URLRequest. Internal (not private) so tests can inspect it.
    func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appending(path: endpoint.path),
                                             resolvingAgainstBaseURL: false) else {
            throw APIError.unexpected("Bad path: \(endpoint.path)")
        }
        if !endpoint.query.isEmpty { components.queryItems = endpoint.query }
        guard let url = components.url else {
            throw APIError.unexpected("Bad URL for \(endpoint.path)")
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = endpoint.body {
            request.httpBody = try JSONCoding.makeEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if endpoint.requiresAuth {
            guard let token = tokenProvider?.accessToken else { throw APIError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ endpoint: Endpoint, isRetry: Bool = false) async throws -> Data {
        let request = try makeRequest(for: endpoint)
        let (data, http) = try await transmit(request)

        // Expired access token: refresh once, then retry the same request once.
        if http.statusCode == 401, endpoint.requiresAuth, let provider = tokenProvider {
            let sentToken = request.value(forHTTPHeaderField: "Authorization")
                .map { String($0.dropFirst("Bearer ".count)) }
            guard !isRetry, let sentToken else {
                provider.sessionExpired()   // still 401 with a fresh token: give up
                throw APIError.unauthorized
            }
            _ = try await provider.refreshedAccessToken(after: sentToken)
            return try await perform(endpoint, isRetry: true)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError(statusCode: http.statusCode, body: data)
        }
        return data
    }

    private func transmit(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result: (Data, URLResponse)
        do {
            result = try await transport(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()   // the screen went away; not a real error
        } catch let error as URLError {
            throw APIError(urlError: error)
        }
        guard let http = result.1 as? HTTPURLResponse else {
            throw APIError.unexpected("Response was not HTTP")
        }
        return (result.0, http)
    }
}
