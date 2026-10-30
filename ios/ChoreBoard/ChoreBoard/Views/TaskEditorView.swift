import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: TaskEditorViewModel
    @FocusState private var titleFocused: Bool
    private let onSaved: (BoardTask) -> Void

    init(service: any TasksProviding, boardId: UUID, members: [Member],
         existing: BoardTask?, onSaved: @escaping (BoardTask) -> Void) {
        _viewModel = State(initialValue: TaskEditorViewModel(service: service, boardId: boardId,
                                                             members: members, existing: existing))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $viewModel.title)
                        .textInputAutocapitalization(.sentences)
                        .focused($titleFocused)
                    if let error = viewModel.visibleTitleError {
                        FieldErrorText(message: error)
                    }

                    TextField("Notes (optional)", text: $viewModel.details, axis: .vertical)
                        .lineLimit(2...5)
                    if let error = viewModel.visibleDetailsError {
                        FieldErrorText(message: error)
                    }
                }

                Section {
                    Picker("Assignee", selection: $viewModel.assigneeId) {
                        Text("Unassigned").tag(UUID?.none)
                        ForEach(viewModel.members) { member in
                            Text(member.name).tag(Optional(member.id))
                        }
                    }

                    Toggle("Due date", isOn: $viewModel.hasDueDate.animation())
                    if viewModel.hasDueDate {
                        DatePicker("Date", selection: $viewModel.dueDate, displayedComponents: .date)
                    }
                }

                if let message = viewModel.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(viewModel.screenTitle)
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
            .onAppear { titleFocused = viewModel.existing == nil }
        }
    }

    private func save() {
        Task {
            if let task = await viewModel.save() {
                onSaved(task)
                dismiss()
            }
        }
    }
}
