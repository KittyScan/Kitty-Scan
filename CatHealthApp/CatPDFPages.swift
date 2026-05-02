import SwiftUI
import UIKit
// =========================================================
// PDF shared constants
// =========================================================
/// US Letter at 72 DPI. Cleanly fits A4 viewers too.
let pageSize = CGSize(width: 612, height: 792)
/// Margin grid — 60pt outside, header/footer take 40 + 50.
let pdfPageMarginX: CGFloat = 60
let pdfContentTop: CGFloat = 60     // below header
let pdfContentBottom: CGFloat = 50  // above footer
/// Y-coordinate where content must stop. Anything past this overflows
/// into the running footer.
let pdfMaxContentY: CGFloat = pageSize.height - pdfContentBottom

/// Max records per PDF — kept low for file size + draw time.
let pdfRecordCap = 10

/// Strict type scale for the PDF — every page picks from this set so the
/// document feels typographically consistent. Reads like a chart/letter,
/// not like a slide deck.
enum PDFType {
    static let display    = UIFont.systemFont(ofSize: 36, weight: .bold)   // patient name on cover
    static let title      = UIFont.systemFont(ofSize: 22, weight: .bold)   // page H1
    static let h2         = UIFont.systemFont(ofSize: 14, weight: .bold)   // section labels (ALL CAPS)
    static let h3         = UIFont.systemFont(ofSize: 13, weight: .semibold)
    static let body       = UIFont.systemFont(ofSize: 12, weight: .regular)
    static let bodyMedium = UIFont.systemFont(ofSize: 12, weight: .medium)
    static let caption    = UIFont.systemFont(ofSize: 10, weight: .regular)
    static let metaMono   = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    static let scoreBig   = UIFont.monospacedDigitSystemFont(ofSize: 30, weight: .bold)
}
// =========================================================
// SimpleCatAvatar
// SwiftUI avatar used in CatCardView (PNG export). Canvas-free.
// =========================================================
struct SimpleCatAvatar: View {
    let theme: CatTheme
    let name: String
    let avatarData: Data?
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [theme.light, theme.card],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
            if let data = avatarData,
               let img = AvatarImage.decode(data: data, maxPixelSize: size * 3) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } else {
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.deep)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(theme.main.opacity(0.25), lineWidth: 1))
    }
}
// =========================================================
// CatPDF — pure CoreGraphics PDF generator
//
// Previously this file rendered SwiftUI page views through `ImageRenderer`
// inside a `UIGraphicsPDFRenderer.pdfData` closure. That setup caused the
// export to hang (mach_msg2_trap on main thread) in the simulator — nested
// SwiftUI + UIKit graphics contexts don't play nicely under load.
//
// This rewrite uses NSAttributedString.draw(in:) + CGContext shapes
// directly. No SwiftUI, no ImageRenderer, no Metal pipeline compilation.
// Boring but bulletproof.
// =========================================================
enum CatPDF {
    /// Two-page report.
    ///   Page 1 — patient header + most recent examination (one-sentence
    ///            findings / recommendations / concerns).
    ///   Page 2 — scoring methodology + disclaimer.
    /// Historical records are NOT included in PDF; users can re-export at
    /// any time with the latest data, and the in-app history view shows the
    /// full timeline.
    static func render(cat: Cat, records: [HistoryRecord], theme: CatTheme, zh: Bool) -> Data? {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let tag = "[CatPDF:\(cat.name)]"
        print("\(tag) start (2-page report)")
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { pdfCtx in
            let cg = pdfCtx.cgContext
            let recordID = "CAR-\(cat.id.uuidString.prefix(8))"
            let totalPages = 2

            // Page 1 — patient summary + latest exam
            pdfCtx.beginPage()
            drawClinicalHeader(cg: cg, rect: bounds, theme: theme,
                                catName: cat.name, recordID: recordID,
                                page: 1, total: totalPages, zh: zh)
            drawSummaryPage(cg: cg, rect: bounds, cat: cat, theme: theme,
                            latest: records.first,
                            totalCount: records.count, zh: zh)
            drawClinicalFooter(cg: cg, rect: bounds, theme: theme,
                               page: 1, total: totalPages, zh: zh)

            // Page 2 — methodology
            pdfCtx.beginPage()
            drawClinicalHeader(cg: cg, rect: bounds, theme: theme,
                                catName: cat.name, recordID: recordID,
                                page: 2, total: totalPages, zh: zh)
            drawMethodology(cg: cg, rect: bounds, theme: theme, zh: zh)
            drawClinicalFooter(cg: cg, rect: bounds, theme: theme,
                               page: 2, total: totalPages, zh: zh)
        }
        print("\(tag) done · \(data.count) bytes")
        return data
    }
}

