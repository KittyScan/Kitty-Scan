import SwiftUI
import Foundation
import Observation

/// Holds the app-wide selected CatTheme and the "active" cat id across tabs.
/// Updated from RootGate whenever the active cat changes.
@Observable
@MainActor
final class ThemeProvider {
    static let shared = ThemeProvider()

    var breedId: String?

    private let activeCatKey = "activeCatId"
    var activeCatId: String? {
        didSet {
            UserDefaults.standard.set(activeCatId, forKey: activeCatKey)
        }
    }

    init() {
        self.activeCatId = UserDefaults.standard.string(forKey: activeCatKey)
    }

    var theme: CatTheme {
        CatThemes.byId(breedId) ?? CatThemes.defaultTheme
    }

    /// Returns the currently active cat (user-picked or first).
    func activeCat(from cats: [Cat]) -> Cat? {
        if let idStr = activeCatId,
           let uuid = UUID(uuidString: idStr),
           let match = cats.first(where: { $0.id == uuid }) {
            return match
        }
        return cats.first
    }

    func setActive(cat: Cat) {
        activeCatId = cat.id.uuidString
        breedId = cat.breedId
    }
}
