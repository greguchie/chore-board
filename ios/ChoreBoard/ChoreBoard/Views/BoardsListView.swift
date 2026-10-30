import SwiftUI

struct BoardsListView: View {
    @Environment(AuthSession.self) private var session
    @State private var viewModel: BoardsViewModel
    @State private var sheet: BoardSheet?
    @State private var boardToDelete: Board?
    private let service: any BoardsProviding

    init(service: any BoardsProviding) {
        self.service = service
        _viewModel = State(initialValue: BoardsViewModel(service: service))
    }

    var body: some View {
        content
            .navigationTitle("Boards")
            .navigationDestination(for: Board.self) { board in
                BoardDetailView(board: board, service: APITasksService(api: .shared))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    accountMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .create } label: {
                        Label("New board", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $sheet) { sheet in
                BoardEditorView(service: service, existing: sheet.board) { saved in
                    viewModel.upsert(saved)
                }
            }
            .confirmationDialog(
                "Delete \(boardToDelete?.name ?? "board")?",
                isPresented: Binding(get: { boardToDelete != nil },
                                     set: { if !$0 { boardToDelete = nil } }),
                titleVisibility: .visible,
                presenting: boardToDelete
            ) { board in
                Button("Delete board", role: .destructive) {
                    Task { await viewModel.delete(board) }
                }
            } message: { _ in
                Text("This deletes the board and all its tasks for every member. It can't be undone.")
            }
            .alert("Something went wrong",
                   isPresented: Binding(get: { viewModel.actionError != nil },
                                        set: { if !$0 { viewModel.actionError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.actionError ?? "")
            }
            .task {
                await viewModel.load()
                if session.currentUser == nil {
                    try? await session.loadCurrentUser()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading boards…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load boards", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await viewModel.retry() } }
                    .buttonStyle(.borderedProminent)
            }

        case .loaded:
            List {
                if viewModel.boards.isEmpty {
                    ContentUnavailableView {
                        Label("No boards yet", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Create a board for your home, flat or team, then invite people to share chores.")
                    } actions: {
                        Button("Create a board") { sheet = .create }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.boards) { board in
                        NavigationLink(value: board) {
                            BoardRow(board: board)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if board.myRole.canDeleteBoard {
                                Button("Delete", systemImage: "trash") { boardToDelete = board }
                                    .tint(.red)
                            }
                            if board.myRole.canEditBoard {
                                Button("Edit", systemImage: "pencil") { sheet = .edit(board) }
                                    .tint(.blue)
                            }
                        }
                    }
                }
            }
            .refreshable { await viewModel.load() }
        }
    }

    private var accountMenu: some View {
        Menu {
            if let user = session.currentUser {
                Section(user.email) {
                    Text(user.displayName)
                }
            }
            Button("Log out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                Task { await session.logout() }
            }
        } label: {
            Label("Account", systemImage: "person.crop.circle")
        }
    }
}

/// Which sheet is open: a new board, or editing an existing one.
private nonisolated enum BoardSheet: Identifiable {
    case create
    case edit(Board)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let board): board.id.uuidString
        }
    }

    var board: Board? {
        switch self {
        case .create: nil
        case .edit(let board): board
        }
    }
}

private struct BoardRow: View {
    let board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(board.name)
                    .font(.headline)
                Spacer()
                RoleBadge(role: board.myRole)
            }
            if let description = board.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