// =========================================================
// Page 1 — Patient summary + most recent examination.
//
// Single-language: when zh=true, ALL labels and copy are Chinese; when
// zh=false, all English. No double-language section labels.
// Uses the strict PDFType scale so every line of text is one of:
//   title (22) · h2 (14) · body (12) · caption (10) · scoreBig (30)
// =========================================================
private func drawSummaryPage(cg: CGContext,
                              rect: CGRect,
                              cat: Cat,
                              theme: CatTheme,
                              latest: HistoryRecord?,
                              totalCount: Int,
                              zh: Bool) {
    UIColor.white.setFill()
    cg.fill(rect)

    let x: CGFloat = pdfPageMarginX
    let w = rect.width - pdfPageMarginX * 2
    var y: CGFloat = pdfContentTop

    // -------- Patient identification --------
    drawText(zh ? "受检个体" : "PATIENT",
             at: CGPoint(x: x, y: y),
             font: PDFType.h2,
             color: theme.deep.uiSolid)
    y += 22
    drawText(cat.name,
             at: CGPoint(x: x, y: y),
             font: PDFType.display,
             color: UIColor.black.withAlphaComponent(0.85))
    y += 50

    let identityParts: [String] = [
        cat.breed,
        sexDisplayClean(cat.sex, zh: zh),
        cat.age,
        cat.neuter ? (zh ? "已绝育" : "Neutered") : (zh ? "未绝育" : "Intact"),
    ].compactMap { $0?.isEmpty == true ? nil : $0 }
    if !identityParts.isEmpty {
        drawText(identityParts.joined(separator: " · "),
                 at: CGPoint(x: x, y: y),
                 font: PDFType.body,
                 color: UIColor.darkGray)
        y += 22
    }

    // Hairline rule
    UIColor(white: 0.85, alpha: 1).setStroke()
    cg.setLineWidth(0.5)
    cg.move(to: CGPoint(x: x, y: y))
    cg.addLine(to: CGPoint(x: x + w, y: y))
    cg.strokePath()
    y += 16

    // -------- Metadata table — 2 columns × 4 rows --------
    // Same structural style we use for sub-scores and findings: header row
    // + thin underline + zebra striping. Reads as one consistent "patient
    // record table" instead of free-floating label/value pairs.
    let recordID = "CAR-\(cat.id.uuidString.prefix(8))"
    let dateFmt = DateFormatter()
    dateFmt.locale = Locale(identifier: zh ? "zh_Hans" : "en_US")
    dateFmt.dateStyle = .medium
    let metaRows: [(String, String)] = [
        (zh ? "档案编号"     : "Record ID",          recordID),
        (zh ? "生成日期"     : "Generated",          dateFmt.string(from: Date())),
        (zh ? "检查总次数"   : "Total examinations", "\(totalCount)"),
        (zh ? "本次检查日期" : "Examination date",
            latest.map { dateFmt.string(from: $0.date) } ?? "—"),
    ]
    drawText(zh ? "档案信息" : "RECORD METADATA",
             at: CGPoint(x: x, y: y),
             font: PDFType.h2,
             color: theme.deep.uiSolid)
    y += 22
    y = drawTableHeader(cg: cg, x: x, y: y, w: w,
                         columns: [(zh ? "项目" : "FIELD",     0),
                                   (zh ? "内容" : "VALUE", 200)])
    for (i, pair) in metaRows.enumerated() {
        y = drawTableRow(cg: cg, x: x, y: y, w: w,
                         zebraIndex: i,
                         cells: [
                            (pair.0, 0,   PDFType.body,       UIColor.darkGray),
                            (pair.1, 200, monoCellFont(),     UIColor.black.withAlphaComponent(0.85)),
                         ])
    }
    y += 18

    // -------- Latest examination --------
    drawText(zh ? "本次检查" : "LATEST EXAMINATION",
             at: CGPoint(x: x, y: y),
             font: PDFType.h2,
             color: theme.deep.uiSolid)
    y += 24

    if let r = latest {
        let scoreColor = scoreUIColor(for: r.healthScore)

        // ---- COMPOSITE highlight box ----
        // One bordered card: dimension label left, big mono number center,
        // qualitative interpretation right, horizontal bar across the bottom.
        // Reads like the headline row of a lab-results sheet.
        let compositeH: CGFloat = 78
        let compositeRect = CGRect(x: x, y: y, width: w, height: compositeH)
        UIColor(white: 0.97, alpha: 1).setFill()
        UIBezierPath(roundedRect: compositeRect, cornerRadius: 8).fill()
        UIColor(white: 0.85, alpha: 1).setStroke()
        let stroke = UIBezierPath(roundedRect: compositeRect, cornerRadius: 8)
        stroke.lineWidth = 0.5
        stroke.stroke()
        // Left accent bar — color encodes the band so the qualitative
        // verdict is readable at a glance even before scanning the text.
        scoreColor.setFill()
        UIBezierPath(roundedRect: CGRect(x: x, y: y, width: 4, height: compositeH),
                     cornerRadius: 1).fill()

        // Label
        drawText(zh ? "综合评分" : "COMPOSITE",
                 at: CGPoint(x: x + 18, y: y + 12),
                 font: PDFType.caption,
                 color: UIColor.darkGray)
        // Big number
        drawText("\(r.healthScore)",
                 at: CGPoint(x: x + 18, y: y + 26),
                 font: PDFType.scoreBig,
                 color: scoreColor)
        // " / 100" suffix in smaller weight, baseline-aligned to the big number
        drawText("/ 100",
                 at: CGPoint(x: x + 18 + bigNumberWidth("\(r.healthScore)") + 6,
                              y: y + 38),
                 font: PDFType.bodyMedium,
                 color: UIColor.darkGray)
        // Qualitative band, right-aligned
        let bandText = scoreLabelText(score: r.healthScore, zh: zh)
        let bandSize = (bandText as NSString).size(withAttributes: [.font: PDFType.bodyMedium])
        (bandText as NSString).draw(
            at: CGPoint(x: x + w - 18 - bandSize.width, y: y + 26),
            withAttributes: [.font: PDFType.bodyMedium, .foregroundColor: scoreColor]
        )
        // Bottom progress bar inside the card
        let barTrack = CGRect(x: x + 18, y: y + compositeH - 16,
                              width: w - 36, height: 4)
        UIColor(white: 0.88, alpha: 1).setFill()
        UIBezierPath(roundedRect: barTrack, cornerRadius: 2).fill()
        let fillW = barTrack.width * CGFloat(max(0, min(100, r.healthScore))) / 100
        scoreColor.setFill()
        UIBezierPath(roundedRect: CGRect(x: barTrack.minX, y: barTrack.minY,
                                          width: fillW, height: barTrack.height),
                     cornerRadius: 2).fill()
        y += compositeH + 16

        // ---- Sub-score table — uses the same helper style ----
        let subPairs: [(String, Int?)] = [
            (zh ? "眼睛" : "Eyes",     r.eyesScore),
            (zh ? "毛发" : "Fur",      r.furScore),
            (zh ? "体态" : "Posture",  r.postureScore),
            (zh ? "精神" : "Energy",   r.energyScore),
        ]
        let scoreColX: CGFloat = 130
        let barColX: CGFloat   = 200
        let barColW            = w - 200
        y = drawTableHeader(cg: cg, x: x, y: y, w: w,
                             columns: [(zh ? "项目" : "DIMENSION", 0),
                                       (zh ? "得分" : "SCORE",     scoreColX)])
        for (i, pair) in subPairs.enumerated() {
            let (label, score) = pair
            let rowColor = score.map { scoreUIColor(for: $0) } ?? UIColor.gray
            let rowH: CGFloat = 22
            // zebra
            if i % 2 == 1 {
                UIColor(white: 0.97, alpha: 1).setFill()
                UIBezierPath(rect: CGRect(x: x, y: y - 4, width: w, height: rowH)).fill()
            }
            drawText(label, at: CGPoint(x: x, y: y),
                     font: PDFType.bodyMedium,
                     color: UIColor.black.withAlphaComponent(0.85))
            drawText(score.map { "\($0)" } ?? "—",
                     at: CGPoint(x: x + scoreColX, y: y),
                     font: monoCellFont(),
                     color: rowColor)
            let track = CGRect(x: x + barColX, y: y + 6, width: barColW, height: 6)
            UIColor(white: 0.92, alpha: 1).setFill()
            UIBezierPath(roundedRect: track, cornerRadius: 3).fill()
            if let s = score {
                let fw = track.width * CGFloat(max(0, min(100, s))) / 100
                rowColor.setFill()
                UIBezierPath(roundedRect: CGRect(x: track.minX, y: track.minY,
                                                  width: fw, height: track.height),
                              cornerRadius: 3).fill()
            }
            y += rowH
            UIColor(white: 0.92, alpha: 1).setStroke()
            cg.setLineWidth(0.5)
            cg.move(to: CGPoint(x: x, y: y - 4))
            cg.addLine(to: CGPoint(x: x + w, y: y - 4))
            cg.strokePath()
        }
        y += 14

        // -------- Findings table — same visual structure as RECORD METADATA --------
        drawText(zh ? "检查结果" : "FINDINGS",
                 at: CGPoint(x: x, y: y),
                 font: PDFType.h2,
                 color: theme.deep.uiSolid)
        y += 22
        let findings: [(String, String)] = [
            (zh ? "眼睛" : "Eyes",     firstSentence(r.eyesCondition)),
            (zh ? "毛发" : "Fur",      firstSentence(r.furCondition)),
            (zh ? "体态" : "Posture",  firstSentence(r.postureCondition)),
        ]
        let findingLabelCol: CGFloat = 0
        let findingTextCol: CGFloat  = 90
        y = drawTableHeader(cg: cg, x: x, y: y, w: w,
                             columns: [(zh ? "项目" : "DIMENSION",  findingLabelCol),
                                       (zh ? "结果" : "OBSERVATION", findingTextCol)])
        for (i, pair) in findings.enumerated() {
            // Findings can wrap to a second line; we measure first so the
            // row height adapts. drawTableRow handles a fixed height — for
            // wrapping cells we have to do it inline.
            let rowH = wrappedRowHeight(text: pair.1, width: w - findingTextCol,
                                         font: PDFType.body)
            // zebra
            if i % 2 == 1 {
                UIColor(white: 0.97, alpha: 1).setFill()
                UIBezierPath(rect: CGRect(x: x, y: y - 4, width: w, height: rowH + 8)).fill()
            }
            // dimension label
            drawText(pair.0,
                     at: CGPoint(x: x + findingLabelCol, y: y),
                     font: PDFType.bodyMedium,
                     color: UIColor.darkGray)
            // wrapped finding text
            _ = drawWrappedText(pair.1,
                                 in: CGRect(x: x + findingTextCol, y: y,
                                            width: w - findingTextCol, height: 60),
                                 font: PDFType.body,
                                 color: UIColor.black.withAlphaComponent(0.85),
                                 lineSpacing: 2)
            y += rowH + 8
            // hairline below row
            UIColor(white: 0.92, alpha: 1).setStroke()
            cg.setLineWidth(0.5)
            cg.move(to: CGPoint(x: x, y: y - 4))
            cg.addLine(to: CGPoint(x: x + w, y: y - 4))
            cg.strokePath()
        }
        y += 12

        // -------- Top recommendation (one-sentence summary) --------
        if let firstTip = r.suggestions.first {
            drawText(zh ? "重点建议" : "RECOMMENDATION",
                     at: CGPoint(x: x, y: y),
                     font: PDFType.h2,
                     color: theme.deep.uiSolid)
            y += 22
            let h = drawWrappedText(firstSentence(firstTip),
                                     in: CGRect(x: x, y: y, width: w, height: 60),
                                     font: PDFType.body,
                                     color: UIColor.black.withAlphaComponent(0.85),
                                     lineSpacing: 3)
            y += h + 12
        }

        // -------- Concerns (one-sentence summary) --------
        if let firstWarning = r.warnings.first {
            drawText(zh ? "需要关注" : "CONCERN",
                     at: CGPoint(x: x, y: y),
                     font: PDFType.h2,
                     color: UIColor.systemRed)
            y += 22
            let h = drawWrappedText(firstSentence(firstWarning),
                                     in: CGRect(x: x, y: y, width: w, height: 60),
                                     font: PDFType.body,
                                     color: UIColor.black.withAlphaComponent(0.85),
                                     lineSpacing: 3)
            y += h + 12
        }
    } else {
        drawText(zh ? "暂无检查记录。" : "No examinations on record.",
                 at: CGPoint(x: x, y: y),
                 font: PDFType.body,
                 color: UIColor.darkGray)
    }
}

