import Foundation

/// Presentation-only badge normalization. Restrict the menu bar to a compact,
/// non-sensitive count or a neutral dot; raw Dock labels are never rendered.
enum BadgeIcon {
    static func menuTitle(for rawBadge: String?, showsCount: Bool) -> String {
        guard let badge = rawBadge?.trimmingCharacters(in: .whitespacesAndNewlines),
              !badge.isEmpty else { return "" }

        guard showsCount else { return " •" }

        let digits = badge.hasSuffix("+") ? String(badge.dropLast()) : badge
        let numeric = !digits.isEmpty && digits.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
        guard numeric else { return " •" }

        // Protect the menu-bar layout if an app reports an unusually large count.
        guard digits.count <= 2, let count = Int(digits), count < 100 else {
            return " 99+"
        }
        return " " + badge
    }
}
