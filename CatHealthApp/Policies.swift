import Foundation

/// Structured privacy policy / ToS documents.
/// Stored as data (not marked-up strings) so the viewer can render typography nicely,
/// and so future edits stay diffable.
///
/// ⚠️ DRAFT — reviewed by the dev, NOT by a lawyer. Before shipping to the App Store,
///    a qualified attorney should verify these meet your jurisdiction's requirements.
///    Placeholders in brackets [TO BE FILLED] must be replaced prior to publishing.

struct PolicyDoc: Hashable {
    let title: String
    let effectiveDate: String
    let sections: [Section]

    struct Section: Hashable {
        let number: Int
        let heading: String
        let blocks: [Block]
    }

    enum Block: Hashable {
        case paragraph(String)
        case bullets([String])
        case callout(String)    // highlighted box
        case link(String, String)  // (label, url)
    }
}

enum Policies {

    static let version = "v2"          // bump when policy text changes → re-consent
    static let effectiveDateZh = "2026 年 4 月 27 日"
    static let effectiveDateEn = "April 27, 2026"

    static func privacy(zh: Bool) -> PolicyDoc {
        zh ? privacyZH : privacyEN
    }

    static func terms(zh: Bool) -> PolicyDoc {
        zh ? termsZH : termsEN
    }

