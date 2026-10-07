//
//  HeadLockedFollower.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import ARKit
import RealityKit
import QuartzCore
import simd

/// Keeps UI (stop button, play hint) at a fixed spot in the user's field of view,
/// following the head lazily so it doesn't feel glued to the face.
@MainActor
final class HeadLockedFollower {
    let entity = Entity()

    private struct Item {
        let entity: Entity
        let offset: SIMD3<Float>   // x right, y up, -z forward, relative to the head (yaw only)
    }

    private var items: [Item] = []
    private var session: ARKitSession?
    private var worldTracking: WorldTrackingProvider?
    /// World-space head position (fallback if tracking is unavailable).
    private(set) var headPosition: SIMD3<Float> = [0, 1.55, 0]
    private var headYaw: Float = 0
    private var hasPose = false

    func add(_ child: Entity, offset: SIMD3<Float>) {
        items.append(Item(entity: child, offset: offset))
        entity.addChild(child)
        layout()
    }

    func start() async {
        guard session == nil, WorldTrackingProvider.isSupported else { return }
        let session = ARKitSession()
        let provider = WorldTrackingProvider()
        self.session = session
        self.worldTracking = provider
        do {
            try await session.run([provider])
        } catch {
            print("[HeadLockedFollower] World tracking unavailable: \(error)")
        }
    }

    func stop() {
        session?.stop()
        session = nil
        worldTracking = nil
    }

    func update(dt: Float) {
        if let provider = worldTracking, provider.state == .running,
           let device = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
            let m = device.originFromAnchorTransform
            let position = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
            let forward = SIMD3<Float>(-m.columns.2.x, 0, -m.columns.2.z)

            if !hasPose { headPosition = position }
            headPosition += (position - headPosition) * approachFactor(rate: 10, dt: dt)

            if simd_length(forward) > 0.2 {
                let yaw = atan2f(-forward.x, -forward.z)
                var delta = yaw - headYaw
                while delta > .pi { delta -= 2 * .pi }
                while delta < -.pi { delta += 2 * .pi }
                headYaw += hasPose ? delta * approachFactor(rate: 3, dt: dt) : delta
            }
            hasPose = true
        }
        layout()
    }

    private func layout() {
        let yawRotation = simd_quatf(angle: headYaw, axis: [0, 1, 0])
        for item in items {
            item.entity.position = headPosition + yawRotation.act(item.offset)
            // Tilt panels below eye level back towards the eyes.
            let tilt = atan2f(item.offset.y, -item.offset.z)
            item.entity.orientation = yawRotation * simd_quatf(angle: tilt, axis: [1, 0, 0])
        }
    }
}
