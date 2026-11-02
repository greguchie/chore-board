import Foundation
import Testing
import UIKit
@testable import ChoreBoard

@MainActor
struct ShareSheetTests {

    private struct DiskFull: LocalizedError {
        var errorDescription: String? { "Disk full" }
    }

    @Test func completedShareIsReported() {
        let result = ShareResult.from(activityType: .message, completed: true, error: nil)

        #expect(result == .shared(activity: UIActivity.ActivityType.message.rawValue))
        #expect(result.summary == "Invite shared via Messages.")
    }

    @Test func knownDestinationsHaveFriendlyNames() {
        // Guards the identifier strings used in ShareResult.summary.
        let copy = ShareResult.from(activityType: .copyToPasteboard, completed: true, error: nil)
        let mail = ShareResult.from(activityType: .mail, completed: true, error: nil)
        let airDrop = ShareResult.from(activityType: .airDrop, completed: true, error: nil)

        #expect(copy.summary == "Invite link copied.")
        #expect(mail.summary == "Invite shared via Mail.")
        #expect(airDrop.summary == "Invite shared via AirDrop.")
    }

    @Test func dismissingTheSheetIsACancel() {
        #expect(ShareResult.from(activityType: nil, completed: false, error: nil) == .cancelled)
        #expect(ShareResult.from(activityType: .mail, completed: false, error: nil) == .cancelled)
        #expect(ShareResult.cancelled.summary == nil)
    }

    @Test func errorsAreReported() {
        let result = ShareResult.from(activityType: .mail, completed: false, error: DiskFull())

        #expect(result == .failed("Disk full"))
        #expect(result.summary == "Couldn't share: Disk full")
    }

    @Test func inviteSheetKeepsTheLastOutcome() {
        let viewModel = InviteLinkViewModel(boardId: UUID(), service: FakeInvitesService())

        viewModel.recordShare(.shared(activity: UIActivity.ActivityType.copyToPasteboard.rawValue))
        #expect(viewModel.shareSummary == "Invite link copied.")

        viewModel.recordShare(.cancelled)   // a later cancel doesn't erase it
        #expect(viewModel.shareSummary == "Invite link copied.")
    }
}