    // ================================================================
    // PRIVACY — English
    // ================================================================
    private static let privacyEN = PolicyDoc(
        title: "KittyScan Privacy Policy",
        effectiveDate: effectiveDateEn,
        sections: [
            .init(number: 1, heading: "Who we are", blocks: [
                .paragraph("KittyScan (\"we\", \"us\", \"the app\") is a personal cat health app operated from California, USA. This policy explains, in plain language, what information we collect, why we collect it, who else sees it, and the controls you have.")
            ]),
            .init(number: 2, heading: "Our principles", blocks: [
                .paragraph("Three commitments shape every design choice in KittyScan:"),
                .bullets([
                    "**Local-first.** Your cat profiles, photos, analysis history, and chat conversations live on YOUR device. We don't have a copy.",
                    "**Pseudonymous.** What our server sees about you is reduced to a random UUID we generate the first time the app opens. Your name, email, or phone number never reaches our backend.",
                    "**No advertising, ever.** We don't run ads, share data with ad networks, or use advertising identifiers (IDFA). We make money only from optional subscriptions and analysis packs."
                ])
            ]),
            .init(number: 3, heading: "What we collect — and where it lives", blocks: [
                .paragraph("**Stored on YOUR device only:**"),
                .bullets([
                    "Cat profiles (name, breed, age, neuter status, known issues, avatar photo)",
                    "Cat photos you submit for analysis",
                    "All AI-generated health reports, sub-scores, and warnings",
                    "Chat-with-AI message history",
                    "Notes you attach to a check (\"今天没怎么吃饭\" etc.)",
                    "Your free-tier counter and pack credit balance",
                    "Language and theme preferences",
                    "Login session token (after Apple/Google Sign In)"
                ]),
                .paragraph("**Sent to our backend (Cloudflare Worker) for the duration of one request:**"),
                .bullets([
                    "The photo itself (only while we forward it to Anthropic — see §4)",
                    "Cat metadata embedded in the prompt (name, breed, age) — required for the AI to produce contextual reports",
                    "Your `Account Token` (a random UUID, see §5)",
                    "Your `Device ID` (a separate random UUID, see §5)"
                ]),
                .paragraph("**Stored on our backend long-term:**"),
                .bullets([
                    "Per-device rate-limit counters (auto-expire ≤ 40 days)",
                    "Per-account-token entitlement state: subscription tier, remaining quota, billing-period start (so we know whether you can run another analysis)",
                    "Aggregate, anonymous monthly token-usage totals (for cost reconciliation; cannot be linked to a single user)"
                ]),
                .paragraph("**Stored by Apple, not us, when you purchase a subscription or pack:**"),
                .bullets([
                    "Your Apple ID, payment method, billing history. We never see these — Apple handles the transaction.",
                    "We receive only a transaction ID and our own Account Token (which we sent you to begin with), allowing us to enable your purchased entitlement."
                ]),
                .paragraph("**We do NOT collect, ever:**"),
                .bullets([
                    "Real name, phone number, mailing address, payment info",
                    "Location, GPS, or IP-based geolocation (your IP is briefly visible to Cloudflare for routing/abuse-prevention only and is not retained tied to your account)",
                    "Contacts, calendar, microphone, or HealthKit data",
                    "Advertising identifiers (IDFA, Google Ad ID)",
                    "Crash logs that contain personal data — we don't run a crash reporter",
                    "Behavioral analytics (no Mixpanel, Amplitude, Firebase Analytics, etc.)"
                ])
            ]),
            .init(number: 4, heading: "How a photo travels through the system", blocks: [
                .paragraph("Step by step, what happens when you tap \"Analyze\":"),
                .paragraph("**1.** Photo is captured / picked from your device's photo library (we ask iOS for one-time permission)."),
                .paragraph("**2.** A small on-device check runs first: Apple's Vision framework detects whether a cat is present and whether the image is too dark / too bright. This runs entirely on your phone — nothing leaves the device. If the photo fails the check, we ask you to retake before any network call."),
                .paragraph("**3.** A separate on-device check (Vision feature print) compares this photo against your previously analyzed photos to detect if the photo looks like a different cat than your active profile. Also runs entirely on-device."),
                .paragraph("**4.** If the photo passes both checks, your iOS app sends an HTTPS request to our Cloudflare Worker at `carmel-worker.workers.dev/analyze` with: the JPEG-compressed photo (base64), the analysis prompt, your Account Token, and your Device ID."),
                .paragraph("**5.** The Worker checks your subscription entitlement and rate limit. If permitted, it forwards the photo + prompt to **Anthropic's Claude API** over HTTPS, authenticated with our server-side API key (which is never visible to your app)."),
                .paragraph("**6.** Claude returns a JSON health report. The Worker returns it to your app and discards the photo from memory. The photo is not written to any disk on our side and not logged."),
                .paragraph("**7.** Your app saves the photo + report to your device's local database (SwiftData) and the screen renders the result."),
                .callout("**The photo is in transit on our servers for a few seconds and is never persisted there. The only data we keep is: counters that say \"this account ran one more analysis\" and \"this device hit our endpoint at this time\". No image data, no prompt content, no report content.**")
            ]),
            .init(number: 5, heading: "Identifiers we use, and what they reveal", blocks: [
                .paragraph("We use two pseudonymous identifiers — both are random UUIDs we generate the first time you open the app. Neither is linked to your real identity unless you choose to subscribe (in which case Apple — not us — links it to your Apple ID for billing purposes)."),
                .paragraph("**Device ID.** Generated and stored in your iOS Keychain. Used purely as the key for our per-device rate-limit counters. Erasing the app or your phone destroys this ID. We cannot use it to track you across devices, across reinstalls, or to a real-world identity."),
                .paragraph("**Account Token.** A separate UUID we attach to subscription transactions. When you buy a sub, Apple includes this UUID in the transaction receipt, which lets our backend know which entitlement to enable when the receipt comes back. The token never leaves your device except in HTTPS requests to our Worker. It is not associated with your name, email, or any identity provider account."),
                .paragraph("If you sign in with Apple or Google, the identity provider knows your email; we receive only your display name to populate the app UI. Your email is stored in your iOS app's local AuthManager, not on our backend.")
            ]),
            .init(number: 6, heading: "Subscriptions, packs, and Apple's role", blocks: [
                .paragraph("KittyScan offers a free tier (3 lifetime analyses), one-time analysis packs (10 or 30 analyses), and a monthly Pro subscription. **All payments are processed by Apple via the App Store** — we never see your card number, address, or Apple ID."),
                .paragraph("After a purchase, Apple sends our backend a **signed receipt** (a JWS) containing: the transaction ID, the product ID (`monthly`/`pack10`/`pack30`), the Account Token we sent earlier, and the expiration date if it's a subscription. We verify the signature against Apple's public certificate chain and update your entitlement record accordingly."),
                .paragraph("We do **not** receive: your Apple ID email, your billing address, your card brand, or your transaction price (only the product ID — pricing is handled by Apple)."),
                .paragraph("If you cancel or refund a subscription, Apple sends us a Server Notification (also signed); we revoke your entitlement immediately upon verifying it.")
            ]),
            .init(number: 7, heading: "Sub-processors we rely on", blocks: [
                .paragraph("We use these third parties (\"sub-processors\") to deliver KittyScan. We've intentionally kept this list minimal:"),
                .paragraph("**Anthropic, PBC** — Provides the AI model that generates the health reports. Receives: your photo and the prompt (which contains cat metadata). Per Anthropic's commercial Zero Data Retention default, your inputs are not used for model training and are not retained beyond the request."),
                .link("Anthropic Privacy Policy", "https://www.anthropic.com/legal/privacy"),
                .paragraph("**Cloudflare, Inc.** — Hosts our Worker (the API gateway) and KV namespace (rate-limit + entitlement storage). Receives: photos in transit, your IP address (for routing/DDoS protection only), your Account Token and Device ID."),
                .link("Cloudflare Privacy Policy", "https://www.cloudflare.com/privacypolicy/"),
                .paragraph("**Apple, Inc.** — Handles payments, App Store distribution, Sign in with Apple. See Apple's Privacy Policy."),
                .paragraph("**Google LLC** — If you use Sign in with Google, Google sees your sign-in event and shares your email/display name with the app. See Google's Privacy Policy."),
                .paragraph("We have no other sub-processors. We do not sell, rent, or share your data with anyone outside this list.")
            ]),
            .init(number: 8, heading: "How long we keep things", blocks: [
                .bullets([
                    "**Locally on your device**: Until you delete the record, sign out, or uninstall the app. SwiftData persists across launches.",
                    "**Rate-limit counters (Cloudflare KV)**: ≤ 40 days then auto-expire.",
                    "**Entitlement records**: As long as your subscription is active, plus 90 days after expiry/cancellation for billing reconciliation. After 90 days, deleted permanently.",
                    "**Transaction-applied de-dup keys**: 90 days then auto-expire.",
                    "**Aggregate cost ledger**: ~70 days. Anonymous and per-month, never per-user.",
                    "**Photos in transit**: Fewer than 60 seconds — only while a single request is in flight.",
                    "**Anthropic-side retention**: Per their policy. We don't control this beyond opting into Zero Data Retention."
                ])
            ]),
            .init(number: 9, heading: "Your rights", blocks: [
                .paragraph("Whether you're in the US, EU/UK, or California, you have these controls:"),
                .bullets([
                    "**Access / view**: Settings → Edit profile shows everything we have on-device about you.",
                    "**Export**: Settings → Export my data produces a JSON file of all your cats and analysis history.",
                    "**Correct**: Edit any cat profile in-app at any time.",
                    "**Delete**: Settings → Delete account wipes all local data, your Device ID, and your Account Token. We then send a deletion request to our backend; within 24 hours your entitlement and counter records are removed (kept just long enough to honor any open subscription).",
                    "**Portability**: The export file is plain JSON — it can be opened by any other app or text editor.",
                    "**Object / restrict**: You can revoke our processing by deleting the app or your account. We don't run any processing that continues after that.",
                    "**Withdraw consent**: Settings → Privacy → Revoke. The app re-presents this notice on next launch."
                ]),
                .paragraph("**California (CCPA / CPRA):** We do not \"sell\" your data, do not share it for cross-context behavioral advertising, and do not run targeted advertising. You have the rights listed above; to exercise them, use the in-app controls or contact us at the email below."),
                .paragraph("**EU/UK (GDPR):** The legal basis for processing is performance of the service contract (when you submit a photo, you've requested an analysis). We are the data controller; Anthropic and Cloudflare are processors under contract. You have the rights listed above plus the right to lodge a complaint with your supervisory authority.")
            ]),
            .init(number: 10, heading: "Security", blocks: [
                .bullets([
                    "**In transit**: All communication uses HTTPS (TLS 1.2+). iOS App Transport Security (ATS) is enabled — the app refuses non-HTTPS connections.",
                    "**At rest on your device**: SwiftData uses iOS file protection. Sensitive identifiers (Device ID, login session token) live in the iOS Keychain (hardware-backed on devices with Secure Enclave).",
                    "**At rest on our backend**: Cloudflare KV is encrypted at rest by Cloudflare. We store no raw secrets in code or logs.",
                    "**Server credentials (our Anthropic and Apple API keys)**: Stored exclusively in Cloudflare's secret store; never embedded in the iOS app, never written to disk on our side, never logged. We rotate them periodically and after any suspected exposure.",
                    "**No persistent photo storage**: We have no S3 / R2 / database table that holds your images. The photo only ever exists in the request body for the few seconds it's in flight.",
                    "**Subscription receipts**: Verified against Apple's signing certificate before we change your entitlement state — a forged purchase request cannot grant Pro."
                ])
            ]),
            .init(number: 11, heading: "What we DON'T do — explicit list", blocks: [
                .paragraph("To remove ambiguity, here's what's affirmatively NOT happening in KittyScan:"),
                .bullets([
                    "We do NOT run analytics SDKs (no Firebase, Mixpanel, Amplitude, Sentry, etc.)",
                    "We do NOT run crash reporters that send data off-device",
                    "We do NOT use advertising identifiers, attribution SDKs, or fingerprinting",
                    "We do NOT track you across other apps or websites",
                    "We do NOT store your photos on any server — they exist only on your phone",
                    "We do NOT use your photos or chats to train AI models. Anthropic's commercial terms confirm this for them; we ourselves don't train any model",
                    "We do NOT share data with parents, partners, or affiliates — we have none",
                    "We do NOT sell data, period"
                ])
            ]),
            .init(number: 12, heading: "Children", blocks: [
                .paragraph("KittyScan is not directed at children under 13 (or under 16 in EU jurisdictions where that's the consent floor). We do not knowingly collect personal information from children. If a parent or guardian believes a child has used KittyScan, contact us and we'll delete the associated data immediately.")
            ]),
            .init(number: 13, heading: "International transfers", blocks: [
                .paragraph("Our backend (Cloudflare) operates globally; your requests may be routed through whichever Cloudflare data center is geographically nearest you. The persistent ledger lives in Cloudflare's distributed KV (multi-region). Anthropic's processing typically occurs in the US. By using KittyScan from outside the US, you understand and accept that your data is processed in the US and other countries.")
            ]),
            .init(number: 14, heading: "Changes to this policy", blocks: [
                .paragraph("If we make material changes (new sub-processors, new data categories, expanded purposes), we will: (1) bump the version number in this document, (2) prompt you to re-consent in the app before the change takes effect, and (3) preserve your data exactly as before in the meantime. Non-material changes (typo fixes, clarifications) may be made silently.")
            ]),
            .init(number: 15, heading: "Contact", blocks: [
                .paragraph("Privacy questions, deletion requests, or anything else: open the app, go to **Settings → Send Feedback**, and submit a message. We read every one."),
                .paragraph("We deliberately don't publish a personal email here to protect against spam — but the in-app form goes directly to the developer."),
                .paragraph("If you're an EU/UK resident and aren't satisfied with our response, you may file a complaint with your local data protection authority.")
            ]),
        ]
    )

