//
//  ImmersiveView.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI
import RealityKit

enum AttachmentID {
    static let stop = "stop"
    static let hint = "hint"
    static let infographic = "infographic"
    static let afterStrike = "afterStrike"
}

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @State private var updateSubscription: EventSubscription?

    var body: some View {
        let phase = appModel.phase
        let focus = appModel.infographic

        RealityView { content, attachments in
            let scene = appModel.scene
            scene.build(showVirtualLandscape: appModel.showVirtualLandscape)
            content.add(scene.root)

            if let stop = attachments.entity(for: AttachmentID.stop),
               let hint = attachments.entity(for: AttachmentID.hint) {
                scene.attachHeadLocked(stop: stop, hint: hint)
            }
            if let info = attachments.entity(for: AttachmentID.infographic) {
                scene.attachInfographic(info)
            }
            if let after = attachments.entity(for: AttachmentID.afterStrike) {
                scene.attachAfterStrike(after)
            }

            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                MainActor.assumeIsolated {
                    scene.update(dt: Float(event.deltaTime))
                }
            }

            appModel.startExperience()
        } update: { _, _ in
            appModel.scene.setUI(infographicVisible: focus != .hidden,
                                 afterStrikeVisible: phase == .afterStrike)
        } attachments: {
            Attachment(id: AttachmentID.stop) {
                StopButtonView(onStop: stop)
            }
            Attachment(id: AttachmentID.hint) {
                HintView().environment(appModel)
            }
            Attachment(id: AttachmentID.infographic) {
                InfographicView().environment(appModel)
            }
            Attachment(id: AttachmentID.afterStrike) {
                AfterStrikeView(onAgain: { appModel.director.buildAnother() }, onFinish: finish)
                    .environment(appModel)
            }
        }
        // Drag is the primary interaction; tap is recognised alongside it
        // (a real drag never counts as a tap, a tap never starts a drag).
        .gesture(dragGesture)
        .simultaneousGesture(tapGesture)
        .task {
            await appModel.scene.head.start()
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .targetedToEntity(where: .has(ChargeComponent.self))
            .onChanged { value in
                let location = value.convert(value.location3D, from: .local, to: .scene)
                let start = value.convert(value.startLocation3D, from: .local, to: .scene)
                appModel.scene.charged?.drag(value.entity, to: location, start: start)
            }
            .onEnded { value in
                appModel.scene.charged?.endDrag(value.entity)
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(where: .has(ChargeComponent.self))
            .onEnded { value in
                appModel.scene.charged?.sendToStorm(value.entity)
            }
    }

    // MARK: - Exit

    private func stop() {
        guard appModel.immersiveSpaceState == .open else { return }
        appModel.immersiveSpaceState = .inTransition
        Task { @MainActor in
            appModel.stopExperience()
            openWindow(id: AppModel.startWindowID)
            await dismissImmersiveSpace()
        }
    }

    private func finish() {
        Task { @MainActor in
            stop()
        }
    }
}
