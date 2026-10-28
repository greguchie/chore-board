import Foundation

nonisolated struct HealthStatus: Decodable, Sendable {
    let status: String
    let dbTime: Date
}