/// Trim the AI's verbose multi-sentence outputs down to a single statement.
/// Splits on common Chinese + English sentence terminators and returns the
/// first non-empty fragment. If we can't find a delimiter the original
/// string is returned unchanged.
private func firstSentence(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let terminators: Set<Character> = ["。", "！", "？", ".", "!", "?", "；", ";"]
    for (i, ch) in trimmed.enumerated() where terminators.contains(ch) {
        let endIdx = trimmed.index(trimmed.startIndex, offsetBy: i + 1)
        return String(trimmed[..<endIdx]).trimmingCharacters(in: .whitespaces)
    }
    return trimmed
}

/// Width of a big composite-score number (e.g. "78") rendered in
/// `PDFType.scoreBig`. Used to position the "/ 100" suffix flush against
/// the right edge of the number without measuring it twice elsewhere.
private func bigNumberWidth(_ s: String) -> CGFloat {
    (s as NSString).size(withAttributes: [.font: PDFType.scoreBig]).width
}

// =========================================================
// Table primitives
//
// All Page-1 tabular blocks (record metadata, sub-scores, findings) share
// these helpers so they read as one consistent visual language: small
// uppercase header row, subtle underline, zebra-striped rows, and
// monospaced numeric values where applicable. Pulling these out also
// makes adding future tables (e.g. weight history) trivial.
// =========================================================

