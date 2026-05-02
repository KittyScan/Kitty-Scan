import UIKit
import SwiftUI

// =========================================================
// CatCardView — 1080 × 1920 portrait poster (9:16, Instagram/朋友圈 ready).
//
// Sections (top → bottom):
//   1. Themed gradient header
//   2. Sketched portrait of the user's own photo (Core Image color-dodge)
//      — falls back to a big initial letter when the user has no avatar
//   3. Name + breed pill + theme mood
//   4. Score block: big ring + 4 sub-score mini bars
//   5. Warnings card (red, only if latest report has any)
//   6. Trend mini-sparkline (only with 2+ records)
//   7. Advice strip: top 1-2 suggestions from the latest report
//   8. Stats row: total checks · days tracked · avg score
//   9. Footer: KittyScan brand + export date
//
// Drawing pipeline: pure CoreGraphics (UIGraphicsImageRenderer). The previous
// SwiftUI ImageRenderer hung the main thread mid-export — CG primitives are
// boring but bulletproof.
// =========================================================
/// Sendable snapshot of everything `renderPNG` needs. Built on the main
/// actor (where SwiftData reads are safe), then handed across an actor
/// boundary so the actual rendering can run on a background priority queue.
/// This is the fix for the export flow's "white screen" hang — without it,
/// every `cat.records[*].healthScore` read happens on the main thread
/// inside the render loop, freezing SwiftUI's compositor.
struct CardInput: Sendable {
    let name: String
    let breed: String?
    let avatarData: Data?
    let theme: CatTheme
    let recordCount: Int
    let sinceCreatedDays: Int
    let latestScore: Int?
    let exportDateText: String
    let zh: Bool

    let latestWarnings: [String]
    let latestSuggestions: [String]
    let latestSubScores: SubScores?
    let scoreHistory: [Int]   // chronological (oldest → newest) for sparkline
    let avgScore: Int?

    @MainActor
    static func snapshot(cat: Cat,
                         records: [HistoryRecord],
                         theme: CatTheme,
                         recordCount: Int,
                         latestScore: Int?,
                         sinceCreatedDays: Int,
                         exportDateText: String,
                         zh: Bool) -> CardInput {
        let latest = records.first
        // records is newest-first; reverse for chronological history.
        let history = records.prefix(20).map(\.healthScore).reversed()
        let avg: Int? = history.isEmpty ? nil : Array(history).reduce(0, +) / history.count
        let subs: SubScores? = {
            guard let l = latest,
                  let e = l.eyesScore, let f = l.furScore,
                  let p = l.postureScore, let n = l.energyScore else { return nil }
            return SubScores(eyes: e, fur: f, posture: p, energy: n)
        }()
        return CardInput(
            name: cat.name, breed: cat.breed, avatarData: cat.avatarData,
            theme: theme, recordCount: recordCount,
            sinceCreatedDays: sinceCreatedDays, latestScore: latestScore,
            exportDateText: exportDateText, zh: zh,
            latestWarnings: latest?.warnings ?? [],
            latestSuggestions: latest?.suggestions ?? [],
            latestSubScores: subs,
            scoreHistory: Array(history),
            avgScore: avg
        )
    }
}

enum CatCardView {

    /// Background-safe entry point. Renders entirely off the main actor —
    /// CGContext, UIGraphicsImageRenderer, Core Image, and PNG encoding are
    /// all thread-safe in modern iOS.
    static func renderPNG(input: CardInput) -> Data? {
        let size = CGSize(width: 1080, height: 1920)
        print("[CatCard:\(input.name)] begin render")

        // CRITICAL: pin scale to 1.0. The renderer's default scale is the
        // device's screen scale (3x on most iPhones), which would silently
        // turn this 1080×1920 poster into a 3240×5760 bitmap — 9× the pixel
        // count, 9× the CPU work, and the cause of the "white screen" hang
        // during export. We're authoring at fixed pixel dimensions; we
        // don't want any retina multiplier on top.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let data = renderer.pngData { ctx in
            drawCard(cg: ctx.cgContext, size: size, input: input)
        }
        print("[CatCard:\(input.name)] done · \(data.count) bytes")
        return data
    }
}

