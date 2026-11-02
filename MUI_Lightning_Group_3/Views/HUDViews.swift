//
//  HUDViews.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI

/// Row under the dashboard card: next step / skip intro, pause. When paused: resume, restart, end.
struct ControlBar: View {
    @Environment(AppModel.self) private var appModel
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if appModel.isPaused {
                Button { appModel.resume() } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                Button { appModel.restartExperience() } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
                Button(action: onEnd) {
                    Label("End", systemImage: "xmark")
                }
            } else {
                if appModel.phase == .intro {
                    Button { appModel.requestNextStep() } label: {
                        Label("Next step", systemImage: "forward.fill")
                    }
                    Button { appModel.director.skipIntro() } label: {
                        Label("Skip intro", systemImage: "forward.end.fill")
                    }
                }
                Button { appModel.pause() } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
            }
        }
        .font(.title3)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .padding(8)
        .glassBackgroundEffect(in: Capsule())
        .animation(.easeInOut(duration: 0.25), value: appModel.isPaused)
        .animation(.easeInOut(duration: 0.25), value: appModel.phase)
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
