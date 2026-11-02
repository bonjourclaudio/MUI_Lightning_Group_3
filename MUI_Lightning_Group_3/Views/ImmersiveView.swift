//
//  ImmersiveView.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI
import Spatial
import RealityKit

enum AttachmentID {
    static let dashboard = "dashboard"
}

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @State private var updateSubscription: EventSubscription?

    var body: some View {
        RealityView { content, attachments in
            let scene = appModel.scene
            scene.build(showVirtualLandscape: appModel.showVirtualLandscape)
            content.add(scene.root)

            if let dashboard = attachments.entity(for: AttachmentID.dashboard) {
                scene.attachDashboard(dashboard)
            }
            for slot in 0..<ChargedCloudField.slotCount {
                if let badge = attachments.entity(for: "charge-\(slot)") {
                    scene.attachBadge(slot: slot, badge)
                }
            }
            for label in InfoLabel.allCases {
                if let view = attachments.entity(for: label.id) {
                    scene.attachLabel(label, view: view)
                }
            }

            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                MainActor.assumeIsolated {
                    scene.update(dt: Float(event.deltaTime))
                }
            }

        } attachments: {
            Attachment(id: AttachmentID.dashboard) {
                DashboardView(onAgain: { appModel.director.buildAnother() }, onFinish: finish)
                    .environment(appModel)
            }
            ForEach(0..<ChargedCloudField.slotCount, id: \.self) { slot in
                Attachment(id: "charge-\(slot)") {
                    ChargeBadgeView(slot: slot).environment(appModel)
                }
            }
            ForEach(InfoLabel.allCases) { label in
                Attachment(id: label.id) {
                    InfoLabelView(label: label)
                }
            }
        }
        // One drag gesture for everything draggable (sun and charged clouds),
        // tap recognised alongside it for the charged clouds.
        .gesture(dragGesture)
        .simultaneousGesture(tapGesture)
        .simultaneousGesture(rotateGesture)
        .task {
            await appModel.beginSession()
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .targetedToAnyEntity()
            .onChanged { value in
                let location = value.convert(value.location3D, from: .local, to: .scene)
                if value.entity.components.has(PlacementComponent.self) {
                    let start = value.convert(value.startLocation3D, from: .local, to: .scene)
                    appModel.scene.dragModel(to: location, start: start)
                } else if value.entity.components.has(SunComponent.self) {
                    appModel.scene.dragSun(to: location)
                } else {
                    let start = value.convert(value.startLocation3D, from: .local, to: .scene)
                    appModel.scene.charged?.drag(value.entity, to: location, start: start)
                }
            }
            .onEnded { value in
                if value.entity.components.has(PlacementComponent.self) {
                    appModel.scene.endModelDrag()
                } else if value.entity.components.has(SunComponent.self) {
                    appModel.scene.endSunDrag()
                } else {
                    appModel.scene.charged?.endDrag(value.entity)
                }
            }
    }

    /// Placing the model: turn the see-through landscape with both hands (around the vertical).
    private var rotateGesture: some Gesture {
        RotateGesture3D(constrainedToAxis: .y)
            .targetedToEntity(where: .has(PlacementComponent.self))
            .onChanged { value in
                let q = value.rotation.quaternion
                let yaw = 2 * atan2(Float(q.imag.y), Float(q.real))
                appModel.scene.rotateModel(by: yaw)
            }
            .onEnded { _ in
                appModel.scene.endModelRotate()
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

    private func end() {
        guard appModel.immersiveSpaceState == .open else { return }
        appModel.immersiveSpaceState = .inTransition
        Task { @MainActor in
            appModel.stopExperience()
            openWindow(id: AppModel.startWindowID)
            await dismissImmersiveSpace()
        }
    }

    /// "Finish" (after a storm) and "End" (while paused): a calm ending, then close.
    private func finish() {
        guard appModel.phase != .ending else { return }
        appModel.resume()
        Task { @MainActor in
            await appModel.director.playEnding()
            end()
        }
    }
}
