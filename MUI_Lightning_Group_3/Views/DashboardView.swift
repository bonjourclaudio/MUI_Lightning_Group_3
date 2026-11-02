//
//  DashboardView.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI

/// All UI in one place (`Layout.dashboard`): the card for the current moment,
/// with the control buttons in a row below it.
struct DashboardView: View {
    @Environment(AppModel.self) private var appModel
    let onAgain: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            card
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            if ![.idle, .locating, .placing, .ending].contains(appModel.phase) {
                ControlBar(onEnd: onFinish)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: appModel.phase)
        .animation(.easeInOut(duration: 0.45), value: appModel.awaitingSunDrag)
    }

    @ViewBuilder private var card: some View {
        if appModel.awaitingSunDrag {
            SunInstructionView()
        } else {
            switch appModel.phase {
            case .playing, .lightning:
                StormProgressView()
            case .afterStrike:
                AfterStrikeView(onAgain: onAgain, onFinish: onFinish)
            case .ending:
                EndingView()
            case .placing:
                PlacementView()
            case .locating:
                LocatingView()
            case .idle, .intro:
                EmptyView()
            }
        }
    }
}

/// Shown while the storm dissolves and the sun sets.
struct EndingView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sun.haze.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.multicolor)
            Text("Thank you!")
                .font(.largeTitle.bold())
            Text(appModel.stormsBuilt == 1
                 ? "You built 1 thunderstorm. Next time you see one, you'll know what's happening inside the cloud."
                 : "You built \(appModel.stormsBuilt) thunderstorms. Next time you see one, you'll know what's happening inside the cloud.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(36)
        .frame(width: 620)
        .glassBackgroundEffect()
    }
}

/// Shown once per room (or after "Place the model again"): line up the see-through
/// landscape with the real model, then save.
struct PlacementView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 44))
                .foregroundStyle(.cyan)
            Text("Place the model")
                .font(.title.bold())
            Text("Pinch the blue box and move it over the real model. Turn it with both hands – orange is the front. Line up the four yellow corners with the corners of the slices, then fine-tune with the arrows until the mountains match.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Fine steps: 3 mm / 0.5°.
            let step: Float = 0.003, turn: Float = .pi / 360
            HStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Move").font(.caption).foregroundStyle(.secondary)
                    Button { appModel.scene.nudgeModel(back: step) } label: { Label("Back", systemImage: "arrow.up") }
                    HStack(spacing: 8) {
                        Button { appModel.scene.nudgeModel(right: -step) } label: { Label("Left", systemImage: "arrow.left") }
                        Button { appModel.scene.nudgeModel(right: step) } label: { Label("Right", systemImage: "arrow.right") }
                    }
                    Button { appModel.scene.nudgeModel(back: -step) } label: { Label("Front", systemImage: "arrow.down") }
                }
                VStack(spacing: 8) {
                    Text("Height").font(.caption).foregroundStyle(.secondary)
                    Button { appModel.scene.nudgeModel(height: step) } label: { Label("Raise", systemImage: "chevron.up") }
                    Button { appModel.scene.nudgeModel(height: -step) } label: { Label("Lower", systemImage: "chevron.down") }
                }
                VStack(spacing: 8) {
                    Text("Turn").font(.caption).foregroundStyle(.secondary)
                    Button { appModel.scene.nudgeModel(yaw: turn) } label: { Label("Turn left", systemImage: "rotate.left") }
                    Button { appModel.scene.nudgeModel(yaw: -turn) } label: { Label("Turn right", systemImage: "rotate.right") }
                }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .controlSize(.large)

            Button {
                Task { await appModel.finishPlacement() }
            } label: {
                Label("Save position", systemImage: "checkmark")
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Saved once per room – the app finds the model again by itself.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 620)
        .glassBackgroundEffect()
    }
}

/// Short wait while visionOS recognises the room and the saved model position.
struct LocatingView: View {
    var body: some View {
        HStack(spacing: 16) {
            ProgressView()
            VStack(alignment: .leading, spacing: 4) {
                Text("Finding the model …")
                    .font(.title3)
                Text("Look at the landscape model for a moment.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .glassBackgroundEffect()
    }
}
