import Foundation

/// The one place the app talks to the backend: builds the request,
/// attaches the access token, sends it, and returns a model or an APIError.
@MainActor
final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession

    /// Supplies the current access token. Step 3 connects this
    /// to the Keychain and automatic token refresh.
    var accessTokenProvider: () -> String? = { nil }

    init(baseURL: URL = AppConfig.apiBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
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
            guard let token = accessTokenProvider() else { throw APIError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ endpoint: Endpoint) async throws -> Data {
        let request = try makeRequest(for: endpoint)

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()   // the screen went away; not a real error
        } catch let error as URLError {
            throw APIError(urlError: error)
        }
        let (data, response) = result

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unexpected("Response was not HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(statusCode: http.statusCode, body: data)
        }
        return data
    }
}
