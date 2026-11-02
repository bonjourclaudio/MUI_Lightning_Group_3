//
//  StormProgressView.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI

/// Centred panel below the landscape: how close the storm is to lightning.
struct StormProgressView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let game = appModel.game
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Label("Storm energy", systemImage: "cloud.bolt.fill")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(Int((appModel.stormLevel * 100).rounded())) %")
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Bar(value: appModel.stormLevel,
                gradient: [.yellow, .orange, .purple],
                height: 26)
                .overlay(alignment: .trailing) {
                    // Breakdown threshold of the air → lightning.
                    Image(systemName: "bolt.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                        .padding(.trailing, 8)
                }

            HStack(spacing: 28) {
                Label("\(game.positive)", systemImage: "plus.circle.fill")
                    .foregroundStyle(.red)
                Label("\(game.negative)", systemImage: "minus.circle.fill")
                    .foregroundStyle(.blue)
                Spacer()
            }
            .font(.title3.weight(.semibold))

            Text(status)
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(32)
        .frame(width: 760)
        .glassBackgroundEffect()
        .animation(.spring(duration: 0.6), value: appModel.stormLevel)
    }

    private var status: String {
        let game = appModel.game
        switch appModel.phase {
        case .lightning: return "The air can no longer insulate the charge…"
        case .afterStrike: return "Discharged. Build another storm or finish."
        default: break
        }
        let d = game.imbalance
        if game.positive + game.negative == 0 { return "Drag + and − clouds into the storm." }
        if d >= 2 { return "Too much positive charge – add negative clouds." }
        if d <= -2 { return "Too much negative charge – add positive clouds." }
        return "Balanced – the tension is rising."
    }
}

private struct Bar: View {
    let value: Float
    let gradient: [Color]
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, proxy.size.width * CGFloat(min(max(value, 0), 1))))
                    .opacity(value > 0.005 ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}