/// Monospaced 12pt font used in numeric/ID cells. Pulled into a function
/// so all numeric cells in tables share the same metric.
private func monoCellFont() -> UIFont {
    UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
}

/// Renders a small uppercase header row plus a hairline below it. Returns
/// the new y cursor sitting just below the underline.
@discardableResult
private func drawTableHeader(cg: CGContext, x: CGFloat, y: CGFloat, w: CGFloat,
                              columns: [(label: String, offset: CGFloat)]) -> CGFloat {
    for col in columns {
        drawText(col.label,
                 at: CGPoint(x: x + col.offset, y: y),
                 font: PDFType.caption,
                 color: UIColor.darkGray)
    }
    var endY = y + 14
    UIColor(white: 0.7, alpha: 1).setStroke()
    cg.setLineWidth(0.7)
    cg.move(to: CGPoint(x: x, y: endY))
    cg.addLine(to: CGPoint(x: x + w, y: endY))
    cg.strokePath()
    endY += 8
    return endY
}

/// Renders a uniform-height row with N text cells, optional zebra stripe,
/// and a hairline divider below. Returns the new y cursor.
///
/// Each cell is `(text, offset-from-x, font, color)`.
@discardableResult
private func drawTableRow(cg: CGContext, x: CGFloat, y: CGFloat, w: CGFloat,
                           zebraIndex: Int,
                           cells: [(String, CGFloat, UIFont, UIColor)]) -> CGFloat {
    let rowH: CGFloat = 20
    if zebraIndex % 2 == 1 {
        UIColor(white: 0.97, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(x: x, y: y - 3, width: w, height: rowH)).fill()
    }
    for (text, offset, font, color) in cells {
        drawText(text,
                 at: CGPoint(x: x + offset, y: y),
                 font: font,
                 color: color)
    }
    let endY = y + rowH
    UIColor(white: 0.92, alpha: 1).setStroke()
    cg.setLineWidth(0.5)
    cg.move(to: CGPoint(x: x, y: endY - 3))
    cg.addLine(to: CGPoint(x: x + w, y: endY - 3))
    cg.strokePath()
    return endY
}

/// Computes the height needed to render `text` wrapped to `width` in `font`.
/// Used by the findings table where rows can wrap to multiple lines and
/// row height has to adapt.
private func wrappedRowHeight(text: String, width: CGFloat, font: UIFont) -> CGFloat {
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let h = (text as NSString).boundingRect(
        with: CGSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin],
        attributes: attrs,
        context: nil
    ).size.height
    return ceil(h)
}

