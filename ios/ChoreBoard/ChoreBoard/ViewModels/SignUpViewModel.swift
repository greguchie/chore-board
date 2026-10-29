import Foundation
import Observation

@MainActor
@Observable
final class SignUpViewModel {
    var displayName = ""
    var email = ""
    var password = ""
    var confirmPassword = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?
    private(set) var hasTriedSubmitting = false

    private let auth: any Authenticating

    init(auth: any Authenticating) {
        self.auth = auth
    }

    private var confirmError: String? {
        confirmPassword == password ? nil : "Passwords don't match"
    }

    var visibleNameError: String? { hasTriedSubmitting ? Validation.displayNameError(displayName) : nil }
    var visibleEmailError: String? { hasTriedSubmitting ? Validation.emailError(email) : nil }
    var visiblePasswordError: String? { hasTriedSubmitting ? Validation.newPasswordError(password) : nil }
    var visibleConfirmError: String? { hasTriedSubmitting ? confirmError : nil }

    private var isValid: Bool {
        Validation.displayNameError(displayName) == nil
            && Validation.emailError(email) == nil
            && Validation.newPasswordError(password) == nil
            && confirmError == nil
    }

    func submit() async {
        hasTriedSubmitting = true
        guard !isSubmitting, isValid else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await auth.signUp(email: Validation.trimmed(email),
                                  displayName: Validation.trimmed(displayName),
                                  password: password)
        } catch is CancellationError {
        } catch APIError.conflict {
            errorMessage = "An account with this email already exists. Try logging in instead."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
