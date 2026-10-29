import Foundation
import Testing
@testable import ChoreBoard

/// Records what the screens asked for, and fails on demand.
@MainActor
final class FakeAuth: Authenticating {
    var error: Error?
    private(set) var loginCalls = 0
    private(set) var signUpCalls = 0
    private(set) var lastEmail: String?
    private(set) var lastDisplayName: String?

    func login(email: String, password: String) async throws {
        loginCalls += 1
        lastEmail = email
        if let error { throw error }
    }

    func signUp(email: String, displayName: String, password: String) async throws {
        signUpCalls += 1
        lastEmail = email
        lastDisplayName = displayName
        if let error { throw error }
    }
}

@MainActor
struct AuthFormTests {

    @Test func validationRulesMatchTheServer() {
        #expect(Validation.emailError("") == "Enter your email")
        #expect(Validation.emailError("greg@") == "Enter a valid email address")
        #expect(Validation.emailError("  greg@example.com ") == nil)
        #expect(Validation.newPasswordError("short") == "Use at least 8 characters")
        #expect(Validation.newPasswordError("12345678") == nil)
        #expect(Validation.newPasswordError(String(repeating: "a", count: 129)) == "Use 128 characters or fewer")
        #expect(Validation.displayNameError("   ") == "Enter your name")
        #expect(Validation.displayNameError("Greg") == nil)
    }

    @Test func fieldErrorsStayHiddenUntilFirstSubmit() {
        let viewModel = LoginViewModel(auth: FakeAuth())
        #expect(viewModel.visibleEmailError == nil)
        #expect(viewModel.visiblePasswordError == nil)
    }

    @Test func invalidLoginNeverReachesTheServer() async {
        let auth = FakeAuth()
        let viewModel = LoginViewModel(auth: auth)
        viewModel.email = "not-an-email"

        await viewModel.submit()

        #expect(auth.loginCalls == 0)
        #expect(viewModel.visibleEmailError == "Enter a valid email address")
        #expect(viewModel.visiblePasswordError == "Enter your password")
    }

    @Test func failedLoginShowsErrorAndClearsPassword() async {
        let auth = FakeAuth()
        auth.error = APIError.invalidCredentials
        let viewModel = LoginViewModel(auth: auth)
        viewModel.email = "  greg@example.test "
        viewModel.password = "wrong-password"

        await viewModel.submit()

        #expect(auth.lastEmail == "greg@example.test")   // trimmed before sending
        #expect(viewModel.errorMessage == "Incorrect email or password.")
        #expect(viewModel.password.isEmpty)
        #expect(!viewModel.isSubmitting)
    }

    @Test func signUpRequiresMatchingPasswords() async {
        let auth = FakeAuth()
        let viewModel = SignUpViewModel(auth: auth)
        viewModel.displayName = "Greg"
        viewModel.email = "greg@example.test"
        viewModel.password = "Passw0rd-ios"
        viewModel.confirmPassword = "Passw0rd-iOS"

        await viewModel.submit()

        #expect(auth.signUpCalls == 0)
        #expect(viewModel.visibleConfirmError == "Passwords don't match")
    }

    @Test func signUpExplainsDuplicateEmail() async {
        let auth = FakeAuth()
        auth.error = APIError.conflict("That value is already in use")
        let viewModel = SignUpViewModel(auth: auth)
        viewModel.displayName = "Greg"
        viewModel.email = "greg@example.test"
        viewModel.password = "Passw0rd-ios"
        viewModel.confirmPassword = "Passw0rd-ios"

        await viewModel.submit()

        #expect(viewModel.errorMessage == "An account with this email already exists. Try logging in instead.")
    }

    @Test func signUpSendsTrimmedValues() async {
        let auth = FakeAuth()
        let viewModel = SignUpViewModel(auth: auth)
        viewModel.displayName = "  Greg  "
        viewModel.email = " greg@example.test "
        viewModel.password = "Passw0rd-ios"
        viewModel.confirmPassword = "Passw0rd-ios"

        await viewModel.submit()

        #expect(auth.signUpCalls == 1)
        #expect(auth.lastDisplayName == "Greg")
        #expect(auth.lastEmail == "greg@example.test")
        #expect(viewModel.errorMessage == nil)
    }
}
