import Foundation

struct HealthService {
    func fetch() async throws -> HealthStatus {
        let url = AppConfig.apiBaseURL.appending(path: "health")
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(HealthStatus.self, from: data)
    }
}