// =========================================================
// Composition
// =========================================================
private func drawCard(cg: CGContext, size: CGSize, input: CardInput) {
    let rect = CGRect(origin: .zero, size: size)
    let theme = input.theme

    // ---- Background: full-bleed gradient ----
    cardFillDiagonalGradient(cg: cg, rect: rect,
                              from: theme.bg.uiSolid, to: theme.card.uiSolid)

    // ---- 1) Portrait (circle, hero) ----
    let portraitSize: CGFloat = 500
    let portraitRect = CGRect(
        x: (size.width - portraitSize) / 2,
        y: 130,
        width: portraitSize, height: portraitSize
    )
    cardDrawSketchPortrait(cg: cg, rect: portraitRect,
                           avatarData: input.avatarData,
                           name: input.name, theme: theme)

    // ---- 2) Name (huge, centered) ----
    cardDrawCenteredText(input.name,
                          center: CGPoint(x: rect.midX, y: portraitRect.maxY + 90),
                          font: .systemFont(ofSize: 116, weight: .bold),
                          color: theme.deep.uiSolid)

    // ---- 3) Breed pill + mood ----
    let pillsY = portraitRect.maxY + 180
    if let breed = input.breed {
        cardDrawPill(cg: cg, text: breed,
                      center: CGPoint(x: rect.midX - 130, y: pillsY),
                      font: .systemFont(ofSize: 34, weight: .medium),
                      bg: theme.deep.uiSolid,
                      fg: theme.bg.uiSolid)
    }
    cardDrawCenteredText(theme.mood(zh: input.zh),
                          center: CGPoint(x: rect.midX + 120, y: pillsY),
                          font: .systemFont(ofSize: 32),
                          color: theme.main.uiSolid)

    // ---- 4) Score block (ring + sub-scores) ----
    cardDrawScoreBlock(cg: cg,
                       origin: CGPoint(x: 60, y: 880),
                       width: size.width - 120,
                       subScores: input.latestSubScores,
                       latestScore: input.latestScore,
                       theme: theme,
                       zh: input.zh)

    // ---- 5) Warnings (only if present) ----
    var cursorY: CGFloat = 1290
    if !input.latestWarnings.isEmpty {
        let h = cardDrawWarningsBlock(cg: cg,
                                      origin: CGPoint(x: 60, y: cursorY),
                                      width: size.width - 120,
                                      warnings: Array(input.latestWarnings.prefix(2)),
                                      zh: input.zh)
        cursorY += h + 30
    }

    // ---- 6) Trend mini-chart (only with 2+ records) ----
    if input.scoreHistory.count >= 2 {
        let h = cardDrawTrendBlock(cg: cg,
                                   origin: CGPoint(x: 60, y: cursorY),
                                   width: size.width - 120,
                                   scores: input.scoreHistory,
                                   theme: theme,
                                   zh: input.zh)
        cursorY += h + 30
    }

    // ---- 7) Top suggestion (advice) ----
    if let first = input.latestSuggestions.first {
        let h = cardDrawAdviceBlock(cg: cg,
                                    origin: CGPoint(x: 60, y: cursorY),
                                    width: size.width - 120,
                                    suggestion: first,
                                    theme: theme,
                                    zh: input.zh)
        cursorY += h + 30
    }

    // ---- 8) Stats row (3 columns) ----
    cardDrawStatsRow(cg: cg,
                     origin: CGPoint(x: 60, y: 1730),
                     width: size.width - 120,
                     recordCount: input.recordCount,
                     avgScore: input.avgScore,
                     sinceCreatedDays: input.sinceCreatedDays,
                     theme: theme,
                     zh: input.zh)

    // ---- 9) Footer ----
    cardDrawCenteredText("🐾 KittyScan",
                          center: CGPoint(x: rect.midX, y: 1860),
                          font: .systemFont(ofSize: 36, weight: .semibold),
                          color: theme.deep.uiSolid)
    cardDrawCenteredText(input.exportDateText,
                          center: CGPoint(x: rect.midX, y: 1900),
                          font: .systemFont(ofSize: 24),
                          color: theme.main.uiSolid.withAlphaComponent(0.75))
}

