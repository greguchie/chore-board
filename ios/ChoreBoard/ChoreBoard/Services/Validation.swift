import Foundation

/// Client-side checks that mirror the server's zod rules, so users get
/// instant feedback and the server's 400 is a rare fallback.
nonisolated enum Validation {
    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func emailError(_ email: String) -> String? {
        let value = trimmed(email)
        if value.isEmpty { return "Enter your email" }
        if value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) == nil {
            return "Enter a valid email address"
        }
        return nil
    }

    /// utf16.count matches how JavaScript (and zod) measure string length.
    static func newPasswordError(_ password: String) -> String? {
        if password.utf16.count < 8 { return "Use at least 8 characters" }
        if password.utf16.count > 128 { return "Use 128 characters or fewer" }
        return nil
    }

    static func displayNameError(_ name: String) -> String? {
        let value = trimmed(name)
        if value.isEmpty { return "Enter your name" }
        if value.utf16.count > 100 { return "Use 100 characters or fewer" }
        return nil
    }
    
    static func boardNameError(_ name: String) -> String? {
        let value = trimmed(name)
        if value.isEmpty { return "Enter a board name" }
        if value.utf16.count > 100 { return "Use 100 characters or fewer" }
        return nil
    }

    static func boardDescriptionError(_ description: String) -> String? {
        trimmed(description).utf16.count > 500 ? "Use 500 characters or fewer" : nil
    }
    static func taskTitleError(_ title: String) -> String? {
        let value = trimmed(title)
        if value.isEmpty { return "Enter a task title" }
        if value.utf16.count > 200 { return "Use 200 characters or fewer" }
        return nil
    }

    static func taskDescriptionError(_ description: String) -> String? {
        trimmed(description).utf16.count > 2000 ? "Use 2,000 characters or fewer" : nil
    }
}
