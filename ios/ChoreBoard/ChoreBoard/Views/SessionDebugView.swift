import SwiftUI

/// Temporary panel for testing the auth session. Step 4 replaces it with real login screens.
struct SessionDebugView: View {
    @Environment(AuthSession.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var message = ""
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 12) {
            if session.isLoggedIn {
                Label("Logged in", systemImage: "lock.open.fill")
                    .foregroundStyle(.green)
                Button("Who am I?") {
                    run {
                        try await session.loadCurrentUser()
                        message = "You are \(session.currentUser?.displayName ?? "unknown")"
                    }
                }
                Button("Log out", role: .destructive) {
                    run {
                        await session.logout()
                        message = "Logged out"
                    }
                }
            } else {
                Label("Logged out", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                Button("Log in") {
                    run {
                        try await session.login(email: email, password: password)
                        message = "Logged in as \(session.currentUser?.displayName ?? "unknown")"
                    }
                }
            }

            if !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .textFieldStyle(.roundedBorder)
        .buttonStyle(.bordered)
        .disabled(isWorking)
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try await action()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
