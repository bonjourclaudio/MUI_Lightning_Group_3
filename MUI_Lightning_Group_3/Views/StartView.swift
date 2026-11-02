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

            Text("How do you want to start?")
                .font(.title2.weight(.semibold))
                .padding(.top, 8)

            HStack(spacing: 20) {
                choice(title: "With the physical model",
                       detail: "The landscape stands on the table in front of you.",
                       symbol: "cube.fill", virtual: false)
                choice(title: "Virtual landscape",
                       detail: "No model? The landscape is shown in the room.",
                       symbol: "mountain.2.fill", virtual: true)
            }

            if HeadLockedFollower.hasSavedModel {
                Button {
                    appModel.forcePlacement = true
                    appModel.showVirtualLandscape = false
                    Task { await start() }
                } label: {
                    Label("Model moved? Place it again", systemImage: "scope")
                }
                .buttonStyle(.borderless)
                .disabled(appModel.immersiveSpaceState != .closed)
            }
        }
        .padding(56)
        .frame(width: 760)
    }

    private func choice(title: String, detail: String, symbol: String, virtual: Bool) -> some View {
        Button {
            appModel.showVirtualLandscape = virtual
            Task { await start() }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 250, height: 190)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 24))
        .disabled(appModel.immersiveSpaceState != .closed)
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
