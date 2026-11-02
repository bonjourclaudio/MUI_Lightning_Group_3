//
//  SunInstructionView.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI

/// Opening instruction: drag the sun from sunrise to midday. The story starts once it's done.
struct SunInstructionView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.pinch.fill")
                .font(.system(size: 54))
                .foregroundStyle(.orange)
                .symbolEffect(.bounce, options: .repeating)

            VStack(spacing: 8) {
                Text("Move the sun across the sky")
                    .font(.title.bold())
                Text("Look at the sun, pinch it and drag it along the white line – from morning to midday.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                Image(systemName: "sunrise.fill")
                    .foregroundStyle(.orange)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule()
                            .fill(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(14, proxy.size.width * CGFloat(appModel.sunDragProgress)))
                    }
                }
                .frame(height: 14)
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.yellow)
            }
            .font(.title2)
            .animation(.easeOut(duration: 0.2), value: appModel.sunDragProgress)
        }
        .padding(36)
        .frame(width: 620)
        .glassBackgroundEffect()
    }
}
