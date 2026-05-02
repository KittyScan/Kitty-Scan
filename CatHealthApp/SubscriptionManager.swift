import Foundation
import StoreKit
import Observation

/// Reference holder for a long-lived Task that the @MainActor SubscriptionManager
/// can still cancel from `deinit`. File-scope (not nested) so it doesn't
/// inherit the parent class's MainActor isolation, which would otherwise
/// make its `task` property unreachable from a nonisolated deinit.
fileprivate final class TaskBox: @unchecked Sendable {
    var task: Task<Void, Never>?
}

/// Single source of truth for what the user is allowed to do.
///
/// Rules (must mirror the Cloudflare Worker — server is the ultimate
/// authority, but client tracks for fast UX):
///   • 3 lifetime free analyses (counts in iCloud-synced UserDefaults)
///   • Consumable packs of 10 / 30 analyses (decrement balance on use)
///   • Auto-renewing monthly subscription: 50 analyses + 30 chat msgs / mo,
///     resets on subscription period boundary
///
/// Chat is gated to subscription only. Pack/free users see a paywall when
/// they tap chat.
@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    // MARK: - Product IDs (must match App Store Connect + Products.storekit)
    enum ProductID: String, CaseIterable {
        case pack10  = "com.jingyan.CatHealthApp.pack10"
        case pack30  = "com.jingyan.CatHealthApp.pack30"
        case monthly = "com.jingyan.CatHealthApp.monthly"

        /// Strikethrough "MSRP" shown next to the actual sale price as a
        /// launch-promo cue. Apple only knows the actual price (.displayPrice
        /// from the loaded Product). The MSRP here is purely a UI display
        /// number — bump these any time we want to change the perceived
        /// discount without affecting what users actually pay.
        var displayMSRP: String {
            switch self {
            case .pack10:  return "$3.99"
            case .pack30:  return "$9.99"
            case .monthly: return "$9.99"
            }
        }

        /// Computed % off, used in the promo badge text.
        var promoPercent: Int {
            switch self {
            case .pack10:  return 25   // 3.99 → 2.99
            case .pack30:  return 30   // 9.99 → 6.99
            case .monthly: return 30   // 9.99 → 6.99
            }
        }
    }

    // MARK: - User-facing tier

    enum Tier: Equatable {
        case free               // pre-purchase
        case packCredits(Int)   // remaining one-shot credits
        case subscriber         // active monthly sub
    }

    /// Highest entitlement currently available. Subscriber > pack > free.
    var tier: Tier {
        if isSubscribed { return .subscriber }
        if packBalance > 0 { return .packCredits(packBalance) }
        return .free
    }

    /// Whether the user has *ever* paid (any pack purchase or active sub).
    /// Drives "premium-only" gating like the theme picker and video import,
    /// where we want to reward any purchase — not just an active sub —
    /// because pack credits don't expire and the cosmetic perk shouldn't
    /// vanish when the credits run out.
    var hasPremiumAccess: Bool {
        isSubscribed || hasEverPurchased
    }

    /// Sticky flag flipped to true on first successful purchase of any
    /// product. Persisted so theme unlock survives even after pack credits
    /// hit zero — once paid, always unlocked.
    var hasEverPurchased: Bool {
        get { UserDefaults.standard.bool(forKey: "sub.hasEverPurchased") }
        set { UserDefaults.standard.set(newValue, forKey: "sub.hasEverPurchased") }
    }

    // MARK: - Limits (mirror server-side numbers in wrangler.toml)
    static let freeLifetimeAnalyses = 3
    static let subMonthlyAnalyses   = 50
    static let subMonthlyChats      = 30

    // MARK: - Persisted counters (UserDefaults; iCloud-synced via NSUbiquitousKeyValueStore later)

    private let kFreeUsed       = "sub.freeAnalysesUsed"
    private let kPackBalance    = "sub.packBalance"
    private let kSubAnalyzeUsed = "sub.subAnalyzesThisPeriod"
    private let kSubChatUsed    = "sub.subChatsThisPeriod"
    private let kSubPeriodStart = "sub.subPeriodStartedAt"

    /// Lifetime free analyses already consumed.
    var freeUsed: Int {
        get { UserDefaults.standard.integer(forKey: kFreeUsed) }
        set { UserDefaults.standard.set(newValue, forKey: kFreeUsed) }
    }

    /// Remaining one-shot pack credits.
    var packBalance: Int {
        get { UserDefaults.standard.integer(forKey: kPackBalance) }
        set { UserDefaults.standard.set(newValue, forKey: kPackBalance) }
    }

    /// Analyses used in the current subscription period.
    var subAnalyzesUsed: Int {
        get { UserDefaults.standard.integer(forKey: kSubAnalyzeUsed) }
        set { UserDefaults.standard.set(newValue, forKey: kSubAnalyzeUsed) }
    }

    /// Chat messages used in the current subscription period.
    var subChatsUsed: Int {
        get { UserDefaults.standard.integer(forKey: kSubChatUsed) }
        set { UserDefaults.standard.set(newValue, forKey: kSubChatUsed) }
    }

    var isSubscribed: Bool = false
    var subscriptionExpiresAt: Date?
    var products: [Product] = []
    var purchaseInFlight: ProductID?

    /// Stable UUID identifying THIS user's subscription state to the worker.
    /// Stored in iCloud Key-Value Store (NSUbiquitousKeyValueStore) so it survives
    /// app reinstall on the same Apple ID — closing the "delete app to reset
    /// the 3 free analyses" loophole. UserDefaults mirrors it for offline reads.
    /// Resolution order on read: iCloud → UserDefaults → generate new.
    var appAccountToken: UUID {
        let key = "sub.appAccountToken"
        let cloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard

        if let s = cloud.string(forKey: key), let u = UUID(uuidString: s) {
            if local.string(forKey: key) != s { local.set(s, forKey: key) }
            return u
        }
        if let s = local.string(forKey: key), let u = UUID(uuidString: s) {
            cloud.set(s, forKey: key)
            cloud.synchronize()
            return u
        }
        let new = UUID()
        let s = new.uuidString
        local.set(s, forKey: key)
        cloud.set(s, forKey: key)
        cloud.synchronize()
        return new
    }

    /// Wrapped in a Sendable box so `deinit` (not main-actor-isolated) can
    /// still cancel the listener. `Task` itself is thread-safe. Box is
    /// declared at file scope — nesting it inside the @MainActor class
    /// would inherit MainActor isolation and break deinit access.
    private let transactionListenerBox = TaskBox()

    init() {
        // Pull the latest iCloud KV state at launch so appAccountToken can
        // recover its previously-stored value before the first /analyze call
        // (closes the reinstall-to-reset loophole on the same Apple ID).
        NSUbiquitousKeyValueStore.default.synchronize()

        transactionListenerBox.task = Task { [weak self] in
            // StoreKit pushes any verified transaction (purchase, renewal,
            // refund, etc.) through this stream. We re-evaluate entitlements
            // each time so subscription state stays current.
            for await update in Transaction.updates {
                guard case .verified(let tx) = update else { continue }
                await tx.finish()
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        transactionListenerBox.task?.cancel()
    }

    // MARK: - Capability checks (call before performing the gated action)

    enum GateResult: Equatable {
        case allowed
        case blocked(reason: BlockReason)

        enum BlockReason: String, Equatable, Identifiable {
            case freeExhausted
            case packEmpty
            case subAnalyzeQuotaExhausted
            case subChatQuotaExhausted
            case chatRequiresSubscription
            /// User tapped a locked theme card. Distinct from `freeExhausted`
            /// so the paywall copy doesn't lie about analysis quota.
            case themeLocked

            var id: String { rawValue }
        }
    }

    /// Can the user spend an analysis right now?
    func canAnalyze() -> GateResult {
        switch tier {
        case .subscriber:
            return subAnalyzesUsed < Self.subMonthlyAnalyses
                ? .allowed
                : .blocked(reason: .subAnalyzeQuotaExhausted)
        case .packCredits:
            return packBalance > 0 ? .allowed : .blocked(reason: .packEmpty)
        case .free:
            return freeUsed < Self.freeLifetimeAnalyses
                ? .allowed
                : .blocked(reason: .freeExhausted)
        }
    }

    /// Chat is subscriber-only.
    func canChat() -> GateResult {
        switch tier {
        case .subscriber:
            return subChatsUsed < Self.subMonthlyChats
                ? .allowed
                : .blocked(reason: .subChatQuotaExhausted)
        case .packCredits, .free:
            return .blocked(reason: .chatRequiresSubscription)
        }
    }

    /// Decrement the right counter after a successful analyze. The server is
    /// the ultimate authority — it'll reject if its own ledger says no — but
    /// the client decrements optimistically so paywall UI feels instant.
    func consumeAnalyze() {
        switch tier {
        case .subscriber:    subAnalyzesUsed += 1
        case .packCredits:   packBalance = max(0, packBalance - 1)
        case .free:          freeUsed += 1
        }
    }

    func consumeChat() {
        // Only subscribers reach this path; gate enforced at call site.
        if isSubscribed { subChatsUsed += 1 }
    }

    // MARK: - Purchase flow

    func loadProducts() async {
        do {
            let ids = ProductID.allCases.map(\.rawValue)
            products = try await Product.products(for: ids)
        } catch {
            print("[Subscription] loadProducts failed:", error.localizedDescription)
        }
    }

    /// Initiates a StoreKit purchase. Returns true on successful purchase.
    func purchase(_ id: ProductID) async -> Bool {
        guard let product = products.first(where: { $0.id == id.rawValue }) else {
            return false
        }
        purchaseInFlight = id
        defer { purchaseInFlight = nil }

        do {
            // Tagging the purchase with our stable UUID makes the transaction
            // identifiable to the worker without us having to round-trip the
            // receipt body — Apple includes appAccountToken in the JWS payload.
            let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
            switch result {
            case .success(let verification):
                guard case .verified(let tx) = verification else { return false }
                await applyTransaction(tx, productId: id)
                await reportPurchaseToWorker(tx)
                await tx.finish()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            print("[Subscription] purchase failed:", error.localizedDescription)
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: - Entitlement evaluation

    private func refreshEntitlements() async {
        var subActive = false
        var subExpiry: Date?
        var newSubPeriodStart: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            guard let pid = ProductID(rawValue: tx.productID) else { continue }

            switch pid {
            case .monthly:
                if let expires = tx.expirationDate, expires > Date() {
                    subActive = true
                    subExpiry = expires
                    newSubPeriodStart = tx.purchaseDate
                }
            case .pack10, .pack30:
                // Consumables don't appear in currentEntitlements after
                // .finish() — handled in `applyTransaction` instead.
                break
            }
        }

        isSubscribed = subActive
        subscriptionExpiresAt = subExpiry

        // Reset subscription counters when a new billing period begins.
        if let start = newSubPeriodStart {
            let stored = UserDefaults.standard.object(forKey: kSubPeriodStart) as? Date
            if stored != start {
                UserDefaults.standard.set(start, forKey: kSubPeriodStart)
                subAnalyzesUsed = 0
                subChatsUsed = 0
            }
        }
    }

    /// POSTs the freshly purchased transaction's JWS to the worker so the
    /// server-side ledger can be populated immediately. Best-effort: if it
    /// fails the worker will pick up the same transaction lazily on the next
    /// `/analyze` call (the iOS client always attaches the latest verified
    /// receipt). Don't block the UI on this.
    private func reportPurchaseToWorker(_ tx: Transaction) async {
        guard let url = URL(string: "https://carmel-worker.8fn98bvpdb.workers.dev/verify-receipt") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(appAccountToken.uuidString, forHTTPHeaderField: "X-Account-Token")
        let payload: [String: Any] = [
            "transactionId": String(tx.id),
            "originalTransactionId": String(tx.originalID),
            "productId": tx.productID,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)
    }

    private func applyTransaction(_ tx: Transaction, productId: ProductID) async {
        // Sticky "has ever paid" flag — flipped once and never reset, so
        // theme unlock + other cosmetic perks persist after pack credits
        // run out.
        hasEverPurchased = true
        switch productId {
        case .pack10:  packBalance += 10
        case .pack30:  packBalance += 30
        case .monthly:
            // Newly activated sub starts a fresh quota period.
            UserDefaults.standard.set(tx.purchaseDate, forKey: kSubPeriodStart)
            subAnalyzesUsed = 0
            subChatsUsed = 0
            await refreshEntitlements()
        }
    }
}
