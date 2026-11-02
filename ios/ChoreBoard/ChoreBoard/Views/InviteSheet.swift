import SwiftUI
import UIKit

struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: InviteLinkViewModel
    @State private var copied = false
    @State private var isSharing = false
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
                        Button("Share link", systemImage: "square.and.arrow.up") {
                            isSharing = true
                        }
                        .bold()
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

                if let summary = viewModel.shareSummary {
                    Section {
                        Label(summary, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
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
            .sheet(isPresented: $isSharing) {
                if let link = viewModel.link {
                    ShareSheet(items: [link], excludedActivityTypes: ShareSheet.linkExclusions) { result in
                        viewModel.recordShare(result)
                        isSharing = false   // close our wrapper sheet too, so no blank sheet is left
                    }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
                }
            }
            .task {
                if viewModel.link == nil { await viewModel.create() }
            }
        }
    }
}
