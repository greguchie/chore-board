import SwiftUI

/// Shown at the top of a list when it's displaying saved data.
struct OfflineBanner: View {
    let cachedAt: Date?

    var body: some View {
        Label(message, systemImage: "wifi.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var message: String {
        guard let cachedAt else { return "Offline · showing saved data" }
        return "Offline · updated \(cachedAt.formatted(.relative(presentation: .named)))"
    }
}