// =========================================================
// Section: portrait (real photo, polish + Polaroid-style framing)
// =========================================================
private func cardDrawSketchPortrait(cg: CGContext, rect: CGRect,
                                     avatarData: Data?, name: String, theme: CatTheme) {
    // ---- 1) Soft drop shadow tinted to theme.deep ----
    // Drawing the shadow as a separate blurred ellipse below the portrait
    // gives a more controllable, brand-coherent look than CG's setShadow.
    let shadowRect = rect.offsetBy(dx: 0, dy: 18).insetBy(dx: -4, dy: -4)
    cg.saveGState()
    let shadowColor = theme.deep.uiSolid.withAlphaComponent(0.28)
    cg.setShadow(offset: CGSize(width: 0, height: 6), blur: 32, color: shadowColor.cgColor)
    shadowColor.setFill()
    cg.fillEllipse(in: shadowRect)
    cg.restoreGState()

    // ---- 2) Photo (clipped to circle) ----
    cg.saveGState()
    cg.addEllipse(in: rect)
    cg.clip()

    if let data = avatarData,
       let img = AvatarImage.decode(data: data, maxPixelSize: rect.width * 1.2) {
        // Subtle saturation / contrast bump so the cat pops on the poster.
        // Single CIColorControls pass at the *exact* draw size — no
        // oversampling, no wasted pixels.
        let polished = CatPortraitFilter.polish(img, outputSide: rect.width)
        polished.draw(in: rect)
    } else {
        // Fallback: themed initial when no photo exists.
        cardFillDiagonalGradient(cg: cg, rect: rect,
                                  from: theme.light.uiSolid, to: theme.card.uiSolid)
        cg.restoreGState()
        let letter = String(name.prefix(1))
        cardDrawCenteredText(letter,
                              center: CGPoint(x: rect.midX, y: rect.midY),
                              font: .systemFont(ofSize: rect.width * 0.42, weight: .bold),
                              color: theme.deep.uiSolid)
        // Apply the same two-tone framing to the fallback so it doesn't
        // look like a different style of avatar.
        drawPortraitFrame(cg: cg, rect: rect, theme: theme)
        return
    }
    cg.restoreGState()

    // ---- 3) Two-tone Polaroid-style outer frame ----
    drawPortraitFrame(cg: cg, rect: rect, theme: theme)
}

/// Concentric rings that act as a polaroid-style mat frame: a thick deep ring
/// for poster impact, then a thin background-colored gap, then a final hairline.
private func drawPortraitFrame(cg: CGContext, rect: CGRect, theme: CatTheme) {
    // Outer thick ring (theme.deep)
    cg.setStrokeColor(theme.deep.uiSolid.cgColor)
    cg.setLineWidth(10)
    cg.strokeEllipse(in: rect.insetBy(dx: 5, dy: 5))

    // Inner white gap (visual breathing room between photo and outer ring)
    cg.setStrokeColor(theme.bg.uiSolid.cgColor)
    cg.setLineWidth(3)
    cg.strokeEllipse(in: rect.insetBy(dx: 11, dy: 11))

    // Hairline accent
    cg.setStrokeColor(theme.main.uiSolid.withAlphaComponent(0.45).cgColor)
    cg.setLineWidth(1)
    cg.strokeEllipse(in: rect.insetBy(dx: 14, dy: 14))
}

