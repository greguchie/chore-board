import SwiftUI

struct LoginView: View {
    @State private var viewModel: LoginViewModel
    @FocusState private var focus: Field?
    private let auth: any Authenticating

    private enum Field { case email, password }

    init(auth: any Authenticating) {
        self.auth = auth
        _viewModel = State(initialValue: LoginViewModel(auth: auth))
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text("Chore Board")
                        .font(.title.bold())
                    Text("Share chores with the people you live with")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                if let error = viewModel.visibleEmailError {
                    FieldErrorText(message: error)
                }

                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                if let error = viewModel.visiblePasswordError {
                    FieldErrorText(message: error)
                }
            }

            if let message = viewModel.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Log in").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isSubmitting)
            }

            Section {
                NavigationLink("New here? Create an account") {
                    SignUpView(auth: auth)
                }
            }
        }
        .navigationTitle("Log in")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        focus = nil
        Task { await viewModel.submit() }
    }
}

#Preview {
    NavigationStack {
        LoginView(auth: AuthSession(api: APIClient(), store: InMemoryTokenStore()))
    }
}
