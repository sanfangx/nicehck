import SwiftUI
import UIKit

enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        let formatString = NSLocalizedString(key, comment: "")
        return String(format: formatString, arguments: args)
    }
}

/// iOS 16.0-compatible replacement for iOS 17 `UnevenRoundedRectangle`
struct RoundedCornerShape: Shape {
    var radius: CGFloat = 16
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let bezier = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(bezier.cgPath)
    }
}

/// Shared card style for device detail sections
struct SectionCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
            )
    }
}

extension View {
    func sectionCardStyle() -> some View {
        modifier(SectionCardModifier())
    }
}
