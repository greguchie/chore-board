import SwiftUI
import UIKit

/// What happened when the share sheet closed, as a plain Swift value.
nonisolated enum ShareResult: Equatable, Sendable {
    case shared(activity: String)   // UIKit's activity identifier, e.g. Messages
    case cancelled
    case failed(String)

    /// Translates UIKit's completion callback into a Swift value.
    static func from(activityType: UIActivity.ActivityType?, completed: Bool,
                     error: (any Error)?) -> ShareResult {
        if let error { return .failed(error.localizedDescription) }
        guard completed, let activityType else { return .cancelled }
        return .shared(activity: activityType.rawValue)
    }

    /// A short message for the screen, or nil when there's nothing to say.
    var summary: String? {
        switch self {
        case .shared(let activity):
            switch activity {
            case "com.apple.UIKit.activity.CopyToPasteboard": return "Invite link copied."
            case "com.apple.UIKit.activity.Message": return "Invite shared via Messages."
            case "com.apple.UIKit.activity.Mail": return "Invite shared via Mail."
            case "com.apple.UIKit.activity.AirDrop": return "Invite shared via AirDrop."
            default: return "Invite shared."
            }
        case .cancelled:
            return nil
        case .failed(let message):
            return "Couldn't share: \(message)"
        }
    }
}

/// SwiftUI wrapper around UIKit's share sheet (UIActivityViewController).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType] = []
    var onComplete: (ShareResult) -> Void = { _ in }

    /// Destinations that make no sense for a link.
    static let linkExclusions: [UIActivity.ActivityType] = [
        .addToReadingList, .assignToContact, .saveToCameraRoll, .print, .openInIBooks,
    ]

    // SwiftUI calls this once, to create the UIKit controller.
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = excludedActivityTypes

        let coordinator = context.coordinator
        controller.completionWithItemsHandler = { activityType, completed, _, error in
            // UIKit calls this on the main thread.
            MainActor.assumeIsolated {
                coordinator.finish(ShareResult.from(activityType: activityType,
                                                    completed: completed, error: error))
            }
        }
        return controller
    }

    // SwiftUI calls this whenever its state changes. Keep the latest callback.
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        context.coordinator.onComplete = onComplete
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    /// Receives UIKit's callback and hands the result back to SwiftUI.
    final class Coordinator {
        var onComplete: (ShareResult) -> Void

        init(onComplete: @escaping (ShareResult) -> Void) {
            self.onComplete = onComplete
        }

        func finish(_ result: ShareResult) {
            onComplete(result)
        }
    }
}