// =========================================================
// Section: score block (big ring + 4 sub-score bars)
// =========================================================
private func cardDrawScoreBlock(cg: CGContext,
                                 origin: CGPoint,
                                 width: CGFloat,
                                 subScores: SubScores?,
                                 latestScore: Int?,
                                 theme: CatTheme,
                                 zh: Bool) {
    let height: CGFloat = 380
    let boxRect = CGRect(x: origin.x, y: origin.y, width: width, height: height)
    cardDrawRoundedBox(cg: cg, rect: boxRect, radius: 32,
                        fill: theme.bg.uiSolid.withAlphaComponent(0.7),
                        stroke: theme.light.uiSolid.withAlphaComponent(0.5),
                        lineWidth: 1)

    // Left: ring
    let ringSide: CGFloat = 280
    let ringRect = CGRect(x: boxRect.minX + 50,
                          y: boxRect.midY - ringSide / 2,
                          width: ringSide, height: ringSide)
    let score = latestScore ?? 0
    let band = ScoreBand(score: score)
    cardDrawScoreRing(cg: cg, rect: ringRect, score: score, color: band.uiColor)

    // Score number inside ring
    cardDrawCenteredText("\(score)",
                          center: CGPoint(x: ringRect.midX, y: ringRect.midY - 14),
                          font: .systemFont(ofSize: 116, weight: .bold),
                          color: band.uiColor)
    cardDrawCenteredText(scoreLabelText(band: band, zh: zh),
                          center: CGPoint(x: ringRect.midX, y: ringRect.midY + 80),
                          font: .systemFont(ofSize: 30, weight: .medium),
                          color: theme.main.uiSolid)

    // Right: 4 sub-score bars
    let barsLeft = ringRect.maxX + 60
    let barsRight = boxRect.maxX - 40
    var barY: CGFloat = boxRect.minY + 50
    let labels = zh ? ["眼睛", "毛发", "体态", "精神"]
                    : ["Eyes", "Fur", "Posture", "Energy"]
    let subValues: [Int?] = [
        subScores?.eyes, subScores?.fur, subScores?.posture, subScores?.energy
    ]
    for (i, label) in labels.enumerated() {
        cardDrawSubScoreBar(cg: cg,
                            x: barsLeft, y: barY,
                            width: barsRight - barsLeft,
                            label: label,
                            value: subValues[i],
                            theme: theme)
        barY += 70
    }
}

private func cardDrawScoreRing(cg: CGContext, rect: CGRect, score: Int, color: UIColor) {
    let lineWidth: CGFloat = 18
    let inner = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)

    // Track
    cg.setStrokeColor(color.withAlphaComponent(0.18).cgColor)
    cg.setLineWidth(lineWidth)
    cg.strokeEllipse(in: inner)

    // Filled arc
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = inner.width / 2
    let progress = max(0, min(1, CGFloat(score) / 100))
    let start: CGFloat = -.pi / 2
    let end = start + (2 * .pi * progress)
    cg.setStrokeColor(color.cgColor)
    cg.setLineWidth(lineWidth)
    cg.setLineCap(.round)
    cg.beginPath()
    cg.addArc(center: center, radius: radius,
              startAngle: start, endAngle: end, clockwise: false)
    cg.strokePath()
}

