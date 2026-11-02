import SwiftUI
import UIKit

struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: InviteLinkViewModel
    @State private var copied = false
    private let boardName: String

    init(boardId: UUID, boardName: String, service: any InvitesProviding) {
        self.boardName = boardName
        _viewModel = State(initialValue: InviteLinkViewModel(boardId: boardId, service: service))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Anyone with this link can join \(boardName) as a member. It works for 7 days.")
                        .foregroundStyle(.secondary)
                }

                Section("Invite link") {
                    if let link = viewModel.link {
                        Text(link.absoluteString)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                        Button(copied ? "Copied" : "Copy link",
                               systemImage: copied ? "checkmark" : "doc.on.doc") {
                            UIPasteboard.general.string = link.absoluteString
                            copied = true
                        }
                    } else if let message = viewModel.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Button("Try again") { Task { await viewModel.create() } }
                    } else {
                        ProgressView("Creating link…")
                    }
                }
            }
            .navigationTitle("Invite people")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if viewModel.link == nil { await viewModel.create() }
            }
        }
    }
}
