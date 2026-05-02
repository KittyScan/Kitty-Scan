import SwiftUI
import SwiftData

@main
struct CatHealthAppApp: App {
    @State private var auth = AuthManager.shared
    @State private var lang = LanguageManager.shared
    @State private var themeProvider = ThemeProvider.shared
    @State private var subs = SubscriptionManager.shared

    var body: some Scene {
        WindowGroup {
            RootGate()
                .environment(auth)
                .environment(lang)
                .environment(themeProvider)
                .environment(subs)
                .tint(themeProvider.theme.deep)
        }
        // Models registered locally for now. To enable iCloud sync (so the
        // diary survives device changes + syncs iPhone↔iPad), enable the
        // iCloud capability in Xcode (Signing & Capabilities → +Capability
        // → iCloud → CloudKit), pick/create a CloudKit container, then
        // switch to the `configurations:` form below:
        //
        //   let schema = Schema([Cat.self, HistoryRecord.self, DailyLog.self, CatEvent.self])
        //   let cfg = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        //   .modelContainer(try ModelContainer(for: schema, configurations: cfg))
        //
        // CloudKit requires every property to have a default and every
        // relationship to be optional or have a default — our models are
        // already shaped that way.
        .modelContainer(for: [Cat.self, HistoryRecord.self, DailyLog.self, CatEvent.self])
    }
}

/// Routes between Auth / Onboarding / Main app based on login + cat profile.
/// Also keeps ThemeProvider in sync with the current cat's breed.
struct RootGate: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ThemeProvider.self) private var themeProvider
    @Query(sort: \Cat.createdAt) private var cats: [Cat]

    private var activeBreedId: String? {
        themeProvider.activeCat(from: cats)?.breedId
    }

    @State private var consentAccepted: Bool = Consent.hasAccepted

    var body: some View {
        ZStack {
            if !consentAccepted {
                ConsentGate {
                    consentAccepted = true
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if !auth.isLoggedIn {
                AuthView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.02)),
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                    ))
            } else if cats.isEmpty {
                OnboardingView { cat in
                    themeProvider.setActive(cat: cat)
                }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                    ))
            } else {
                ContentView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.03)),
                        removal: .opacity
                    ))
            }
        }
        .onChange(of: activeBreedId, initial: true) { _, newId in
            themeProvider.breedId = newId
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: consentAccepted)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: auth.isLoggedIn)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: cats.isEmpty)
    }
}
