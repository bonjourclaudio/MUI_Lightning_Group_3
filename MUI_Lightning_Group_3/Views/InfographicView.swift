//
//  InfographicView.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI

/// Floating panel next to the model: cross-section of a thunderstorm cloud
/// (precipitation + charge distribution), highlighting what the narration explains.
struct InfographicView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let focus = appModel.infographic
        VStack(alignment: .leading, spacing: 14) {
            Text(title(for: focus))
                .font(.title2.bold())
            CloudCrossSection(focus: focus)
                .frame(width: 464, height: 400)
            Text(caption(for: focus))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if focus == .game {
                ChargeMeter(game: appModel.game)
            }
        }
        .padding(28)
        .frame(width: 520)
        .glassBackgroundEffect()
        .animation(.easeInOut(duration: 0.5), value: focus)
    }

    private func title(for focus: InfographicFocus) -> String {
        switch focus {
        case .hidden, .overview: return "Anatomy of a thunderstorm cloud"
        case .precipitation: return "Precipitation inside the cloud"
        case .charges: return "How charge separates"
        case .rain: return "From hail to rain"
        case .game: return "Charge up the storm"
        }
    }

    private func caption(for focus: InfographicFocus) -> String {
        switch focus {
        case .hidden, .overview:
            return "Updrafts carry warm, moist air far above the freezing level. At the tropopause the cloud can't rise any further and spreads into an anvil."
        case .precipitation:
            return "Above the 0 °C line, droplets stay liquid even below freezing (supercooled). They freeze onto ice particles – graupel and hail grow."
        case .charges:
            return "Collisions between light ice crystals and heavier graupel transfer charge: ice crystals (+) rise to the top, graupel (−) gathers in the middle."
        case .rain:
            return "Graupel and hail become too heavy for the updraft and fall. Below the 0 °C line they melt into rain – big hailstones reach the ground."
        case .game:
            return "Bring positive and negative charge into the cloud. When the tension gets too high, the air can no longer insulate – lightning!"
        }
    }
}

// MARK: - Cross-section drawing

struct CloudCrossSection: View {
    let focus: InfographicFocus

    private struct Emphasis {
        var ice = 1.0, graupel = 1.0, droplets = 1.0, rain = 1.0, charges = 0.0, updraft = 1.0
    }

    private var emphasis: Emphasis {
        switch focus {
        case .hidden, .overview:
            return Emphasis(ice: 0.6, graupel: 0.6, droplets: 0.6, rain: 0.6, charges: 0, updraft: 1)
        case .precipitation:
            return Emphasis(ice: 1, graupel: 1, droplets: 1, rain: 0.35, charges: 0, updraft: 1)
        case .charges:
            return Emphasis(ice: 1, graupel: 1, droplets: 0.3, rain: 0.3, charges: 1, updraft: 0.5)
        case .rain:
            return Emphasis(ice: 0.3, graupel: 0.6, droplets: 0.3, rain: 1, charges: 0.3, updraft: 0.3)
        case .game:
            return Emphasis(ice: 0.8, graupel: 0.8, droplets: 0.6, rain: 0.8, charges: 1, updraft: 0.6)
        }
    }

