import SwiftUI

struct RoleBadge: View {
    let role: BoardRole

    var body: some View {
        Text(role.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch role {
        case .owner: .orange
        case .admin: .blue
        case .member: .gray
        }
    }
}