    // ================================================================
    // PRIVACY — Chinese
    // ================================================================
    private static let privacyZH = PolicyDoc(
        title: "KittyScan 隐私政策",
        effectiveDate: effectiveDateZh,
        sections: [
            .init(number: 1, heading: "我们是谁", blocks: [
                .paragraph("KittyScan(下称\"我们\"\"本 App\")是一款个人猫咪健康 App,运营主体位于美国加州。本政策用直白的话说明我们收集什么、为什么收集、谁还会看到、你有哪些控制权。")
            ]),
            .init(number: 2, heading: "我们的原则", blocks: [
                .paragraph("整款 App 的设计围绕三条原则:"),
                .bullets([
                    "**本地优先。** 你的猫档案、照片、分析记录、聊天对话都存在**你自己的设备**上。我们没有副本。",
                    "**化名化。** 我们的服务器看到的关于你的全部信息,只是 App 第一次启动时随机生成的两个 UUID。你的真名、邮箱、电话从不到达我们的后端。",
                    "**永远没有广告。** 不投放广告、不跟广告网络共享数据、不使用广告标识符(IDFA)。我们的全部收入来自可选的订阅和次卡。"
                ])
            ]),
            .init(number: 3, heading: "我们收集什么 —— 以及它存在哪里", blocks: [
                .paragraph("**只存在你设备上的:**"),
                .bullets([
                    "猫档案(名字、品种、年龄、是否绝育、已知问题、头像)",
                    "你提交分析的猫咪照片",
                    "所有 AI 生成的健康报告、分项评分、警告",
                    "AI 聊天追问的对话记录",
                    "你给某次检测加的备注(\"今天没怎么吃饭\"之类)",
                    "免费次数计数 + 次卡余额",
                    "语言和主题偏好",
                    "登录会话 token(用 Apple/Google 登录后)"
                ]),
                .paragraph("**只在一次请求期间发到我们后端(Cloudflare Worker)的:**"),
                .bullets([
                    "照片本身(只在我们转发给 Anthropic 期间存在 —— 见 §4)",
                    "猫咪元数据(名字、品种、年龄)—— 让 AI 报告能结合具体情况",
                    "你的 Account Token(随机 UUID,见 §5)",
                    "你的 Device ID(另一个随机 UUID,见 §5)"
                ]),
                .paragraph("**长期存在我们后端的:**"),
                .bullets([
                    "按设备的限流计数器(≤ 40 天自动过期)",
                    "按 Account Token 的订阅状态:套餐档位、剩余额度、当前账单周期起点(用来判断你能否再做一次分析)",
                    "**匿名**的月度 token 用量汇总(用于对账,无法关联到具体用户)"
                ]),
                .paragraph("**当你订阅或购买次卡时,由 Apple 保存(不在我们这):**"),
                .bullets([
                    "你的 Apple ID、支付方式、消费历史 —— 我们看不到这些。Apple 处理整个交易。",
                    "我们只收到一个交易 ID 和我们之前发出的 Account Token,据此把你的订阅档位激活。"
                ]),
                .paragraph("**我们绝对不收集的:**"),
                .bullets([
                    "真实姓名、手机号、地址、支付信息",
                    "地理位置 / GPS / 基于 IP 的位置(IP 在请求时短暂可见于 Cloudflare 用于路由和反滥用,不会跟你的账号绑定保留)",
                    "通讯录、日历、麦克风、HealthKit 数据",
                    "广告标识符(IDFA、Google Ad ID)",
                    "包含个人数据的崩溃日志 —— 我们没装崩溃上报",
                    "行为分析(没有 Firebase / Mixpanel / Amplitude / Sentry 等)"
                ])
            ]),
            .init(number: 4, heading: "一张照片的完整旅程", blocks: [
                .paragraph("点\"分析\"那一刻起,具体发生了什么:"),
                .paragraph("**1.** 从相机或相册取一张照片(我们一次性向 iOS 申请权限)。"),
                .paragraph("**2.** 先在你手机上做本地检测:用 Apple Vision 框架判断是否有猫、画面是否过暗或过曝。**这一步全在本地跑,什么都不发出去**。如果不合格,我们直接提示你重拍,根本不会发起任何网络请求。"),
                .paragraph("**3.** 再在本地做一次 \"是不是同一只猫\" 的视觉对比(Vision feature print 跟你之前的照片比较)。**也全在本地**。"),
                .paragraph("**4.** 两步检查通过后,iOS App 通过 HTTPS 把以下内容发到我们的 Cloudflare Worker(`carmel-worker.workers.dev/analyze`):JPEG 压缩后的照片(base64)、分析 prompt、Account Token、Device ID。"),
                .paragraph("**5.** Worker 校验你的订阅档位和限流配额。如果通过,它把照片和 prompt 通过 HTTPS 转发给 **Anthropic 的 Claude API**,使用我们服务端持有的 API key 鉴权(这把 key 永远不会出现在你的 App 里)。"),
                .paragraph("**6.** Claude 返回一份 JSON 健康报告。Worker 把它返回给你的 App,然后从内存里丢掉这张照片。**照片不会写入我们任何磁盘,不会被记录到日志**。"),
                .paragraph("**7.** 你的 App 把照片和报告写入本地 SwiftData 数据库,屏幕上渲染结果。"),
                .callout("**整个过程中,照片在我们服务器上停留几秒钟,从不持久化。我们留下的只是这两个计数器:\"这个账号又跑了一次分析\"\"这个设备在这个时间访问过\"。没有图像、没有 prompt 内容、没有报告内容。**")
            ]),
            .init(number: 5, heading: "我们用的两个标识符,各自暴露什么", blocks: [
                .paragraph("我们用两个化名标识符 —— 都是 App 第一次启动时随机生成的 UUID。除非你订阅(那时 Apple —— 不是我们 —— 会把它和你的 Apple ID 绑定用于结算),否则它们都跟你真实身份无关。"),
                .paragraph("**Device ID。** 生成后存在 iOS Keychain,仅用作我们按设备限流计数器的 key。你卸载 App 或抹机就毁掉它。我们无法用它跨设备追踪你、跨重装追踪你、或关联到现实身份。"),
                .paragraph("**Account Token。** 另一个 UUID,我们在订阅交易时塞给 Apple。你买订阅时,Apple 会把这个 UUID 写进交易凭证,我们后端因此能在凭证回流时知道该激活哪个账号的订阅。这个 token 除了在 HTTPS 请求里发到我们 Worker 之外,从不离开你设备。**它不和你的姓名、邮箱、任何身份提供商账号关联**。"),
                .paragraph("如果你用 Apple 或 Google 登录,身份提供商知道你的邮箱;我们只收到显示名(用来在 App 界面里称呼你)。**邮箱只存在你 iOS App 本地的 AuthManager,从不上我们后端**。")
            ]),
            .init(number: 6, heading: "订阅、次卡和 Apple 的角色", blocks: [
                .paragraph("KittyScan 提供:免费档(终身 3 次分析)、一次性次卡(10 次或 30 次)、月度 Pro 订阅。**所有付款都由 Apple 经 App Store 处理 —— 我们看不到你的卡号、地址、Apple ID**。"),
                .paragraph("购买完成后,Apple 给我们后端发一份**签名凭证(JWS)**,内含交易 ID、产品 ID(`monthly`/`pack10`/`pack30`)、我们之前发的 Account Token、订阅到期时间(如果是订阅)。我们用 Apple 的公钥证书链验签,然后据此更新你的订阅档位记录。"),
                .paragraph("我们**收不到**:你的 Apple ID 邮箱、账单地址、卡的发卡机构、交易金额(只能看到产品 ID,实际定价由 Apple 处理)。"),
                .paragraph("如果你取消或退款订阅,Apple 会发一条 Server Notification(也是签名的);我们验签通过后立即撤销你的 Pro 权益。")
            ]),
            .init(number: 7, heading: "我们使用的子处理方", blocks: [
                .paragraph("我们故意把这个名单压到最少:"),
                .paragraph("**Anthropic, PBC** —— 提供 AI 模型生成健康报告。收到:你的照片和 prompt(prompt 里包含猫咪元数据)。按 Anthropic 商业 Zero Data Retention 默认条款,**你的输入不会用于模型训练,也不会在请求结束后保留**。"),
                .link("Anthropic 隐私政策", "https://www.anthropic.com/legal/privacy"),
                .paragraph("**Cloudflare, Inc.** —— 托管我们的 Worker(API 网关)和 KV 命名空间(限流和订阅状态存储)。收到:传输中的照片、你的 IP(仅用于路由和 DDoS 防护)、你的 Account Token 和 Device ID。"),
                .link("Cloudflare 隐私政策", "https://www.cloudflare.com/privacypolicy/"),
                .paragraph("**Apple, Inc.** —— 处理付款、App Store 分发、Sign in with Apple。参见 Apple 隐私政策。"),
                .paragraph("**Google LLC** —— 如果你用 Sign in with Google,Google 知道这次登录事件,并和 App 共享你的邮箱和显示名。参见 Google 隐私政策。"),
                .paragraph("**没有别的子处理方**。我们不出售、不出租、不和上述名单之外的任何方共享你的数据。")
            ]),
            .init(number: 8, heading: "我们各类数据保留多久", blocks: [
                .bullets([
                    "**你设备上**:直到你删记录、退出登录、卸载 App。SwiftData 跨启动持久化。",
                    "**限流计数器(Cloudflare KV)**:≤ 40 天后自动过期。",
                    "**订阅档位记录**:订阅生效期间保留;到期/取消后再保留 90 天用于结算对账,然后永久删除。",
                    "**交易去重 key**:90 天后自动过期。",
                    "**月度成本汇总**:~70 天。匿名、按月,从不按用户。",
                    "**传输中的照片**:不到 60 秒 —— 仅在单次请求飞行期间。",
                    "**Anthropic 一侧的保留**:按其政策。我们除了启用 Zero Data Retention 之外不能控制。"
                ])
            ]),
            .init(number: 9, heading: "你的权利", blocks: [
                .paragraph("无论你身处美国、欧盟/英国、还是加州,你都有以下控制权:"),
                .bullets([
                    "**查看**:设置 → 编辑档案,显示我们设备上关于你的全部信息。",
                    "**导出**:设置 → 导出我的数据,得到 JSON 格式的全部猫咪和分析历史。",
                    "**修正**:在 App 里随时编辑任何猫档案。",
                    "**删除**:设置 → 删除账号,清空所有本地数据 + 你的 Device ID + Account Token。然后我们向后端发一次删除请求,24 小时内你的订阅记录和计数器记录被清除(只在还有未过期订阅时短暂保留以履行义务)。",
                    "**可携性**:导出文件是纯 JSON,任何 App 或文本编辑器都能打开。",
                    "**反对/限制处理**:删 App 或删账号即可终止我们的处理。我们没有任何在你删除后还会继续的处理流程。",
                    "**撤回同意**:设置 → 隐私 → 撤回。下次启动时 App 会重新展示本政策。"
                ]),
                .paragraph("**加州(CCPA / CPRA)**:我们**不\"出售\"**你的数据,**不**为跨上下文行为广告共享数据,**不**做定向广告。如要行使权利,使用 App 内控件或邮件联系我们(见 §15)。"),
                .paragraph("**欧盟/英国(GDPR)**:处理的法律依据是履行服务合同(你提交照片即表示请求一次分析)。我们是数据控制者;Anthropic 和 Cloudflare 是受合同约束的处理者。除上述权利外,你还有权向当地数据保护机构投诉。")
            ]),
            .init(number: 10, heading: "安全", blocks: [
                .bullets([
                    "**传输中**:全程 HTTPS(TLS 1.2+)。iOS App Transport Security(ATS)开启 —— App 拒绝任何非 HTTPS 连接。",
                    "**你设备上的静态数据**:SwiftData 启用 iOS file protection。敏感标识符(Device ID、登录会话 token)存在 iOS Keychain(支持 Secure Enclave 的设备上由硬件加密)。",
                    "**我们后端的静态数据**:Cloudflare KV 在 Cloudflare 一侧默认加密。代码和日志里**不保存任何明文密钥**。",
                    "**我们的服务端凭证(Anthropic 和 Apple 的 API key)**:仅存在 Cloudflare 的 secret store,**永远不会嵌入 iOS App、不写盘、不打日志**。我们定期轮换,任何疑似泄露后立即作废重发。",
                    "**没有持久化的照片存储**:我们没有任何 S3 / R2 / 数据库表保存你的图像。照片只在请求飞行的几秒钟里存在于内存。",
                    "**订阅凭证验证**:在改变你的订阅状态之前,先用 Apple 的签名证书验签,**伪造的购买请求无法解锁 Pro**。"
                ])
            ]),
            .init(number: 11, heading: "我们明确不做的事(列清单)", blocks: [
                .paragraph("为了消除歧义,这是 KittyScan 明确**不**会发生的事:"),
                .bullets([
                    "**不**集成任何分析 SDK(没有 Firebase、Mixpanel、Amplitude、Sentry 等)",
                    "**不**接入会上报数据的崩溃报告器",
                    "**不**使用广告标识符、归因 SDK、或设备指纹",
                    "**不**跨 App 或网站追踪你",
                    "**不**把你的照片存到任何服务器 —— 它们只在你手机上",
                    "**不**用你的照片或聊天训练 AI 模型。Anthropic 商业条款已确认其侧不训练;我们自己不训练任何模型",
                    "**不**和母公司、合作伙伴、关联方共享数据 —— 我们没有这些",
                    "**不**出售数据,绝对不"
                ])
            ]),
            .init(number: 12, heading: "未成年人", blocks: [
                .paragraph("KittyScan 不针对 13 岁以下儿童(欧盟某些司法辖区下沉到 16 岁)。我们不会有意收集儿童个人信息。如果家长或监护人认为有儿童使用了 KittyScan,请联系我们,我们会立即删除相关数据。")
            ]),
            .init(number: 13, heading: "跨境传输", blocks: [
                .paragraph("我们后端(Cloudflare)是全球分发的,你的请求会被路由到地理上最近的 Cloudflare 数据中心。持久化的账本存在 Cloudflare 的多区域 KV 里。Anthropic 的处理通常发生在美国境内。**在美国境外使用 KittyScan 即表示你理解并接受你的数据可能在美国及其他国家被处理**。")
            ]),
            .init(number: 14, heading: "本政策的变更", blocks: [
                .paragraph("如果有实质性变更(新增子处理方、新增数据类别、扩大用途),我们会:(1)在文档顶部 bump 版本号,(2)在 App 里提示你重新同意后才生效,(3)在此期间保持你已有数据原样不动。非实质性变更(错别字、措辞优化)可能静默更新。")
            ]),
            .init(number: 15, heading: "联系我们", blocks: [
                .paragraph("隐私问题、删除请求、其他任何反馈:打开 App → **设置 → 提交问题 / 反馈**,直接发给开发者。我们每一条都看。"),
                .paragraph("我们刻意不在这里公开个人邮箱以避免垃圾邮件 —— 但 App 内的表单直接送达开发者本人。"),
                .paragraph("如果你是欧盟/英国居民且对我们的回复不满意,可以向当地数据保护机构投诉。")
            ]),
        ]
    )

