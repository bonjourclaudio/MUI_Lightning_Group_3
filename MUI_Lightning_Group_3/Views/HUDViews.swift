//
//  HUDViews.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI

/// Always visible, bottom right of the field of view.
struct StopButtonView: View {
    let onStop: () -> Void

    var body: some View {
        // Standard visionOS button on a glass capsule: system material, white label,
        // gaze highlight and press feedback come for free.
        Button(action: onStop) {
            Label("Stop", systemImage: "stop.fill")
                .font(.title3)
                .padding(.horizontal, 6)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .help("End the experience")
        .padding(8)
        .glassBackgroundEffect(in: Capsule())
    }
}

/// Short hint while playing (silent version: the only on-screen guidance).
struct HintView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack {
            if appModel.phase == .playing {
                Label("Drag the + and − clouds into the storm – or tap them", systemImage: "hand.draw")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .glassBackgroundEffect()
            }
        }
        .frame(width: 800, height: 120, alignment: .bottom)
        .animation(.easeInOut(duration: 0.3), value: appModel.phase)
    }
}

struct AfterStrikeView: View {
    @Environment(AppModel.self) private var appModel
    let onAgain: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "cloud.bolt.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.multicolor)
            Text("Lightning!")
                .font(.title.bold())
            Text(appModel.stormsBuilt == 1 ? "You built 1 thunderstorm." : "You built \(appModel.stormsBuilt) thunderstorms.")
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button(action: onAgain) {
                    Label("Build another storm", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                Button(action: onFinish) {
                    Label("Finish", systemImage: "checkmark")
                }
            }
            .controlSize(.large)
        }
        .padding(32)
        .glassBackgroundEffect()
    }
}
