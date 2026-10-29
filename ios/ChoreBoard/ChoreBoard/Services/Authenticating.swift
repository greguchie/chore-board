/// What the login and signup screens need. AuthSession is the real one;
/// tests use a fake, so screen logic can be tested without a network.
@MainActor
protocol Authenticating: AnyObject {
    func login(email: String, password: String) async throws
    func signUp(email: String, displayName: String, password: String) async throws
}

extension AuthSession: Authenticating {}
