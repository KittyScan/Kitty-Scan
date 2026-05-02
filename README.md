# 🐾 KittyScan — AI Cat Health Companion

> SwiftUI iOS app that turns a single cat photo into a vet-aware health report
> in ~5 seconds, powered by Claude vision. Includes diary tracking, trend
> analysis, AI follow-up chat, and a privacy-first on-device data model.

[App Store: KittyScan](https://apps.apple.com/) (in review · v1.0)

---

## Features

- **One-tap analysis** — pick a cat photo, get a structured health report
  (eyes, fur, posture, energy, score, care tips) in plain language.
- **Daily diary** — log meals, water, mood. The last 7 days fold into the
  next analysis prompt so the AI sees context, not just the photo.
- **Trend tracking** — per-axis health charts (eyes / fur / posture / energy)
  surface drifts before they become problems.
- **Chat with the AI** — Pro users can ask follow-up questions; the model
  carries the cat's full history into every reply.
- **30 languages** — model output language follows the user's choice.
- **Privacy-first** — photos are processed during the API call only, never
  persisted on our servers. All cat profiles and reports live locally on the
  device via SwiftData.

---

## Architecture

```
   ┌──────────────────────────┐         ┌─────────────────────────┐
   │         iOS App          │  HTTPS  │  Cloudflare Worker      │
   │  SwiftUI + SwiftData     │ ──────▶ │  (TypeScript)           │
   │                          │         │                         │
   │  • SubscriptionManager   │         │  • Rate limit (KV)      │
   │  • ClaudeService         │         │  • Entitlement ledger   │
   │  • PaywallView (StoreKit)│         │  • Apple JWS verify     │
   │  • iCloud KV identity    │         │  • Cost tracking        │
   └──────────────────────────┘         └────────────┬────────────┘
                                                      │
                                                      ▼
                                        ┌──────────────────────────┐
                                        │   Anthropic Claude API   │
                                        │   (vision + chat)        │
                                        └──────────────────────────┘
```

The iOS client never holds API keys — every Anthropic request is brokered
by the Worker, which enforces per-device rate limits, validates Apple
StoreKit purchases via JWS, and writes a tier-aware entitlement ledger
to Cloudflare KV.

---

## Tech Stack

| Layer | Technology |
|---|---|
| **iOS** | Swift 6, SwiftUI, SwiftData, StoreKit 2, AuthenticationServices, AVFoundation |
| **AI** | Claude Sonnet 4 (Pro) / Haiku 4.5 (Free + pack) |
| **Backend** | Cloudflare Workers, Workers KV, TypeScript |
| **Auth** | Sign in with Apple, Google Sign-In, anonymous skip flow |
| **Payments** | Apple StoreKit 2 + App Store Server API (JWS verification) |
| **Identity** | NSUbiquitousKeyValueStore (cross-reinstall stable user ID) |

---

## Highlights

### Privacy-first design
- Cat photos are never stored on our servers — passed through during the
  ~3-second Claude API call only.
- All user content (cat profiles, reports, diary, chat history) lives in
  on-device SwiftData. No cloud sync of personal data.
- No third-party analytics SDKs, no IDFA, no advertising. ATT not required.

### Tier-aware backend
The Worker decides between two Claude models on every request: Pro
subscribers get Sonnet 4 (more accurate), free + pack users get Haiku 4.5
(~6× cheaper). Tier is signaled via header from a server-verified
StoreKit transaction, not the client-claimed tier.

### Defense-in-depth purchase verification
Apple StoreKit transactions are verified server-side via the App Store
Server API: signed JWS payload → Apple confirms → bundle ID match
check → `appAccountToken` match check → entitlement ledger write.
Forging a purchase requires forging Apple's signature.

### Anti-abuse
Three layers protecting the Anthropic spend cap:
1. Per-IP hourly rate limit (catches fresh-Device-ID enumeration).
2. Per-Device daily / monthly cap (defense-in-depth).
3. Account Token entitlement ledger keyed by an iCloud-synced UUID, so
   "delete and reinstall" no longer resets the free trial counter.

---

## Project Structure

```
CatHealthApp/
├── CatHealthAppApp.swift          # App entry, root navigation
├── ContentView.swift              # Root tab view
├── CameraView.swift               # Capture + analyze flow
├── HealthReportView.swift         # Generated report UI
├── HealthChartView.swift          # Per-axis trend charts
├── DiaryView.swift                # Daily log calendar
├── HistoryView.swift              # Past analyses
├── PaywallView.swift              # IAP + subscription UI
├── SubscriptionManager.swift      # StoreKit 2 + entitlement
├── ClaudeService.swift            # Backend API client
├── ThemeProvider.swift            # 22 cat-themed palettes
├── PromptBuilder.swift            # AI prompt construction
├── ConsentGate.swift              # Privacy-aware first run
├── Policies.swift                 # In-app privacy / terms
└── ...                            # ~50 more source files
```

---

## Notes

- v1.0 currently in App Store review.
- Worker source is in a separate repo.
- Backend secrets (Anthropic key, Apple .p8) are stored as Cloudflare
  Worker secrets, never committed.

## License

All rights reserved. Source available for portfolio review.
