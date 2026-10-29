import SwiftUI

/// Small red message shown under a form field.
struct FieldErrorText: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
