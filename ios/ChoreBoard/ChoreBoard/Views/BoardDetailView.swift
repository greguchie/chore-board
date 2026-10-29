import SwiftUI

struct BoardDetailView: View {
    let board: Board

    var body: some View {
        List {
            if let description = board.description, !description.isEmpty {
                Section("About") {
                    Text(description)
                }
            }

            Section("Your role") {
                RoleBadge(role: board.myRole)
            }

            Section {
                ContentUnavailableView("No tasks yet",
                                       systemImage: "checklist",
                                       description: Text("Tasks for this board will appear here."))
            }
        }
        .navigationTitle(board.name)
    }
}