    // ================================================================
    // TERMS — English
    // ================================================================
    private static let termsEN = PolicyDoc(
        title: "KittyScan Terms of Service",
        effectiveDate: effectiveDateEn,
        sections: [
            .init(number: 1, heading: "Agreement", blocks: [
                .paragraph("By using KittyScan (\"the app\"), you agree to these Terms. If you don't agree, please don't use the app.")
            ]),
            .init(number: 2, heading: "What KittyScan does", blocks: [
                .paragraph("KittyScan is a personal cat health diary with AI-powered photo analysis. It is for entertainment and reference use only.")
            ]),
            .init(number: 3, heading: "NOT veterinary advice — IMPORTANT", blocks: [
                .callout("The AI analysis is NOT medical or veterinary advice. It is generated by a large language model (Anthropic's Claude) and may be inaccurate, incomplete, or wrong. Do NOT use KittyScan as a substitute for a real veterinarian."),
                .paragraph("If your cat shows signs of distress (labored breathing, bleeding, seizure, severe lethargy, unconsciousness, etc.), **contact a veterinarian immediately**."),
                .paragraph("We are not liable for decisions you make based on KittyScan's output.")
            ]),
            .init(number: 4, heading: "Acceptable use", blocks: [
                .paragraph("You agree NOT to:"),
                .bullets([
                    "Upload photos that aren't your own or that you don't have permission to analyze",
                    "Submit abusive, illegal, or NSFW content",
                    "Reverse engineer, scrape, or overload the service",
                    "Try to extract our API keys or bypass rate limits"
                ]),
                .paragraph("Free tier: 3 analyses per day, 10 per month. We may change these limits with notice.")
            ]),
            .init(number: 5, heading: "Your content", blocks: [
                .paragraph("You retain all rights to your photos and data. You grant us a limited, worldwide license to process your photos for the sole purpose of providing the service (i.e., sending them to Anthropic for analysis and returning the result).")
            ]),
            .init(number: 6, heading: "Service availability", blocks: [
                .bullets([
                    "Service is provided \"as is\" without warranty.",
                    "We don't guarantee uptime or feature continuity.",
                    "We may modify, suspend, or discontinue features with reasonable notice."
                ])
            ]),
            .init(number: 7, heading: "Limitation of liability", blocks: [
                .paragraph("To the fullest extent permitted by California law, our total liability to you is limited to **USD $0** (KittyScan is free). We disclaim all implied warranties.")
            ]),
            .init(number: 8, heading: "Termination", blocks: [
                .paragraph("You can delete your account anytime via Settings. We may suspend or terminate accounts that violate these Terms.")
            ]),
            .init(number: 9, heading: "Governing law", blocks: [
                .paragraph("These Terms are governed by the laws of the **State of California, USA**, without regard to conflict-of-law rules. Disputes shall be resolved exclusively in state or federal courts located in **Santa Clara County, California**, and you consent to personal jurisdiction there.")
            ]),
            .init(number: 10, heading: "Changes", blocks: [
                .paragraph("We may update these Terms. Material changes will require re-consent in the app.")
            ]),
            .init(number: 11, heading: "Contact", blocks: [
                .paragraph("Questions? Open the app and go to **Settings → Send Feedback**.")
            ]),
        ]
    )

