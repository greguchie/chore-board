import SwiftUI

struct BoardsListView: View {
    @Environment(AuthSession.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var viewModel: BoardsViewModel
    @State private var sheet: BoardSheet?
    @State private var boardToDelete: Board?
    @State private var boardToOpen: UUID?
    private let service: any BoardsProviding
    private let tasksService: any TasksProviding
    private let cache: any OfflineCaching

    init(service: any BoardsProviding, tasksService: any TasksProviding, cache: any OfflineCaching) {
        self.service = service
        self.tasksService = tasksService
        self.cache = cache
        _viewModel = State(initialValue: BoardsViewModel(service: service, cache: cache))
    }

    var body: some View {
        content
            .navigationTitle("Boards")
            .navigationDestination(for: Route.self) { route in
                destination(for: route)
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
            .sheet(item: $sheet, onDismiss: openNewBoard) { sheet in
                BoardEditorView(service: service, existing: sheet.board) { saved in
                    viewModel.upsert(saved)
                    // A brand-new board opens once the sheet has finished closing.
                    if sheet.board == nil { boardToOpen = saved.id }
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

    /// The one place routes become screens.
    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .board(let id):
            BoardRouteView(boardId: id,
                           cached: viewModel.boards.first { $0.id == id },
                           boardsService: service,
                           tasksService: tasksService,
                           cache: cache)
        }
    }

    private func openNewBoard() {
        guard let id = boardToOpen else { return }
        boardToOpen = nil
        router.open(.board(id))
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
                if viewModel.isOffline {
                    Section { OfflineBanner(cachedAt: viewModel.cachedAt) }
                }
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
                        NavigationLink(value: Route.board(board.id)) {
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
