import SwiftUI

struct BoardDetailView: View {
    @State private var viewModel: TasksViewModel
    @State private var sheet: TaskSheet?
    private let service: any TasksProviding

    init(board: Board, service: any TasksProviding) {
        self.service = service
        _viewModel = State(initialValue: TasksViewModel(board: board, service: service))
    }

    var body: some View {
        content
            .navigationTitle(viewModel.board.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .create } label: {
                        Label("New task", systemImage: "plus")
                    }
                    .disabled(viewModel.state != .loaded)
                }
            }
            .sheet(item: $sheet) { sheet in
                TaskEditorView(service: service, boardId: viewModel.board.id,
                               members: viewModel.members, existing: sheet.task) { saved in
                    viewModel.upsert(saved)
                }
            }
            .alert("Something went wrong",
                   isPresented: Binding(get: { viewModel.actionError != nil },
                                        set: { if !$0 { viewModel.actionError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.actionError ?? "")
            }
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading tasks…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load tasks", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await viewModel.retry() } }
                    .buttonStyle(.borderedProminent)
            }

        case .loaded:
            List {
                Section {
                    if let description = viewModel.board.description, !description.isEmpty {
                        Text(description)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Your role") {
                        RoleBadge(role: viewModel.board.myRole)
                    }
                }

                if viewModel.tasks.isEmpty {
                    ContentUnavailableView {
                        Label("No tasks yet", systemImage: "checklist")
                    } description: {
                        Text("Add the first chore for this board.")
                    } actions: {
                        Button("Add a task") { sheet = .create }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        let group = viewModel.tasks(in: status)
                        if !group.isEmpty {
                            Section("\(status.title) (\(group.count))") {
                                ForEach(group) { task in
                                    row(for: task)
                                }
                            }
                        }
                    }
                }
            }
            .refreshable { await viewModel.load() }
        }
    }

    private func row(for task: BoardTask) -> some View {
        TaskRow(task: task,
                assigneeName: viewModel.assigneeName(for: task),
                onToggle: { Task { await viewModel.toggleDone(task) } },
                onEdit: { sheet = .edit(task) })
            .swipeActions(edge: .leading) {
                ForEach(TaskStatus.allCases.filter { $0 != task.status }, id: \.self) { target in
                    Button(target.moveLabel) {
                        Task { await viewModel.setStatus(task, to: target) }
                    }
                    .tint(tint(for: target))
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if viewModel.canDeleteTasks {
                    Button("Delete", systemImage: "trash") {
                        Task { await viewModel.delete(task) }
                    }
                    .tint(.red)
                }
            }
    }

    private func tint(for status: TaskStatus) -> Color {
        switch status {
        case .todo: .gray
        case .inProgress: .blue
        case .done: .green
        }
    }
}

/// Which sheet is open: a new task, or editing an existing one.
private nonisolated enum TaskSheet: Identifiable {
    case create
    case edit(BoardTask)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let task): task.id.uuidString
        }
    }

    var task: BoardTask? {
        switch self {
        case .create: nil
        case .edit(let task): task
        }
    }
}

private struct TaskRow: View {
    let task: BoardTask
    let assigneeName: String?
    let onToggle: () -> Void
    let onEdit: () -> Void

    private var isDone: Bool { task.status == .done }
    private var isOverdue: Bool {
        guard let due = task.dueDate, !isDone else { return false }
        return due < DueDate.today   // "YYYY-MM-DD" strings sort like dates
    }
    private var statusColor: Color {
        switch task.status {
        case .todo: .secondary
        case .inProgress: .blue
        case .done: .green
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.status.symbol)
                    .font(.title2)
                    .foregroundStyle(statusColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? Color.secondary : Color.primary)

                if assigneeName != nil || task.dueDate != nil {
                    HStack(spacing: 12) {
                        if let assigneeName {
                            Label(assigneeName, systemImage: "person")
                        }
                        if let due = task.dueDate {
                            Label(isOverdue ? "Overdue · \(DueDate.display(due))" : DueDate.display(due),
                                  systemImage: "calendar")
                                .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
        }
        .padding(.vertical, 2)
    }
}