private func cardDrawSubScoreBar(cg: CGContext,
                                  x: CGFloat, y: CGFloat,
                                  width: CGFloat,
                                  label: String,
                                  value: Int?,
                                  theme: CatTheme) {
    let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
        .foregroundColor: theme.deep.uiSolid,
    ]
    (label as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: labelAttrs)

    let valueText = value.map { "\($0)" } ?? "—"
    let valueAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 28, weight: .bold),
        .foregroundColor: theme.deep.uiSolid,
    ]
    let vSize = (valueText as NSString).size(withAttributes: valueAttrs)
    (valueText as NSString).draw(
        at: CGPoint(x: x + width - vSize.width, y: y),
        withAttributes: valueAttrs
    )

    // Bar
    let barRect = CGRect(x: x, y: y + 36, width: width, height: 12)
    let bandColor = value.map { ScoreBand(score: $0).uiColor } ?? UIColor.gray
    cardDrawRoundedBox(cg: cg, rect: barRect, radius: 6,
                        fill: bandColor.withAlphaComponent(0.18),
                        stroke: nil, lineWidth: 0)
    if let value {
        let progress = CGFloat(max(0, min(100, value))) / 100
        let fillRect = CGRect(x: barRect.minX, y: barRect.minY,
                              width: barRect.width * progress, height: barRect.height)
        cardDrawRoundedBox(cg: cg, rect: fillRect, radius: 6,
                            fill: bandColor, stroke: nil, lineWidth: 0)
    }
}

// =========================================================
// Section: warnings, trend, advice, stats
// =========================================================
private func cardDrawWarningsBlock(cg: CGContext,
                                    origin: CGPoint,
                                    width: CGFloat,
                                    warnings: [String],
                                    zh: Bool) -> CGFloat {
    let pad: CGFloat = 26
    let title = zh ? "需要留意" : "Needs attention"
    let titleFont = UIFont.systemFont(ofSize: 32, weight: .bold)
    let bodyFont = UIFont.systemFont(ofSize: 28, weight: .semibold)

    // Measure body text height
    let bodyWidth = width - pad * 2 - 28  // minus left bullet space
    var bodyHeight: CGFloat = 0
    let bodySizes = warnings.map { item -> CGSize in
        let s = (item as NSString).boundingRect(
            with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: bodyFont],
            context: nil
        ).size
        bodyHeight += s.height + 12
        return s
    }
    let total = pad + 30 + 16 + bodyHeight + pad

    let box = CGRect(x: origin.x, y: origin.y, width: width, height: total)
    let danger = UIColor.systemRed
    cardDrawRoundedBox(cg: cg, rect: box, radius: 24,
                        fill: danger.withAlphaComponent(0.10),
                        stroke: danger.withAlphaComponent(0.35),
                        lineWidth: 1.5)

    // Title
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: titleFont, .foregroundColor: danger,
    ]
    (("⚠️  " + title) as NSString).draw(
        at: CGPoint(x: box.minX + pad, y: box.minY + pad),
        withAttributes: titleAttrs
    )

    // Bullets
    var y = box.minY + pad + 30 + 16
    for (i, item) in warnings.enumerated() {
        let bullet = "•"
        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont, .foregroundColor: danger,
        ]
        (bullet as NSString).draw(at: CGPoint(x: box.minX + pad, y: y), withAttributes: bulletAttrs)

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont, .foregroundColor: danger,
        ]
        (item as NSString).draw(
            with: CGRect(x: box.minX + pad + 28, y: y,
                         width: bodyWidth, height: bodySizes[i].height),
            options: [.usesLineFragmentOrigin],
            attributes: bodyAttrs,
            context: nil
        )
        y += bodySizes[i].height + 12
    }

    return total
}