/// Localized, single-language sex display. Replaces the older mixed
/// "♂ Male" form which looked weird mid-Chinese-paragraph.
private func sexDisplayClean(_ sex: String?, zh: Bool) -> String? {
    switch sex {
    case "male":   return zh ? "公" : "Male"
    case "female": return zh ? "母" : "Female"
    default:       return nil
    }
}

// =========================================================
// Primitives
// =========================================================
private func drawCatAvatar(cg: CGContext, rect: CGRect, cat: Cat, theme: CatTheme) {
    // Save state for clip
    cg.saveGState()
    cg.addEllipse(in: rect)
    cg.clip()
    // Themed gradient fill
    fillDiagonalGradient(cg: cg, rect: rect,
                          from: theme.light.uiSolid,
                          to: theme.card.uiSolid)
    // Photo if available
    if let data = cat.avatarData,
       let img = AvatarImage.decode(data: data, maxPixelSize: rect.width * 2.5) {
        img.draw(in: rect)
    } else {
        cg.restoreGState()
        let letter = String(cat.name.prefix(1))
        drawCenteredText(letter,
                         center: CGPoint(x: rect.midX, y: rect.midY),
                         font: .systemFont(ofSize: rect.width * 0.42, weight: .bold),
                         color: theme.deep.uiSolid)
        // Re-apply stroke below
        cg.setStrokeColor(theme.main.uiSolid.withAlphaComponent(0.25).cgColor)
        cg.setLineWidth(1)
        cg.strokeEllipse(in: rect)
        return
    }
    cg.restoreGState()
    // Stroke
    cg.setStrokeColor(theme.main.uiSolid.withAlphaComponent(0.25).cgColor)
    cg.setLineWidth(1)
    cg.strokeEllipse(in: rect)
}
private func drawInfoRow(cg: CGContext, x: CGFloat, y: CGFloat, width: CGFloat,
                         label: String, value: String, theme: CatTheme) -> CGFloat {
    // Clinical-style: dark grey label left, monospaced black value right,
    // hairline divider below. No theme tinting in inner pages.
    drawText(label,
             at: CGPoint(x: x, y: y),
             font: .systemFont(ofSize: 16),
             color: UIColor.darkGray)
    let valFont = UIFont.systemFont(ofSize: 16, weight: .medium)
    let valSize = (value as NSString).size(withAttributes: [.font: valFont])
    (value as NSString).draw(
        at: CGPoint(x: x + width - valSize.width, y: y),
        withAttributes: [.font: valFont,
                          .foregroundColor: UIColor.black.withAlphaComponent(0.85)]
    )
    cg.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
    cg.setLineWidth(0.5)
    cg.move(to: CGPoint(x: x, y: y + 26))
    cg.addLine(to: CGPoint(x: x + width, y: y + 26))
    cg.strokePath()
    return 36
}
private func drawCondRow(cg: CGContext, x: CGFloat, y: CGFloat, width: CGFloat,
                         label: String, value: String, theme: CatTheme) -> CGFloat {
    drawText(label,
             at: CGPoint(x: x, y: y),
             font: .systemFont(ofSize: 14, weight: .semibold),
             color: UIColor.darkGray)
    let h = drawWrappedText(value,
                            in: CGRect(x: x, y: y + 18,
                                       width: width, height: 80),
                            font: .systemFont(ofSize: 16),
                            color: UIColor.black.withAlphaComponent(0.85),
                            lineSpacing: 3)
    let totalH = 18 + h + 12
    cg.setStrokeColor(UIColor(white: 0.92, alpha: 1).cgColor)
    cg.setLineWidth(0.5)
    cg.move(to: CGPoint(x: x, y: y + totalH - 4))
    cg.addLine(to: CGPoint(x: x + width, y: y + totalH - 4))
    cg.strokePath()
    return totalH
}

/// Localized score-band label, used in the score header on the exam page.
private func scoreLabelText(score: Int, zh: Bool) -> String {
    switch ScoreBand(score: score) {
    case .excellent: return zh ? "优秀范围"   : "Above-average"
    case .good:      return zh ? "正常范围"   : "Within normal range"
    case .fair:      return zh ? "需要观察"   : "Requires monitoring"
    case .critical:  return zh ? "需要复查"   : "Requires follow-up"
    }
}

/// Running page header — appears on every page except the cover. Thin
/// theme-color rule + monospaced metadata bar (cat name · record ID · page).
private func drawClinicalHeader(cg: CGContext, rect: CGRect, theme: CatTheme,
                                 catName: String, recordID: String,
                                 page: Int, total: Int, zh: Bool) {
    // Top accent rule (subtle, 4pt)
    let stripe = CGRect(x: 0, y: 0, width: rect.width, height: 4)
    theme.deep.uiSolid.setFill()
    cg.fill(stripe)

    let metaY: CGFloat = 20
    let leftText = "\(catName) · \(recordID)"
    drawText(leftText,
             at: CGPoint(x: 60, y: metaY),
             font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium),
             color: UIColor.darkGray)

    let rightText = zh ? "第 \(page) 页 / 共 \(total) 页"
                       : "Page \(page) of \(total)"
    let rightFont = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    let rightSize = (rightText as NSString).size(withAttributes: [.font: rightFont])
    (rightText as NSString).draw(
        at: CGPoint(x: rect.width - 60 - rightSize.width, y: metaY),
        withAttributes: [.font: rightFont, .foregroundColor: UIColor.darkGray]
    )
}

