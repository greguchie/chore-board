import SwiftUI

/// The destination for a .board(id) route.
struct BoardRouteView: View {
    @State private var viewModel: BoardRouteViewModel
    private let tasksService: any TasksProviding

    init(boardId: UUID, cached: Board?,
         boardsService: any BoardsProviding, tasksService: any TasksProviding) {
        self.tasksService = tasksService
        _viewModel = State(initialValue: BoardRouteViewModel(boardId: boardId, cached: cached,
                                                             service: boardsService))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("Opening board…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let board):
                BoardDetailView(board: board, service: tasksService)

            case .notFound:
                ContentUnavailableView("Board not available",
                                       systemImage: "questionmark.folder",
                                       description: Text("It may have been deleted, or you're no longer a member."))

            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't open board", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await viewModel.load() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .task { await viewModel.load() }
    }
}