private func cardDrawTrendBlock(cg: CGContext,
                                 origin: CGPoint,
                                 width: CGFloat,
                                 scores: [Int],   // chronological (oldest → newest)
                                 theme: CatTheme,
                                 zh: Bool) -> CGFloat {
    let height: CGFloat = 200
    let pad: CGFloat = 24
    let box = CGRect(x: origin.x, y: origin.y, width: width, height: height)
    cardDrawRoundedBox(cg: cg, rect: box, radius: 24,
                        fill: theme.bg.uiSolid.withAlphaComponent(0.7),
                        stroke: theme.light.uiSolid.withAlphaComponent(0.5),
                        lineWidth: 1)

    let title = zh ? "📈 健康趋势" : "📈 Health trend"
    (title as NSString).draw(
        at: CGPoint(x: box.minX + pad, y: box.minY + pad),
        withAttributes: [
            .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
            .foregroundColor: theme.deep.uiSolid,
        ]
    )

    // Sparkline area
    let chartRect = CGRect(x: box.minX + pad, y: box.minY + 70,
                           width: box.width - pad * 2, height: 100)
    guard scores.count >= 2 else { return height }

    // Reference band (70-90 healthy zone)
    let yForScore: (Int) -> CGFloat = { v in
        let clamped = CGFloat(max(0, min(100, v)))
        return chartRect.maxY - chartRect.height * (clamped / 100)
    }
    let bandRect = CGRect(x: chartRect.minX,
                          y: yForScore(90),
                          width: chartRect.width,
                          height: yForScore(70) - yForScore(90))
    UIColor.systemGreen.withAlphaComponent(0.10).setFill()
    UIBezierPath(rect: bandRect).fill()

    // Line + points
    let dx = chartRect.width / CGFloat(scores.count - 1)
    cg.setStrokeColor(theme.deep.uiSolid.cgColor)
    cg.setLineWidth(4)
    cg.setLineJoin(.round)
    cg.beginPath()
    for (i, s) in scores.enumerated() {
        let p = CGPoint(x: chartRect.minX + CGFloat(i) * dx, y: yForScore(s))
        if i == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
    }
    cg.strokePath()

    for (i, s) in scores.enumerated() {
        let p = CGPoint(x: chartRect.minX + CGFloat(i) * dx, y: yForScore(s))
        let dotColor = ScoreBand(score: s).uiColor
        let dot = CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
        dotColor.setFill()
        UIBezierPath(ovalIn: dot).fill()
    }

    return height
}

private func cardDrawAdviceBlock(cg: CGContext,
                                  origin: CGPoint,
                                  width: CGFloat,
                                  suggestion: String,
                                  theme: CatTheme,
                                  zh: Bool) -> CGFloat {
    let pad: CGFloat = 24
    let titleFont = UIFont.systemFont(ofSize: 30, weight: .semibold)
    let bodyFont = UIFont.systemFont(ofSize: 28)
    let bodyW = width - pad * 2

    let bodySize = (suggestion as NSString).boundingRect(
        with: CGSize(width: bodyW, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin],
        attributes: [.font: bodyFont],
        context: nil
    ).size

    let height = pad + 30 + 12 + bodySize.height + pad
    let box = CGRect(x: origin.x, y: origin.y, width: width, height: height)
    cardDrawRoundedBox(cg: cg, rect: box, radius: 24,
                        fill: theme.light.uiSolid.withAlphaComponent(0.35),
                        stroke: nil, lineWidth: 0)

    let title = zh ? "💡 给主人的建议" : "💡 For you"
    (title as NSString).draw(
        at: CGPoint(x: box.minX + pad, y: box.minY + pad),
        withAttributes: [.font: titleFont, .foregroundColor: theme.deep.uiSolid]
    )
    (suggestion as NSString).draw(
        with: CGRect(x: box.minX + pad, y: box.minY + pad + 30 + 12,
                     width: bodyW, height: bodySize.height),
        options: [.usesLineFragmentOrigin],
        attributes: [.font: bodyFont, .foregroundColor: theme.deep.uiSolid],
        context: nil
    )

    return height
}

