import Foundation

enum AppConfig {
    static let apiBaseURL: URL = {
        #if DEBUG
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "https://api.example.com")! // replaced in Phase 6 (AWS)
        #endif
    }()
}
