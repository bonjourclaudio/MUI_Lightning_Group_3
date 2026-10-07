//
//  StartView.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI

struct StartView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var model = appModel

        VStack(spacing: 28) {
            Image(systemName: "cloud.bolt.rain.fill")
                .font(.system(size: 72))
                .symbolRenderingMode(.multicolor)

            VStack(spacing: 10) {
                Text("How does lightning form?")
                    .font(.extraLargeTitle2)
                Text("Watch a thunderstorm grow above the landscape – then take control and charge it up until lightning strikes.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show virtual landscape (simulator, or without the physical model)", isOn: $model.showVirtualLandscape)
            }
            .frame(width: 540)

            Button {
                Task { await start() }
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.title2)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(appModel.immersiveSpaceState != .closed)
        }
        .padding(56)
        .frame(width: 760)
    }

    private func start() async {
        appModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: AppModel.immersiveSpaceID) {
        case .opened:
            dismissWindow(id: AppModel.startWindowID)
        case .userCancelled, .error:
            appModel.immersiveSpaceState = .closed
        @unknown default:
            appModel.immersiveSpaceState = .closed
        }
    }
}
