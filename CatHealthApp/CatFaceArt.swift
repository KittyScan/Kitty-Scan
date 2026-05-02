import SwiftUI
import UIKit

/// The beloved cartoon cat face — Canvas-based port of the HTML SVG (140×140).
/// All path coordinates are authored in a 140×140 space; the transform scales to `size`.
struct CatFace: View {
    let theme: CatTheme
    var avatarData: Data? = nil
    var size: CGFloat = 120
    var showHalo: Bool = false

    var body: some View {
        ZStack {
            if showHalo {
                Circle()
                    .fill(theme.light.opacity(0.45))
                    .frame(width: size + 14, height: size + 14)
            }
            Group {
                // Downsampled decode — avoids decompressing full original (e.g., 4000×3000 JPEG)
                // which otherwise blows memory during export rendering.
                if let data = avatarData,
                   let img = AvatarImage.decode(data: data, maxPixelSize: max(size * 3, 256)) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(theme.main.opacity(0.25), lineWidth: 0.5))
                } else {
                    Canvas(rendersAsynchronously: false) { ctx, canvasSize in
                        var c = ctx
                        draw(into: &c, canvasSize: canvasSize)
                    }
                    .frame(width: size, height: size)
                }
            }
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 3)
        }
        .frame(width: showHalo ? size + 14 : size,
               height: showHalo ? size + 14 : size)
    }

    // MARK: - Drawing
    private func draw(into ctx: inout GraphicsContext, canvasSize: CGSize) {
        let s = min(canvasSize.width, canvasSize.height) / 140
        ctx.transform = CGAffineTransform(scaleX: s, y: s)

        let p = theme.pattern
        let isLonghair = p.contains("longhair")
        let isFold = (p == "fold")
        let isSphynx = (p == "sphynx")
        let isPointed = (p == "pointed")
        let isTabby = p.contains("tabby")
        let isCalico = (p == "calico")
        let isTuxedo = (p == "tuxedo")
        let isTuxedoOrange = (p == "tuxedo-orange")
        let isTortie = (p == "tortie")
        let isSpotted = (p == "spotted")
        let isOddEye = (p == "odd-eye")

        let colMain = theme.main
        let colDeep = theme.deep
        let colNose = theme.nose

        // --- Halo (longhair) ---
        if isLonghair {
            ctx.fill(Path(ellipseIn: CGRect(x: 2, y: 16, width: 136, height: 124)),
                     with: .color(colMain.opacity(0.25)))
            ctx.fill(Path(ellipseIn: CGRect(x: 8, y: 20, width: 124, height: 116)),
                     with: .color(theme.light.opacity(0.45)))
        }

        // --- Ears outer + inner ---
        if isFold {
            ctx.fill(earFold(left: true), with: .color(colMain))
            ctx.fill(earFold(left: false), with: .color(colMain))
        } else if isSphynx {
            ctx.fill(earSphynx(left: true), with: .color(colMain))
            ctx.fill(earSphynx(left: false), with: .color(colMain))
            ctx.fill(earInner(left: true, offsetY: 2), with: .color(theme.accent.opacity(0.7)))
            ctx.fill(earInner(left: false, offsetY: 2), with: .color(theme.accent.opacity(0.7)))
        } else {
            ctx.fill(earOuter(left: true), with: .color(colMain))
            ctx.fill(earOuter(left: false), with: .color(colMain))
            ctx.fill(earInner(left: true, offsetY: 0), with: .color(theme.accent.opacity(0.7)))
            ctx.fill(earInner(left: false, offsetY: 0), with: .color(theme.accent.opacity(0.7)))
        }

        // --- Head base ---
        ctx.fill(Path(ellipseIn: CGRect(x: 18, y: 28, width: 104, height: 100)),
                 with: .color(colMain))

        // --- Pointed mask (ragdoll/siamese) ---
        if isPointed {
            ctx.fill(Path(ellipseIn: CGRect(x: 18, y: 28, width: 104, height: 100)),
                     with: .color(theme.bg))
            ctx.fill(Path(ellipseIn: CGRect(x: 32, y: 65, width: 76, height: 60)),
                     with: .color(colMain.opacity(0.4)))
            ctx.fill(Path(ellipseIn: CGRect(x: 50, y: 48, width: 40, height: 24)),
                     with: .color(colMain.opacity(0.35)))
        }

        // --- Tabby stripes ---
        if isTabby {
            ctx.fill(Path(roundedRect: CGRect(x: 52, y: 32, width: 36, height: 4.5),
                          cornerSize: CGSize(width: 2, height: 2)),
                     with: .color(colDeep.opacity(0.85)))
            ctx.fill(Path(roundedRect: CGRect(x: 67.5, y: 26, width: 5, height: 18),
                          cornerSize: CGSize(width: 2.5, height: 2.5)),
                     with: .color(colDeep.opacity(0.85)))

            // rotated side stripes (two sets)
            drawRotatedStripe(&ctx, x: 30, y: 56, w: 16, h: 3.5, pivot: CGPoint(x: 38, y: 58), angle: -0.262, alpha: 0.7)
            drawRotatedStripe(&ctx, x: 94, y: 56, w: 16, h: 3.5, pivot: CGPoint(x: 102, y: 58), angle: 0.262, alpha: 0.7)
            drawRotatedStripe(&ctx, x: 26, y: 70, w: 14, h: 3, pivot: CGPoint(x: 33, y: 71), angle: -0.175, alpha: 0.6)
            drawRotatedStripe(&ctx, x: 100, y: 70, w: 14, h: 3, pivot: CGPoint(x: 107, y: 71), angle: 0.175, alpha: 0.6)
        }

        // --- Calico ---
        if isCalico {
            ctx.fill(Path { p in
                p.move(to: CGPoint(x: 18, y: 55))
                p.addQuadCurve(to: CGPoint(x: 40, y: 26), control: CGPoint(x: 20, y: 30))
                p.addQuadCurve(to: CGPoint(x: 44, y: 62), control: CGPoint(x: 50, y: 38))
                p.addQuadCurve(to: CGPoint(x: 18, y: 55), control: CGPoint(x: 30, y: 66))
                p.closeSubpath()
            }, with: .color(colDeep.opacity(0.92)))
            ctx.fill(Path { p in
                p.move(to: CGPoint(x: 95, y: 28))
                p.addQuadCurve(to: CGPoint(x: 120, y: 62), control: CGPoint(x: 118, y: 36))
                p.addQuadCurve(to: CGPoint(x: 92, y: 60), control: CGPoint(x: 108, y: 68))
                p.addQuadCurve(to: CGPoint(x: 95, y: 28), control: CGPoint(x: 86, y: 42))
                p.closeSubpath()
            }, with: .color(colMain))
            ctx.fill(Path(ellipseIn: CGRect(x: 56, y: 34, width: 28, height: 12)),
                     with: .color(colDeep.opacity(0.88)))
        }

        // --- Tuxedo (black top, white chin) ---
        if isTuxedo {
            ctx.fill(Path { p in
                p.move(to: CGPoint(x: 20, y: 78))
                p.addQuadCurve(to: CGPoint(x: 70, y: 26), control: CGPoint(x: 20, y: 30))
                p.addQuadCurve(to: CGPoint(x: 120, y: 78), control: CGPoint(x: 120, y: 30))
                p.addQuadCurve(to: CGPoint(x: 95, y: 55), control: CGPoint(x: 120, y: 60))
                p.addQuadCurve(to: CGPoint(x: 45, y: 55), control: CGPoint(x: 70, y: 60))
                p.addQuadCurve(to: CGPoint(x: 20, y: 78), control: CGPoint(x: 20, y: 60))
                p.closeSubpath()
            }, with: .color(colDeep))
            ctx.fill(Path(ellipseIn: CGRect(x: 34, y: 76, width: 72, height: 48)),
                     with: .color(theme.bg))
            ctx.fill(Path(ellipseIn: CGRect(x: 36, y: 78, width: 28, height: 20)),
                     with: .color(theme.bg.opacity(0.9)))
            ctx.fill(Path(ellipseIn: CGRect(x: 76, y: 78, width: 28, height: 20)),
                     with: .color(theme.bg.opacity(0.9)))
        }

        // --- Tuxedo-orange (orange top, white face) ---
        if isTuxedoOrange {
            ctx.fill(Path { p in
                p.move(to: CGPoint(x: 22, y: 60))
                p.addQuadCurve(to: CGPoint(x: 70, y: 26), control: CGPoint(x: 22, y: 28))
                p.addQuadCurve(to: CGPoint(x: 118, y: 60), control: CGPoint(x: 118, y: 28))
                p.addQuadCurve(to: CGPoint(x: 95, y: 48), control: CGPoint(x: 118, y: 50))
                p.addQuadCurve(to: CGPoint(x: 45, y: 48), control: CGPoint(x: 70, y: 52))
                p.addQuadCurve(to: CGPoint(x: 22, y: 60), control: CGPoint(x: 22, y: 50))
                p.closeSubpath()
            }, with: .color(colMain))
            ctx.fill(Path(ellipseIn: CGRect(x: 28, y: 68, width: 84, height: 60)),
                     with: .color(theme.bg))
        }

        // --- Tortie ---
        if isTortie {
            ctx.fill(Path { p in
                p.move(to: CGPoint(x: 18, y: 50))
                p.addQuadCurve(to: CGPoint(x: 20, y: 96), control: CGPoint(x: 28, y: 70))
                p.addQuadCurve(to: CGPoint(x: 48, y: 68), control: CGPoint(x: 40, y: 92))
                p.addQuadCurve(to: CGPoint(x: 18, y: 50), control: CGPoint(x: 42, y: 44))
                p.closeSubpath()
            }, with: .color(colDeep.opacity(0.88)))
            ctx.fill(Path { p in
                p.move(to: CGPoint(x: 92, y: 40))
                p.addQuadCurve(to: CGPoint(x: 122, y: 82), control: CGPoint(x: 118, y: 52))
                p.addQuadCurve(to: CGPoint(x: 94, y: 80), control: CGPoint(x: 108, y: 98))
                p.addQuadCurve(to: CGPoint(x: 92, y: 40), control: CGPoint(x: 90, y: 58))
                p.closeSubpath()
            }, with: .color(colDeep.opacity(0.85)))
            ctx.fill(Path(ellipseIn: CGRect(x: 52, y: 32, width: 28, height: 12)),
                     with: .color(colDeep.opacity(0.75)))
            ctx.fill(Path(ellipseIn: CGRect(x: 68, y: 100, width: 20, height: 10)),
                     with: .color(colDeep.opacity(0.7)))
        }

        // --- Spotted (bengal) ---
        if isSpotted {
            let spots: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (40, 55, 4, 3), (54, 42, 3.5, 2.5), (96, 42, 3.5, 2.5), (100, 55, 4, 3),
                (34, 72, 3, 2), (106, 72, 3, 2), (38, 92, 4, 2.5), (102, 92, 4, 2.5)
            ]
            for (cx, cy, rx, ry) in spots {
                ctx.fill(Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry,
                                                width: rx * 2, height: ry * 2)),
                         with: .color(colDeep.opacity(0.85)))
            }
        }

        // --- Sphynx wrinkles ---
        if isSphynx {
            ctx.stroke(Path { pp in
                pp.move(to: CGPoint(x: 50, y: 50))
                pp.addQuadCurve(to: CGPoint(x: 90, y: 50), control: CGPoint(x: 70, y: 54))
            }, with: .color(colDeep.opacity(0.35)), lineWidth: 0.8)
            ctx.stroke(Path { pp in
                pp.move(to: CGPoint(x: 48, y: 58))
                pp.addQuadCurve(to: CGPoint(x: 92, y: 58), control: CGPoint(x: 70, y: 62))
            }, with: .color(colDeep.opacity(0.3)), lineWidth: 0.8)
            ctx.stroke(Path { pp in
                pp.move(to: CGPoint(x: 52, y: 66))
                pp.addQuadCurve(to: CGPoint(x: 88, y: 66), control: CGPoint(x: 70, y: 70))
            }, with: .color(colDeep.opacity(0.25)), lineWidth: 0.8)
        }

        // --- Eyes ---
        ctx.fill(Path(ellipseIn: CGRect(x: 44.5, y: 68, width: 15, height: 20)), with: .color(.black))
        ctx.fill(Path(ellipseIn: CGRect(x: 80.5, y: 68, width: 15, height: 20)), with: .color(.black))

        let leftIris = theme.eye
        let rightIris = isOddEye ? (theme.eyeSecondary ?? theme.eye) : theme.eye
        ctx.fill(Path(ellipseIn: CGRect(x: 48, y: 70, width: 8, height: 12)), with: .color(leftIris))
        ctx.fill(Path(ellipseIn: CGRect(x: 84, y: 70, width: 8, height: 12)), with: .color(rightIris))

        // pupil + highlight
        ctx.fill(Path(ellipseIn: CGRect(x: 50, y: 73, width: 4, height: 6)), with: .color(.black.opacity(0.6)))
        ctx.fill(Path(ellipseIn: CGRect(x: 86, y: 73, width: 4, height: 6)), with: .color(.black.opacity(0.6)))
        ctx.fill(Path(ellipseIn: CGRect(x: 51.6, y: 72, width: 2.4, height: 4)), with: .color(.white.opacity(0.9)))
        ctx.fill(Path(ellipseIn: CGRect(x: 87.6, y: 72, width: 2.4, height: 4)), with: .color(.white.opacity(0.9)))

        // --- Cheeks ---
        ctx.fill(Path(ellipseIn: CGRect(x: 23, y: 88, width: 14, height: 8)),
                 with: .color(colNose.opacity(0.55)))
        ctx.fill(Path(ellipseIn: CGRect(x: 103, y: 88, width: 14, height: 8)),
                 with: .color(colNose.opacity(0.55)))

        // --- Nose ---
        ctx.fill(Path { p in
            p.move(to: CGPoint(x: 64, y: 94))
            p.addQuadCurve(to: CGPoint(x: 76, y: 94), control: CGPoint(x: 70, y: 98))
            p.addQuadCurve(to: CGPoint(x: 70, y: 105), control: CGPoint(x: 76, y: 102))
            p.addQuadCurve(to: CGPoint(x: 64, y: 94), control: CGPoint(x: 64, y: 102))
            p.closeSubpath()
        }, with: .color(colNose))

        // --- Mouth (\-/-ω-\/) ---
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: 70, y: 105))
            p.addLine(to: CGPoint(x: 70, y: 111))
        }, with: .color(colDeep), lineWidth: 1.1)
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: 70, y: 111))
            p.addQuadCurve(to: CGPoint(x: 60, y: 110), control: CGPoint(x: 63, y: 114))
        }, with: .color(colDeep), lineWidth: 1.1)
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: 70, y: 111))
            p.addQuadCurve(to: CGPoint(x: 80, y: 110), control: CGPoint(x: 77, y: 114))
        }, with: .color(colDeep), lineWidth: 1.1)

        // --- Whiskers ---
        for (y1, y2) in [(CGFloat(92), CGFloat(94)), (CGFloat(98), CGFloat(98))] {
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: 6, y: y1))
                p.addLine(to: CGPoint(x: 28, y: y2))
            }, with: .color(colDeep.opacity(0.55)), lineWidth: 0.7)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: 112, y: y2))
                p.addLine(to: CGPoint(x: 134, y: y1))
            }, with: .color(colDeep.opacity(0.55)), lineWidth: 0.7)
        }
    }

    // MARK: - Path helpers
    private func earOuter(left: Bool) -> Path {
        Path { p in
            if left {
                p.move(to: CGPoint(x: 25, y: 38))
                p.addQuadCurve(to: CGPoint(x: 48, y: 26), control: CGPoint(x: 14, y: 4))
                p.addQuadCurve(to: CGPoint(x: 25, y: 38), control: CGPoint(x: 42, y: 32))
            } else {
                p.move(to: CGPoint(x: 115, y: 38))
                p.addQuadCurve(to: CGPoint(x: 92, y: 26), control: CGPoint(x: 126, y: 4))
                p.addQuadCurve(to: CGPoint(x: 115, y: 38), control: CGPoint(x: 98, y: 32))
            }
            p.closeSubpath()
        }
    }
    private func earInner(left: Bool, offsetY: CGFloat) -> Path {
        Path { p in
            if left {
                p.move(to: CGPoint(x: 32, y: 34 + offsetY))
                p.addQuadCurve(to: CGPoint(x: 43, y: 27 + offsetY), control: CGPoint(x: 26, y: 14 + offsetY))
                p.addQuadCurve(to: CGPoint(x: 32, y: 34 + offsetY), control: CGPoint(x: 38, y: 32 + offsetY))
            } else {
                p.move(to: CGPoint(x: 108, y: 34 + offsetY))
                p.addQuadCurve(to: CGPoint(x: 97, y: 27 + offsetY), control: CGPoint(x: 114, y: 14 + offsetY))
                p.addQuadCurve(to: CGPoint(x: 108, y: 34 + offsetY), control: CGPoint(x: 102, y: 32 + offsetY))
            }
            p.closeSubpath()
        }
    }
    private func earFold(left: Bool) -> Path {
        Path { p in
            if left {
                p.move(to: CGPoint(x: 30, y: 32))
                p.addQuadCurve(to: CGPoint(x: 46, y: 28), control: CGPoint(x: 25, y: 22))
                p.addQuadCurve(to: CGPoint(x: 30, y: 32), control: CGPoint(x: 44, y: 38))
            } else {
                p.move(to: CGPoint(x: 110, y: 32))
                p.addQuadCurve(to: CGPoint(x: 94, y: 28), control: CGPoint(x: 115, y: 22))
                p.addQuadCurve(to: CGPoint(x: 110, y: 32), control: CGPoint(x: 96, y: 38))
            }
            p.closeSubpath()
        }
    }
    private func earSphynx(left: Bool) -> Path {
        Path { p in
            if left {
                p.move(to: CGPoint(x: 18, y: 40))
                p.addQuadCurve(to: CGPoint(x: 52, y: 22), control: CGPoint(x: 8, y: -4))
                p.addQuadCurve(to: CGPoint(x: 18, y: 40), control: CGPoint(x: 46, y: 32))
            } else {
                p.move(to: CGPoint(x: 122, y: 40))
                p.addQuadCurve(to: CGPoint(x: 88, y: 22), control: CGPoint(x: 132, y: -4))
                p.addQuadCurve(to: CGPoint(x: 122, y: 40), control: CGPoint(x: 94, y: 32))
            }
            p.closeSubpath()
        }
    }

    private func drawRotatedStripe(_ ctx: inout GraphicsContext,
                                   x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                                   pivot: CGPoint, angle: CGFloat, alpha: Double) {
        let saved = ctx.transform
        ctx.transform = saved
            .translatedBy(x: pivot.x, y: pivot.y)
            .rotated(by: angle)
            .translatedBy(x: -pivot.x, y: -pivot.y)
        ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                      cornerSize: CGSize(width: h / 2, height: h / 2)),
                 with: .color(theme.deep.opacity(alpha)))
        ctx.transform = saved
    }
}

/// Small wrapper used across lists / headers. Keeps a consistent API from before.
struct CatAvatar: View {
    let theme: CatTheme
    var avatarData: Data? = nil
    var size: CGFloat = 72
    var showRing: Bool = true

    var body: some View {
        CatFace(theme: theme, avatarData: avatarData, size: size, showHalo: showRing)
    }
}