/// Running page footer — small disclaimer + brand line.
private func drawClinicalFooter(cg: CGContext, rect: CGRect, theme: CatTheme,
                                 page: Int, total: Int, zh: Bool) {
    let footY = rect.height - 30
    cg.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
    cg.setLineWidth(0.5)
    cg.move(to: CGPoint(x: 60, y: footY - 8))
    cg.addLine(to: CGPoint(x: rect.width - 60, y: footY - 8))
    cg.strokePath()

    let text = zh
        ? "KittyScan · 由 Anthropic Claude Sonnet 4.6 视觉模型生成的辅助筛查文档,不构成医学诊断"
        : "KittyScan · Screening document generated by Anthropic Claude Sonnet 4.6 vision; not a medical diagnosis"
    let f = UIFont.systemFont(ofSize: 9)
    let size = (text as NSString).size(withAttributes: [.font: f])
    (text as NSString).draw(
        at: CGPoint(x: (rect.width - size.width) / 2, y: footY),
        withAttributes: [.font: f, .foregroundColor: UIColor.gray]
    )
}
private func drawStat(cg: CGContext, value: String, label: String, center: CGPoint, theme: CatTheme) {
    drawCenteredText(value,
                     center: CGPoint(x: center.x, y: center.y - 10),
                     font: .systemFont(ofSize: 30, weight: .bold),
                     color: theme.deep.uiSolid)
    drawCenteredText(label,
                     center: CGPoint(x: center.x, y: center.y + 16),
                     font: .systemFont(ofSize: 13),
                     color: theme.main.uiSolid.withAlphaComponent(0.85))
}
private func drawFooter(cg: CGContext, rect: CGRect, theme: CatTheme) {
    let y: CGFloat = rect.height - 28
    drawText("🐾 KittyScan",
             at: CGPoint(x: 40, y: y),
             font: .systemFont(ofSize: 13, weight: .semibold),
             color: theme.deep.uiSolid.withAlphaComponent(0.6))
    let tip = "AI-generated · Not a vet diagnosis"
    let tipFont = UIFont.systemFont(ofSize: 12)
    let tipColor = theme.main.uiSolid.withAlphaComponent(0.5)
    let tipSize = (tip as NSString).size(withAttributes: [.font: tipFont])
    (tip as NSString).draw(
        at: CGPoint(x: rect.width - 40 - tipSize.width, y: y),
        withAttributes: [.font: tipFont, .foregroundColor: tipColor]
    )
}
private func drawPill(cg: CGContext, text: String, center: CGPoint,
                      font: UIFont, bg: UIColor, fg: UIColor) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
    let size = (text as NSString).size(withAttributes: attrs)
    let padH: CGFloat = 14
    let padV: CGFloat = 6
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
private func drawRoundedBox(cg: CGContext, rect: CGRect, radius: CGFloat,
                            fill: UIColor, stroke: UIColor?, lineWidth: CGFloat) {
    let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke = stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}
private func drawDivider(cg: CGContext, x: CGFloat, yCenter: CGFloat,
                         length: CGFloat, color: UIColor) {
    cg.setStrokeColor(color.cgColor)
    cg.setLineWidth(0.5)
    cg.move(to: CGPoint(x: x, y: yCenter - length / 2))
    cg.addLine(to: CGPoint(x: x, y: yCenter + length / 2))
    cg.strokePath()
}
private func drawText(_ text: String, at origin: CGPoint, font: UIFont, color: UIColor) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    (text as NSString).draw(at: origin, withAttributes: attrs)
}

/// Wrapping variant — draws into a fixed-width rect so long body paragraphs
/// (methodology page, disclaimers) flow correctly instead of overflowing.
private func drawText(_ text: String, at origin: CGPoint, font: UIFont,
                      color: UIColor, maxWidth: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).boundingRect(
        with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin],
        attributes: attrs,
        context: nil
    ).size
    (text as NSString).draw(
        with: CGRect(origin: origin, size: size),
        options: [.usesLineFragmentOrigin],
        attributes: attrs,
        context: nil
    )
}

