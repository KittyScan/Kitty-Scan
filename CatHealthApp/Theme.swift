import SwiftUI
import UIKit

enum Theme {
    static let primary       = Color(hex: "FF8C42")
    static let info          = Color(hex: "4A90D9")
    static let warning       = Color(hex: "FF9500")
    static let danger        = Color(hex: "FF3B30")
    static let success       = Color(hex: "34C759")

    // Surface colors — bridge to UIKit semantic colors so they auto-adapt
    // to light/dark mode. systemGroupedBackground = page bg; the *Grouped*
    // variants give the contrast we want (white-on-light-grey in light,
    // dark-grey-on-black in dark).
    static let background    = Color(UIColor.systemGroupedBackground)
    static let cardPrimary   = Color(UIColor.secondarySystemGroupedBackground)
    static let cardSecondary = Color(UIColor.tertiarySystemBackground)
    static let cardTertiary  = Color(UIColor.tertiarySystemFill)

    // Tinted backgrounds — manually adapted because there's no semantic
    // equivalent for "warm cream" in iOS palette.
    static let disclaimerBg = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.24, blue: 0.08, alpha: 1)
            : UIColor(red: 1.00, green: 0.98, blue: 0.92, alpha: 1)
    })

    static let warningBg = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.20, blue: 0.08, alpha: 1)
            : UIColor(red: 1.00, green: 0.97, blue: 0.94, alpha: 1)
    })

    // Amber text on the disclaimer/warning backgrounds — light amber in
    // dark mode for legibility, deep amber in light mode for contrast.
    static let amberText = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.83, blue: 0.40, alpha: 1)
            : UIColor(red: 0.48, green: 0.36, blue: 0.00, alpha: 1)
    })
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var val: UInt64 = 0
        Scanner(string: h).scanHexInt64(&val)
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }

    /// Reliable UIColor bridge that works inside off-screen renderers
    /// (UIGraphicsImageRenderer / UIGraphicsPDFRenderer).
    ///
    /// `UIColor(Color)` silently returns `.clear` when invoked without a trait
    /// environment, producing fully transparent exports that look blank.
    /// We prefer `Color.cgColor` (always concrete for RGB colors) and fall
    /// back to an explicit light-mode trait resolution.
    var uiSolid: UIColor {
        if let cg = self.cgColor {
            return UIColor(cgColor: cg)
        }
        return UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }
}
