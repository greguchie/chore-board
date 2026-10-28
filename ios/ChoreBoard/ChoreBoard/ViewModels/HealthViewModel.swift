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
    private let service: HealthService

    init(service: HealthService = HealthService()) {
        self.service = service
    }

    func check() async {
        state = .loading
        do {
            state = .online(try await service.fetch())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
