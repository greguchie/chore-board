import SwiftUI

struct BoardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: BoardEditorViewModel
    @FocusState private var nameFocused: Bool
    private let onSaved: (Board) -> Void

    init(service: any BoardsProviding, existing: Board?, onSaved: @escaping (Board) -> Void) {
        _viewModel = State(initialValue: BoardEditorViewModel(service: service, existing: existing))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $viewModel.name)
                        .textInputAutocapitalization(.words)
                        .focused($nameFocused)
                    if let error = viewModel.visibleNameError {
                        FieldErrorText(message: error)
                    }
                }

                Section {
                    TextField("Description (optional)", text: $viewModel.details, axis: .vertical)
                        .lineLimit(3...6)
                    if let error = viewModel.visibleDetailsError {
                        FieldErrorText(message: error)
                    }
                } footer: {
                    Text("For example, who's on it or what it's for.")
                }

                if let message = viewModel.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .bold()
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear { nameFocused = viewModel.existing == nil }
        }
    }

    private func save() {
        Task {
            if let board = await viewModel.save() {
                onSaved(board)
                dismiss()
            }
        }
    }
}