private func drawCenteredText(_ text: String, center: CGPoint, font: UIFont, color: UIColor) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).size(withAttributes: attrs)
    let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
    (text as NSString).draw(at: origin, withAttributes: attrs)
}
private func drawWrappedText(_ text: String,
                             in rect: CGRect,
                             font: UIFont,
                             color: UIColor,
                             lineSpacing: CGFloat) -> CGFloat {
    let para = NSMutableParagraphStyle()
    para.lineSpacing = lineSpacing
    para.lineBreakMode = .byWordWrapping
    para.alignment = .left
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: para,
    ]
    let attrString = NSAttributedString(string: text, attributes: attrs)
    let bounding = attrString.boundingRect(
        with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
    )
    attrString.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    return ceil(bounding.height)
}
// =========================================================
// Gradients
// =========================================================
private func fillLinearGradient(cg: CGContext, rect: CGRect,
                                 from start: UIColor, to end: UIColor,
                                 vertical: Bool) {
    cg.saveGState()
    cg.clip(to: rect)
    let colors = [start.cgColor, end.cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) else {
        cg.restoreGState()
        return
    }
    let s = vertical ? CGPoint(x: rect.midX, y: rect.minY) : CGPoint(x: rect.minX, y: rect.midY)
    let e = vertical ? CGPoint(x: rect.midX, y: rect.maxY) : CGPoint(x: rect.maxX, y: rect.midY)
    cg.drawLinearGradient(gradient, start: s, end: e, options: [])
    cg.restoreGState()
}
private func fillDiagonalGradient(cg: CGContext, rect: CGRect,
                                   from start: UIColor, to end: UIColor) {
    let colors = [start.cgColor, end.cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) else { return }
    cg.drawLinearGradient(gradient,
                          start: CGPoint(x: rect.minX, y: rect.minY),
                          end: CGPoint(x: rect.maxX, y: rect.maxY),
                          options: [])
}
// =========================================================
// Small helpers
// =========================================================
private func sexDisplay(_ sex: String?, zh: Bool) -> String {
    switch sex {
    case "male":   return zh ? "♂ 男猫" : "♂ Male"
    case "female": return zh ? "♀ 女猫" : "♀ Female"
    default:       return "—"
    }
}
private func longDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = .current
    f.dateStyle = .long
    return f.string(from: d)
}
private func scoreUIColor(for score: Int) -> UIColor {
    ScoreBand(score: score).uiColor
}

