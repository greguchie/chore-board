import SwiftUI

struct SignUpView: View {
    @State private var viewModel: SignUpViewModel
    @FocusState private var focus: Field?

    private enum Field { case name, email, password, confirm }

    init(auth: any Authenticating) {
        _viewModel = State(initialValue: SignUpViewModel(auth: auth))
    }

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $viewModel.displayName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .email }
                if let error = viewModel.visibleNameError {
                    FieldErrorText(message: error)
                }

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
            }

            Section {
                SecureField("Password", text: $viewModel.password)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focus = .confirm }
                if let error = viewModel.visiblePasswordError {
                    FieldErrorText(message: error)
                }

                SecureField("Confirm password", text: $viewModel.confirmPassword)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .confirm)
                    .submitLabel(.go)
                    .onSubmit(submit)
                if let error = viewModel.visibleConfirmError {
                    FieldErrorText(message: error)
                }
            } footer: {
                Text("At least 8 characters.")
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
                            Text("Create account").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isSubmitting)
            }
        }
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focus = .name }
    }

    private func submit() {
        focus = nil
        Task { await viewModel.submit() }
    }
}

#Preview {
    NavigationStack {
        SignUpView(auth: AuthSession(api: APIClient(), store: InMemoryTokenStore()))
    }
}