    var body: some View {
        Canvas { context, size in
            var ctx = context
            ctx.scaleBy(x: size.width / 460, y: size.height / 400)
            let e = emphasis

            drawBackground(&ctx)
            drawAltitudeLines(&ctx)
            drawCloud(&ctx)

            var layer = ctx
            layer.opacity = e.updraft
            drawUpdraft(&layer)

            layer = ctx; layer.opacity = e.droplets
            for i in 0..<26 {
                let p = point(i, 1, x: 165...315, y: 215...320)
                layer.fill(Path(ellipseIn: CGRect(x: p.x - 2.2, y: p.y - 2.2, width: 4.4, height: 4.4)),
                           with: .color(Color(red: 0.35, green: 0.6, blue: 0.95)))
            }

            layer = ctx; layer.opacity = e.ice
            for i in 0..<26 {
                let p = i < 16 ? point(i, 2, x: 75...415, y: 70...98) : point(i, 3, x: 185...290, y: 120...165)
                star(&layer, at: p, radius: 4.5, color: Color(red: 0.2, green: 0.38, blue: 0.7))
            }

            layer = ctx; layer.opacity = e.graupel
            for i in 0..<16 {
                let p = point(i, 4, x: 190...290, y: 180...255)
                let rect = CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)
                layer.fill(Path(ellipseIn: rect), with: .color(Color(white: 0.96)))
                layer.stroke(Path(ellipseIn: rect), with: .color(Color(white: 0.45)), lineWidth: 1)
            }

            layer = ctx; layer.opacity = e.rain
            drawPrecipitation(&layer)

            layer = ctx; layer.opacity = e.charges
            drawCharges(&layer)

            drawLabels(&ctx, e)
        }
    }

    // MARK: Parts

    private func drawBackground(_ ctx: inout GraphicsContext) {
        let sky = Path(roundedRect: CGRect(x: 0, y: 0, width: 460, height: 400), cornerRadius: 18)
        ctx.fill(sky, with: .linearGradient(Gradient(colors: [Color(red: 0.1, green: 0.15, blue: 0.27),
                                                              Color(red: 0.3, green: 0.38, blue: 0.5)]),
                                            startPoint: .zero, endPoint: CGPoint(x: 0, y: 400)))
        ctx.fill(Path(CGRect(x: 0, y: 372, width: 460, height: 28)),
                 with: .color(Color(red: 0.33, green: 0.44, blue: 0.27)))
    }

    private func drawAltitudeLines(_ ctx: inout GraphicsContext) {
        let lines: [(y: CGFloat, label: String)] = [(58, "Tropopause ≈ 11 km"), (175, "−20 °C ≈ 7 km"), (255, "0 °C ≈ 4 km")]
        for line in lines {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: line.y))
            path.addLine(to: CGPoint(x: 460, y: line.y))
            ctx.stroke(path, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ctx.draw(Text(line.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8)),
                     at: CGPoint(x: 8, y: line.y - 9), anchor: .leading)
        }
    }

    private func drawCloud(_ ctx: inout GraphicsContext) {
        var p = Path()
        p.move(to: CGPoint(x: 140, y: 335))
        p.addCurve(to: CGPoint(x: 170, y: 120), control1: CGPoint(x: 120, y: 260), control2: CGPoint(x: 175, y: 190))
        p.addCurve(to: CGPoint(x: 40, y: 92), control1: CGPoint(x: 120, y: 112), control2: CGPoint(x: 60, y: 108))
        p.addQuadCurve(to: CGPoint(x: 70, y: 62), control: CGPoint(x: 28, y: 64))
        p.addLine(to: CGPoint(x: 410, y: 58))
        p.addQuadCurve(to: CGPoint(x: 432, y: 88), control: CGPoint(x: 445, y: 62))
        p.addCurve(to: CGPoint(x: 300, y: 125), control1: CGPoint(x: 380, y: 106), control2: CGPoint(x: 320, y: 108))
        p.addCurve(to: CGPoint(x: 330, y: 335), control1: CGPoint(x: 290, y: 200), control2: CGPoint(x: 350, y: 260))
        p.addQuadCurve(to: CGPoint(x: 235, y: 342), control: CGPoint(x: 285, y: 352))
        p.addQuadCurve(to: CGPoint(x: 140, y: 335), control: CGPoint(x: 185, y: 352))
        p.closeSubpath()
        ctx.fill(p, with: .linearGradient(Gradient(colors: [Color(white: 0.97), Color(white: 0.55)]),
                                          startPoint: CGPoint(x: 0, y: 60), endPoint: CGPoint(x: 0, y: 340)))
        ctx.stroke(p, with: .color(.white.opacity(0.6)), lineWidth: 1.5)
    }

    private func drawUpdraft(_ ctx: inout GraphicsContext) {
        var shaft = Path()
        shaft.move(to: CGPoint(x: 238, y: 325))
        shaft.addLine(to: CGPoint(x: 238, y: 152))
        ctx.stroke(shaft, with: .color(.orange.opacity(0.85)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        var head = Path()
        head.move(to: CGPoint(x: 238, y: 138))
        head.addLine(to: CGPoint(x: 228, y: 156))
        head.addLine(to: CGPoint(x: 248, y: 156))
        head.closeSubpath()
        ctx.fill(head, with: .color(.orange.opacity(0.85)))
    }

    private func drawPrecipitation(_ ctx: inout GraphicsContext) {
        for i in 0..<18 {
            let x = 160 + rnd(i, 5) * 160
            let y0 = 348 + rnd(i, 6) * 6
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y0))
            drop.addLine(to: CGPoint(x: x - 5, y: 371))
            ctx.stroke(drop, with: .color(Color(red: 0.6, green: 0.8, blue: 1)), lineWidth: 1.5)
        }
        for i in 0..<5 {
            let p = point(i, 7, x: 175...305, y: 352...366)
            let rect = CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white))
        }
    }

    private func drawCharges(_ ctx: inout GraphicsContext) {
        let plus = Text("+").font(.system(size: 15, weight: .heavy)).foregroundStyle(Color(red: 1, green: 0.3, blue: 0.25))
        let minus = Text("−").font(.system(size: 17, weight: .heavy)).foregroundStyle(Color(red: 0.25, green: 0.5, blue: 1))
        for i in 0..<12 { ctx.draw(plus, at: point(i, 8, x: 85...405, y: 72...100)) }
        for i in 0..<10 { ctx.draw(minus, at: point(i, 9, x: 192...288, y: 185...252)) }
        for i in 0..<3 { ctx.draw(plus.font(.system(size: 11, weight: .heavy)), at: point(i, 10, x: 210...260, y: 318...330)) }
    }

    private func drawLabels(_ ctx: inout GraphicsContext, _ e: Emphasis) {
        let showCharge = e.charges > 0.5
        let labels: [(text: String, y: CGFloat, target: CGPoint, opacity: Double)] = [
            (showCharge ? "Ice crystals (+)" : "Ice crystals", 140, CGPoint(x: 292, y: 135), e.ice),
            (showCharge ? "Graupel & hail (−)" : "Graupel & hail", 215, CGPoint(x: 292, y: 215), e.graupel),
            ("Supercooled droplets", 292, CGPoint(x: 318, y: 292), e.droplets),
            ("Rain & hail", 360, CGPoint(x: 312, y: 360), e.rain),
        ]
        for label in labels {
            var layer = ctx
            layer.opacity = max(label.opacity, 0.35)
            var leader = Path()
            leader.move(to: CGPoint(x: 336, y: label.y))
            leader.addLine(to: label.target)
            layer.stroke(leader, with: .color(.white.opacity(0.7)), lineWidth: 1)
            layer.draw(Text(label.text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white),
                       at: CGPoint(x: 340, y: label.y), anchor: .leading)
        }
    }

    // MARK: Helpers

    private func star(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, color: Color) {
        var path = Path()
        for k in 0..<3 {
            let a = CGFloat(k) * .pi / 3
            path.move(to: CGPoint(x: p.x - cos(a) * r, y: p.y - sin(a) * r))
            path.addLine(to: CGPoint(x: p.x + cos(a) * r, y: p.y + sin(a) * r))
        }
        ctx.stroke(path, with: .color(color), lineWidth: 1.4)
    }

    /// Stable pseudo-random 0…1.
    private func rnd(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i * 127 + salt * 311 + 17) * 12.9898) * 43_758.5453
        return CGFloat(v - floor(v))
    }

    private func point(_ i: Int, _ salt: Int, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> CGPoint {
        CGPoint(x: x.lowerBound + rnd(i, salt) * (x.upperBound - x.lowerBound),
                y: y.lowerBound + rnd(i, salt + 50) * (y.upperBound - y.lowerBound))
    }
}

// MARK: - Live charge meter (interactive part)

struct ChargeMeter: View {
    let game: StormGame

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 24) {
                Label("\(game.positive) positive", systemImage: "plus.circle.fill")
                    .foregroundStyle(.red)
                Label("\(game.negative) negative", systemImage: "minus.circle.fill")
                    .foregroundStyle(.blue)
            }
            .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Electrical tension")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [.yellow, .orange, .purple], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(14, 464 * CGFloat(game.intensity)))
                        .opacity(game.intensity > 0 ? 1 : 0)
                }
                .frame(width: 464, height: 14)
                .animation(.spring(duration: 0.6), value: game.intensity)

                Text(status)
                    .font(.callout)
            }
        }
    }

    private var status: String {
        let d = game.imbalance
        if game.positive + game.negative == 0 { return "Drag charged clouds into the storm." }
        if d >= 2 { return "Too much positive charge – add negative clouds." }
        if d <= -2 { return "Too much negative charge – add positive clouds." }
        return "Balanced – the tension rises. Lightning when the air can no longer insulate."
    }
}