private func cardDrawStatsRow(cg: CGContext,
                               origin: CGPoint,
                               width: CGFloat,
                               recordCount: Int,
                               avgScore: Int?,
                               sinceCreatedDays: Int,
                               theme: CatTheme,
                               zh: Bool) {
    let height: CGFloat = 100
    let box = CGRect(x: origin.x, y: origin.y, width: width, height: height)
    cardDrawRoundedBox(cg: cg, rect: box, radius: 24,
                        fill: theme.bg.uiSolid.withAlphaComponent(0.7),
                        stroke: theme.light.uiSolid.withAlphaComponent(0.5),
                        lineWidth: 1)

    let third = box.width / 3
    cardDrawBigStat(value: "\(recordCount)",
                     label: zh ? "次检测" : "Checks",
                     center: CGPoint(x: box.minX + third * 0.5, y: box.midY),
                     theme: theme)
    cardDrawVertDivider(cg: cg, x: box.minX + third,
                         yCenter: box.midY, length: 60,
                         color: theme.light.uiSolid.withAlphaComponent(0.5))
    cardDrawBigStat(value: avgScore.map { "\($0)" } ?? "—",
                     label: zh ? "平均分" : "Avg",
                     center: CGPoint(x: box.minX + third * 1.5, y: box.midY),
                     theme: theme)
    cardDrawVertDivider(cg: cg, x: box.minX + third * 2,
                         yCenter: box.midY, length: 60,
                         color: theme.light.uiSolid.withAlphaComponent(0.5))
    cardDrawBigStat(value: "\(sinceCreatedDays)",
                     label: zh ? "天陪伴" : "Days",
                     center: CGPoint(x: box.minX + third * 2.5, y: box.midY),
                     theme: theme)
}

private func scoreLabelText(band: ScoreBand, zh: Bool) -> String {
    switch band {
    case .excellent: return zh ? "优秀" : "Excellent"
    case .good:      return zh ? "良好" : "Good"
    case .fair:      return zh ? "一般" : "Fair"
    case .critical:  return zh ? "需关注" : "Attention"
    }
}

// =========================================================
// Generic helpers
// =========================================================

private func cardDrawBigStat(value: String, label: String, center: CGPoint, theme: CatTheme) {
    cardDrawCenteredText(value,
                          center: CGPoint(x: center.x, y: center.y - 16),
                          font: .systemFont(ofSize: 46, weight: .bold),
                          color: theme.deep.uiSolid)
    cardDrawCenteredText(label,
                          center: CGPoint(x: center.x, y: center.y + 26),
                          font: .systemFont(ofSize: 22),
                          color: theme.main.uiSolid.withAlphaComponent(0.85))
}

private func cardDrawCenteredText(_ text: String, center: CGPoint, font: UIFont, color: UIColor) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).size(withAttributes: attrs)
    let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
    (text as NSString).draw(at: origin, withAttributes: attrs)
}

private func cardDrawPill(cg: CGContext, text: String, center: CGPoint,
                          font: UIFont, bg: UIColor, fg: UIColor) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
    let size = (text as NSString).size(withAttributes: attrs)
    let padH: CGFloat = 26
    let padV: CGFloat = 12
    let rect = CGRect(
        x: center.x - size.width / 2 - padH,
        y: center.y - size.height / 2 - padV,
        width: size.width + padH * 2,
        height: size.height + padV * 2
    )
    let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
    bg.setFill()
    path.fill()
    (text as NSString).draw(
        at: CGPoint(x: rect.minX + padH, y: rect.minY + padV),
        withAttributes: attrs
    )
}

private func cardDrawRoundedBox(cg: CGContext, rect: CGRect, radius: CGFloat,
                                 fill: UIColor, stroke: UIColor?, lineWidth: CGFloat) {
    let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

private func cardDrawVertDivider(cg: CGContext, x: CGFloat, yCenter: CGFloat,
                                  length: CGFloat, color: UIColor) {
    cg.setStrokeColor(color.cgColor)
    cg.setLineWidth(1)
    cg.move(to: CGPoint(x: x, y: yCenter - length / 2))
    cg.addLine(to: CGPoint(x: x, y: yCenter + length / 2))
    cg.strokePath()
}

private func cardFillDiagonalGradient(cg: CGContext, rect: CGRect,
                                       from start: UIColor, to end: UIColor) {
    let colors = [start.cgColor, end.cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) else { return }
    cg.saveGState()
    cg.clip(to: rect)
    cg.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.minX, y: rect.minY),
                           end: CGPoint(x: rect.maxX, y: rect.maxY),
                           options: [])
    cg.restoreGState()
}
