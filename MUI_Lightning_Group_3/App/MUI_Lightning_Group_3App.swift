//
//  MUI_Lightning_Group_3App.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI

@main
struct MUI_Lightning_Group_3App: App {
    @State private var appModel = AppModel()

    init() {
        ChargeComponent.registerComponent()
    }

    var body: some Scene {
        WindowGroup(id: AppModel.startWindowID) {
            StartView()
                .environment(appModel)
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: AppModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    appModel.stopExperience()
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
