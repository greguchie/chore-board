import SwiftUI

struct HomeView: View {
    @Environment(AuthSession.self) private var session
    @State private var loadError: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Name", value: session.currentUser?.displayName ?? "Loading…")
                LabeledContent("Email", value: session.currentUser?.email ?? "Loading…")
            } header: {
                Text("Signed in")
            } footer: {
                Text("Your boards will appear here soon.")
            }

            if let loadError {
                Section {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Log out", role: .destructive) {
                    Task { await session.logout() }
                }
            }
        }
        .navigationTitle("Chore Board")
        .task { await loadUser() }
        .refreshable { await loadUser() }
    }

    private func loadUser() async {
        do {
            try await session.loadCurrentUser()
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = error.localizedDescription
        }
    }
}