// =========================================================
// Methodology page — appears between cover and profile.
// "Here's how the 78 was calculated" so a vet (or any cold reader) doesn't
// have to take the score on faith. Designed to read like a one-pager
// explainer, NOT a legal disclaimer.
// =========================================================
private func drawMethodology(cg: CGContext, rect: CGRect, theme: CatTheme, zh: Bool) {
    UIColor.white.setFill()
    cg.fill(rect)

    let x: CGFloat = pdfPageMarginX
    let w = rect.width - pdfPageMarginX * 2
    var y: CGFloat = pdfContentTop

    // ---- Page title (matches Page 1 hierarchy) ----
    drawText(zh ? "方法说明" : "METHODOLOGY",
             at: CGPoint(x: x, y: y),
             font: PDFType.h2,
             color: theme.deep.uiSolid)
    y += 22
    drawText(zh ? "评分如何产生" : "How the score is calculated",
             at: CGPoint(x: x, y: y),
             font: PDFType.title,
             color: UIColor.black.withAlphaComponent(0.85))
    y += 36

    // ---- 1) Inputs table — what data goes in ----
    // Replaces the old paragraph; same structural style as Page 1's
    // RECORD METADATA / FINDINGS tables.
    drawText(zh ? "1. 数据输入" : "1. INPUTS",
             at: CGPoint(x: x, y: y),
             font: PDFType.h2,
             color: theme.deep.uiSolid)
    y += 22
    let inputRows: [(String, String)] = zh
        ? [("照片",       "本次提交的猫咪照片"),
           ("猫咪档案",   "品种 / 年龄 / 已知问题"),
           ("近 5 次检测", "仅作趋势对比,不影响本次评分"),
           ("近 7 天日记", "饭量、饮水、是否异常等")]
        : [("Photo",       "The cat photo submitted this round"),
           ("Profile",     "Breed, age, known conditions"),
           ("Last 5 exams","Trend comparison only — never anchors the new score"),
           ("Last 7 days", "Owner-logged routine: meals, water, anomalies")]
    y = drawTableHeader(cg: cg, x: x, y: y, w: w,
                         columns: [(zh ? "项目" : "FIELD",   0),
                                   (zh ? "说明" : "DETAIL", 160)])
    for (i, pair) in inputRows.enumerated() {
        y = drawTableRow(cg: cg, x: x, y: y, w: w,
                          zebraIndex: i,
                          cells: [
                            (pair.0, 0,   PDFType.bodyMedium, UIColor.black.withAlphaComponent(0.85)),
                            (pair.1, 160, PDFType.body,       UIColor.darkGray),
                          ])
    }
    y += 16

    // ---- 2) Dimensions + weights table ----
    // Combined into one table so the reader sees "what's measured" and
    // "how it's weighted" at the same time, instead of flipping between
    // two adjacent tables.
    drawText(zh ? "2. 评估维度与权重" : "2. DIMENSIONS & WEIGHTS",
             at: CGPoint(x: x, y: y),
             font: PDFType.h2,
             color: theme.deep.uiSolid)
    y += 22
    let weightRows: [(String, String, String)] = zh
        ? [("眼睛", "30%", "分泌物、清亮度"),
           ("精神", "30%", "整体状态、警觉度"),
           ("毛发", "20%", "光泽、皮屑"),
           ("体态", "20%", "对称、紧绷度")]
        : [("Eyes",     "30%", "Discharge, clarity"),
           ("Energy",   "30%", "Alertness, liveliness"),
           ("Fur",      "20%", "Gloss, flakes"),
           ("Posture",  "20%", "Symmetry, tension")]
    y = drawTableHeader(cg: cg, x: x, y: y, w: w,
                         columns: [(zh ? "项目" : "DIMENSION", 0),
                                   (zh ? "权重" : "WEIGHT",   160),
                                   (zh ? "评估内容" : "EVALUATES", 240)])
    for (i, row) in weightRows.enumerated() {
        y = drawTableRow(cg: cg, x: x, y: y, w: w,
                          zebraIndex: i,
                          cells: [
                            (row.0, 0,   PDFType.bodyMedium, UIColor.black.withAlphaComponent(0.85)),
                            (row.1, 160, monoCellFont(),     UIColor.black.withAlphaComponent(0.85)),
                            (row.2, 240, PDFType.body,       UIColor.darkGray),
                          ])
    }
    y += 16

    // ---- 3) Composite formula in a tinted code block ----
    drawText(zh ? "3. 综合评分公式" : "3. COMPOSITE FORMULA",
             at: CGPoint(x: x, y: y),
             font: PDFType.h2,
             color: theme.deep.uiSolid)
    y += 22
    let formulaBox = CGRect(x: x, y: y, width: w, height: 30)
    UIColor(white: 0.97, alpha: 1).setFill()
    UIBezierPath(roundedRect: formulaBox, cornerRadius: 6).fill()
    UIColor(white: 0.85, alpha: 1).setStroke()
    let formulaStroke = UIBezierPath(roundedRect: formulaBox, cornerRadius: 6)
    formulaStroke.lineWidth = 0.5
    formulaStroke.stroke()
    let formulaText = zh
        ? "综合分 = 0.30·眼睛 + 0.30·精神 + 0.20·毛发 + 0.20·体态"
        : "Total = 0.30·Eyes + 0.30·Energy + 0.20·Fur + 0.20·Posture"
    drawText(formulaText,
             at: CGPoint(x: x + 12, y: y + 8),
             font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
             color: UIColor.black.withAlphaComponent(0.85))
    y += formulaBox.height + 18

    // ---- 4) Reference bands table ----
    drawText(zh ? "4. 分数区间" : "4. REFERENCE BANDS",
             at: CGPoint(x: x, y: y),
             font: PDFType.h2,
             color: theme.deep.uiSolid)
    y += 22
    let bandRows: [(String, String, UIColor)] = zh
        ? [("90–100", "优秀范围",   UIColor.systemGreen),
           ("70–89",  "正常范围",   UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)),
           ("40–69",  "需要观察",   UIColor.systemOrange),
           ("0–39",   "需要复查",   UIColor.systemRed)]
        : [("90–100", "Above-average",        UIColor.systemGreen),
           ("70–89",  "Within normal range",  UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)),
           ("40–69",  "Requires monitoring",  UIColor.systemOrange),
           ("0–39",   "Requires follow-up",   UIColor.systemRed)]
    y = drawTableHeader(cg: cg, x: x, y: y, w: w,
                         columns: [(zh ? "区间" : "RANGE",  0),
                                   (zh ? "等级" : "LEVEL", 100)])
    for (i, row) in bandRows.enumerated() {
        let rowY = y
        // zebra
        if i % 2 == 1 {
            UIColor(white: 0.97, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: x, y: rowY - 3, width: w, height: 20)).fill()
        }
        // color stripe at the leftmost edge of the row
        UIBezierPath(roundedRect: CGRect(x: x - 4, y: rowY - 1, width: 3, height: 16),
                     cornerRadius: 1.5).fill()
        row.2.setFill()
        UIBezierPath(roundedRect: CGRect(x: x - 4, y: rowY - 1, width: 3, height: 16),
                     cornerRadius: 1.5).fill()
        drawText(row.0, at: CGPoint(x: x, y: rowY),
                 font: monoCellFont(),
                 color: row.2)
        drawText(row.1, at: CGPoint(x: x + 100, y: rowY),
                 font: PDFType.bodyMedium,
                 color: UIColor.black.withAlphaComponent(0.85))
        y = rowY + 20
        UIColor(white: 0.92, alpha: 1).setStroke()
        cg.setLineWidth(0.5)
        cg.move(to: CGPoint(x: x, y: y - 3))
        cg.addLine(to: CGPoint(x: x + w, y: y - 3))
        cg.strokePath()
    }
    y += 18

    // ---- 5) Limitations (red callout box) ----
    drawText(zh ? "5. 局限与说明" : "5. LIMITATIONS",
             at: CGPoint(x: x, y: y),
             font: PDFType.h2,
             color: UIColor.systemRed)
    y += 22
    let limits = zh
        ? "本评分基于影像筛查,不能替代血液检查、寄生虫筛查、触诊、听诊或其他临床手段。任何低于 40 分或带 [URGENT] 标记的报告应由执业兽医复审。"
        : "This score is image-based screening only. It cannot replace bloodwork, parasite testing, palpation, auscultation or other clinical means. Any report scoring below 40 or marked [URGENT] should be reviewed by a licensed veterinarian."
    let limitH = wrappedRowHeight(text: limits, width: w - 24, font: PDFType.body) + 22
    let limitBox = CGRect(x: x, y: y, width: w, height: limitH)
    UIColor.systemRed.withAlphaComponent(0.06).setFill()
    UIBezierPath(roundedRect: limitBox, cornerRadius: 6).fill()
    UIColor.systemRed.withAlphaComponent(0.25).setStroke()
    let limitStroke = UIBezierPath(roundedRect: limitBox, cornerRadius: 6)
    limitStroke.lineWidth = 0.5
    limitStroke.stroke()
    _ = drawWrappedText(limits,
                        in: CGRect(x: x + 12, y: y + 11, width: w - 24, height: limitH - 16),
                        font: PDFType.body,
                        color: UIColor.black.withAlphaComponent(0.8),
                        lineSpacing: 3)
}
