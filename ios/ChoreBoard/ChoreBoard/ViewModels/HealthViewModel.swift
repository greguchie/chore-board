import Foundation
import Observation

@MainActor
@Observable
final class HealthViewModel {
    enum State {
        case idle
        case loading
        case online(HealthStatus)
        case failed(String)
    }

    private(set) var state: State = .idle
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func check() async {
        state = .loading
        do {
            state = .online(try await api.send(API.health))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
