import SwiftUI

struct ContentView: View {
    @State private var viewModel = HealthViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Chore Board")
                .font(.largeTitle.bold())

            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Checking API…")
            case .online(let health):
                Label("API online", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("DB time: \(health.dbTime.formatted(date: .abbreviated, time: .standard))")                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Label("API unreachable", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button("Check again") {
                Task { await viewModel.check() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .task { await viewModel.check() }
    }
}

#Preview {
    ContentView()
}
