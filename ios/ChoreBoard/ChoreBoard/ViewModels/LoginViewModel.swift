import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    var email = ""
    var password = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?
    private(set) var hasTriedSubmitting = false

    private let auth: any Authenticating

    init(auth: any Authenticating) {
        self.auth = auth
    }

    // Field errors appear only after the first submit attempt.
    var visibleEmailError: String? {
        hasTriedSubmitting ? Validation.emailError(email) : nil
    }
    var visiblePasswordError: String? {
        hasTriedSubmitting && password.isEmpty ? "Enter your password" : nil
    }

    func submit() async {
        hasTriedSubmitting = true
        guard !isSubmitting, Validation.emailError(email) == nil, !password.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await auth.login(email: Validation.trimmed(email), password: password)
            // Success: AuthSession flips to logged in and RootView shows Home.
        } catch is CancellationError {
            // The screen went away; nothing to show.
        } catch {
            errorMessage = error.localizedDescription
            password = ""
        }
    }
}