    // ================================================================
    // TERMS — Chinese
    // ================================================================
    private static let termsZH = PolicyDoc(
        title: "KittyScan 服务协议",
        effectiveDate: effectiveDateZh,
        sections: [
            .init(number: 1, heading: "协议", blocks: [
                .paragraph("使用 KittyScan(下称\"本 App\")即表示你同意本协议。不同意请不要使用。")
            ]),
            .init(number: 2, heading: "KittyScan 是什么", blocks: [
                .paragraph("KittyScan 是一款个人猫咪健康日记,带 AI 拍照分析功能。**仅供娱乐和参考**。")
            ]),
            .init(number: 3, heading: "不是兽医建议 —— 重要", blocks: [
                .callout("**AI 分析不是医学或兽医建议**。它由大语言模型(Anthropic 的 Claude)生成,**可能不准确、不完整或错误**。不要用 KittyScan 代替真实兽医。"),
                .paragraph("如你家猫出现异常(呼吸急促、出血、抽搐、严重萎靡、失去意识等),**请立即联系兽医**。"),
                .paragraph("你基于 KittyScan 输出做的决定,后果自负。")
            ]),
            .init(number: 4, heading: "使用规范", blocks: [
                .paragraph("你同意**不**:"),
                .bullets([
                    "上传非你本人的猫的照片,或未经授权的",
                    "提交非法、滥用、不适宜内容",
                    "反编译、抓取或压垮服务",
                    "尝试获取我们的 API key 或绕过限流"
                ]),
                .paragraph("免费额度:每天 3 次分析,每月 10 次。我们可以在通知后调整。")
            ]),
            .init(number: 5, heading: "你的内容", blocks: [
                .paragraph("你保留照片和数据的所有权利。你授予我们一个有限、全球范围的许可,**仅用于处理你的照片以提供服务**(即发给 Anthropic 分析并返回结果)。")
            ]),
            .init(number: 6, heading: "服务可用性", blocks: [
                .bullets([
                    "服务按\"现状\"提供,无任何保证。",
                    "我们不保证 uptime 或功能连续性。",
                    "我们可以在合理通知后修改、暂停或终止功能。"
                ])
            ]),
            .init(number: 7, heading: "责任限制", blocks: [
                .paragraph("在加州法律允许的最大范围内,我们对你的总责任限于 **0 美元**(KittyScan 免费)。我们不承担任何默示担保。")
            ]),
            .init(number: 8, heading: "终止", blocks: [
                .paragraph("你可以随时在设置里删除账号。我们可以在你违反本协议时暂停或终止账号。")
            ]),
            .init(number: 9, heading: "管辖", blocks: [
                .paragraph("本协议受 **美国加州** 法律管辖,不考虑法律冲突规则。争议应在 **加州圣克拉拉县** 的州法院或联邦法院专属解决,你同意接受该法院的属人管辖。")
            ]),
            .init(number: 10, heading: "变更", blocks: [
                .paragraph("我们可能更新本协议。重大变更需要你在 App 里重新同意。")
            ]),
            .init(number: 11, heading: "联系我们", blocks: [
                .paragraph("问题?打开 App → **设置 → 提交问题 / 反馈**。")
            ]),
        ]
    )
}

// =========================================================
// Consent state (UserDefaults)
// =========================================================
enum Consent {
    private static let privacyKey = "consent.privacy.\(Policies.version).acceptedAt"
    private static let tosKey     = "consent.tos.\(Policies.version).acceptedAt"

    static var hasAccepted: Bool {
        UserDefaults.standard.string(forKey: privacyKey) != nil
            && UserDefaults.standard.string(forKey: tosKey) != nil
    }

    static var acceptedAt: Date? {
        guard let s = UserDefaults.standard.string(forKey: privacyKey) else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    static func recordAcceptance() {
        let now = ISO8601DateFormatter().string(from: Date())
        UserDefaults.standard.set(now, forKey: privacyKey)
        UserDefaults.standard.set(now, forKey: tosKey)
    }

    static func revoke() {
        UserDefaults.standard.removeObject(forKey: privacyKey)
        UserDefaults.standard.removeObject(forKey: tosKey)
    }
}
