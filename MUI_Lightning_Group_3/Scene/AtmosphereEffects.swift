//
//  AtmosphereEffects.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import UIKit
import simd

/// Marks the sun as draggable.
struct SunComponent: Component {}

enum Wind {
    /// From the low ground at the front (left) towards the mountains (back right), model x/z.
    static let direction = simd_normalize(SIMD2<Float>(0.55, -0.75))
}

/// Sun (3D body + aura + real directional light on the landscape), rising air shown as
/// temperature-coloured bubbles (blue = cold … red = hot), and wind streamlines (intro only).
@MainActor
final class AtmosphereEffects {
    let entity = Entity()

    private let sun = ModelEntity()          // soft aura (camera-facing glow), drag target
    private let sunBody = ModelEntity()      // 3D sphere in front of the aura
    private var sunBodyOpacity: Float = -1
    private let sunLight = Entity()
    private let track = Entity()
    private var sunKey: SIMD4<Int32>?

    private var air: AirParticles?
    private var wind: WindRibbons?

    init() {
        // Large, soft aura with faint rays – much wider than the body, so it reads as a sun.
        sun.model = ModelComponent(mesh: .generatePlane(width: Self.auraSize, height: Self.auraSize),
                                   materials: [CloudAssets.sunMaterial(tint: [1, 0.9, 0.7], opacity: 0)])
        sun.components.set(BillboardComponent())
        // Draggable along its path (no hover effect: it would highlight the square glow quad).
        sun.components.set(SunComponent())
        sun.components.set(InputTargetComponent())
        sun.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.07)]))
        sun.isEnabled = false
        entity.addChild(sun)

        // The sphere sits at the aura's centre: it hides the aura's flat bright core,
        // the soft glow stays visible around it.
        sunBody.model = ModelComponent(mesh: .generateSphere(radius: 0.032),
                                       materials: [CloudAssets.sunSurfaceMaterial()])
        // Slight tilt so the slow spin reads as a turning ball.
        sunBody.orientation = simd_quatf(angle: 0.35, axis: [1, 0, 0])
        sunBody.components.set(DynamicLightShadowComponent(castsShadow: false))
        sunBody.isEnabled = false
        entity.addChild(sunBody)

        sunLight.components.set(DirectionalLightComponent(color: .white, intensity: 0))
        // Mountains cast shadows that move with the sun.
        sunLight.components.set(DirectionalLightComponent.Shadow(maximumDistance: 2.5, depthBias: 2))
        entity.addChild(sunLight)

        buildTrack()

        let air = AirParticles()
        entity.addChild(air.entity)
        self.air = air

        if let ribbons = try? WindRibbons() {
            entity.addChild(ribbons.entity)
            wind = ribbons
        }
    }

    /// `camera` in landscape-model space.
    func update(state: AtmosphereState, time: Float, dt: Float, camera: SIMD3<Float>) {
        updateSun(state, time: time, dt: dt)
        air?.update(state: state, time: time, dt: dt)
        wind?.update(state: state, time: time, dt: dt, camera: camera)
    }

    // MARK: - Sun

    /// Sun position for a progress value 0 (sunrise, left) … 1 (sunset, right), model space.
    static func sunPosition(_ progress: Float) -> SIMD3<Float> {
        let angle = Float.pi * (1 - progress)
        return [cosf(angle) * 0.85, 0.2 + sinf(angle) * 0.65, -0.55]
    }

    /// Closest progress on the sun path for a point in model space.
    static func sunProgress(nearest p: SIMD3<Float>) -> Float {
        let angle = atan2f((p.y - 0.2) / 0.65, p.x / 0.85)
        let clamped = max(0.02 * .pi, min(0.98 * .pi, angle < -0.5 * .pi ? .pi : max(0, angle)))
        return 1 - clamped / .pi
    }

    /// 0 … 1: how strongly the sun heats the ground (its height above the horizon).
    static func heat(for progress: Float) -> Float {
        sinf(Float.pi * max(0, min(1, progress)))
    }

    /// Width of the aura quad around the sun (the body has a radius of 0.032 m).
    static let auraSize: Float = 0.85

    private(set) var sunPosition: SIMD3<Float> = .zero
    /// During the opening the sun can be dragged: path line visible, sun gently pulses.
    var sunInteractive = false
    private var trackFade: Float = 0

    /// Thin white line showing where the sun can be moved.
    private func buildTrack() {
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        material.writesDepth = false
        let mesh = MeshResource.generateCylinder(height: 1, radius: 1)
        let segments = 64
        for i in 0..<segments {
            let a = Self.sunPosition(0.02 + 0.96 * Float(i) / Float(segments))
            let b = Self.sunPosition(0.02 + 0.96 * Float(i + 1) / Float(segments))
            let length = simd_distance(a, b)
            var direction = (b - a) / length
            if direction.y < 0 { direction = -direction }
            let piece = ModelEntity(mesh: mesh, materials: [material])
            piece.position = (a + b) * 0.5
            piece.orientation = simd_quatf(from: [0, 1, 0], to: direction)
            piece.scale = [0.0012, length, 0.0012]
            track.addChild(piece)
        }
        track.isEnabled = false
        entity.addChild(track)
    }

    private func updateSun(_ s: AtmosphereState, time: Float, dt: Float) {
        let angle = Float.pi * (1 - s.sunProgress)
        let altitude = sinf(angle)
        sunPosition = Self.sunPosition(s.sunProgress)
        sun.position = sunPosition
        let visibility = s.sunVisible * (1 - 0.75 * s.storm)   // stays findable in the storm
        sun.isEnabled = s.sunVisible > 0.01
        trackFade += ((sunInteractive ? 1 : 0) - trackFade) * approachFactor(rate: 3, dt: dt)
        track.isEnabled = trackFade > 0.01
        if track.isEnabled { track.setOpacity(trackFade) }
        // Pulse invites the visitor to grab it.
        let pulse = 1 + 0.12 * trackFade * (0.5 + 0.5 * sinf(time * 3.5))
        sun.scale = .init(repeating: pulse)

        sunBody.isEnabled = sun.isEnabled
        sunBody.position = sunPosition
        sunBody.scale = .init(repeating: pulse)
        sunBody.orientation = simd_quatf(angle: 0.35, axis: [1, 0, 0]) * simd_quatf(angle: time * 0.12, axis: [0, 1, 0])
        let bodyOpacity = (visibility * 50).rounded() / 50
        if bodyOpacity != sunBodyOpacity {
            sunBodyOpacity = bodyOpacity
            sunBody.setOpacity(bodyOpacity)
        }
        if sun.components.has(InputTargetComponent.self) != sunInteractive {
            if sunInteractive {
                sun.components.set(InputTargetComponent())
            } else {
                sun.components.remove(InputTargetComponent.self)
            }
        }

        // Low sun is warm and orange, high sun is nearly white.
        let warmth = ramp(altitude, from: 0.15, to: 0.75)
        let tint = lerp3([1, 0.58, 0.3], [1, 0.95, 0.86], warmth)
        let key = SIMD4<Int32>(Int32(tint.y * 60), Int32(tint.z * 60), Int32(visibility * 60), Int32(altitude * 60))
        if key != sunKey {
            sunKey = key
            sun.model?.materials = [CloudAssets.sunMaterial(tint: tint, opacity: visibility)]
            if var light = sunLight.components[DirectionalLightComponent.self] {
                light.color = UIColor(red: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1)
                light.intensity = 2500 * visibility * (0.3 + 0.7 * altitude)
                sunLight.components.set(light)
            }
        }
        sunLight.look(at: .zero, from: sun.position, relativeTo: entity)
    }
}

/// Rising air as small translucent 3D bubbles, coloured by temperature
/// (standard scale: blue = cold … red = hot).
/// - From the sun-warmed land: start red (hot) and cool down while rising.
/// - From the lowlands at the front: cool, moist air (blue), carried by the wind towards the
///   mountains, then up.
@MainActor
final class AirParticles {
    let entity = Entity()

    private struct Bubble {
        let model: ModelEntity
        let moist: Bool
        var start: SIMD2<Float>
        var t: Float
        var speed: Float
        var wobble: Float
        var visible: Bool
        var bucket: Int
        var size: Float
    }

    private var bubbles: [Bubble] = []
    private var opacityKey = SIMD2<Int32>(-1, -1)

    /// Temperature scale, cold → hot.
    static let scale: [UIColor] = [
        UIColor(red: 0.20, green: 0.42, blue: 1.00, alpha: 1),   // cold blue
        UIColor(red: 0.38, green: 0.66, blue: 1.00, alpha: 1),
        UIColor(red: 0.66, green: 0.85, blue: 1.00, alpha: 1),   // cool
        UIColor(red: 0.96, green: 0.92, blue: 0.86, alpha: 1),   // neutral
        UIColor(red: 1.00, green: 0.72, blue: 0.45, alpha: 1),   // warm
        UIColor(red: 1.00, green: 0.48, blue: 0.26, alpha: 1),
        UIColor(red: 0.95, green: 0.20, blue: 0.14, alpha: 1),   // hot red
    ]
    private var materials: [[PhysicallyBasedMaterial]] = []   // [opacity step][temperature]
    private static let opacitySteps = 8

    init() {
        materials = (0...Self.opacitySteps).map { step in
            let opacity = 0.6 * Float(step) / Float(Self.opacitySteps)
            return Self.scale.map { Materials.bubble($0, opacity: opacity, glow: 0.35) }
        }
        let mesh = MeshResource.generateSphere(radius: 1)
        func add(moist: Bool) {
            let model = ModelEntity(mesh: mesh, materials: [materials[0][0]])
            model.isEnabled = false
            model.components.set(DynamicLightShadowComponent(castsShadow: false))
            entity.addChild(model)
            bubbles.append(Bubble(model: model, moist: moist, start: .zero,
                                  t: Float.random(in: 0...1), speed: Float.random(in: 0.09...0.15),
                                  wobble: Float.random(in: 0...6.28), visible: false, bucket: -1,
                                  size: Float.random(in: 0.006...0.011)))
        }
        for _ in 0..<30 { add(moist: false) }
        for _ in 0..<22 { add(moist: true) }
    }

    func update(state s: AtmosphereState, time: Float, dt: Float) {
        // Warm air: as long as the ground is warm (morning). Moist air: while the wind blows (intro).
        let landAmount = s.thermals * (1 - 0.6 * s.storm)
        let moistAmount = s.moistAir
        let landStep = Int((landAmount * Float(Self.opacitySteps)).rounded())
        let moistStep = Int((moistAmount * Float(Self.opacitySteps)).rounded())
        let key = SIMD2<Int32>(Int32(landStep), Int32(moistStep))
        let opacityChanged = key != opacityKey
        opacityKey = key
        entity.isEnabled = landStep > 0 || moistStep > 0 || bubbles.contains { $0.model.isEnabled }

        let landCount = bubbles.filter { !$0.moist }.count
        let moistCount = bubbles.count - landCount
        let landActive = Int((min(1, s.thermals) * Float(landCount)).rounded())
        let moistActive = Int((moistAmount * Float(moistCount)).rounded())
        let cloud = Layout.cloudBase
        var landIndex = 0, moistIndex = 0

        for i in bubbles.indices {
            var b = bubbles[i]
            let rank: Int
            if b.moist { rank = moistIndex; moistIndex += 1 } else { rank = landIndex; landIndex += 1 }
            b.t += b.speed * dt
            if b.t >= 1 || b.bucket < 0 {
                b.t = b.bucket < 0 ? b.t.truncatingRemainder(dividingBy: 1) : 0
                b.start = b.moist ? Self.randomLowlandPoint() : Terrain.hotSpots.randomElement()!
                b.visible = rank < (b.moist ? moistActive : landActive)
            }

            var p: SIMD3<Float>
            let temperature: Float
            if b.moist {
                // Across the land with the wind, over the slopes, then up into the cloud.
                let travel = ramp(b.t, from: 0, to: 0.75)
                let xz = b.start + (SIMD2<Float>(cloud.x, cloud.z) - b.start) * travel
                let ground = Terrain.height(xz.x, xz.y) + 0.02
                let rise = ramp(b.t, from: 0.45, to: 1)
                p = SIMD3<Float>(xz.x, ground + (cloud.y - ground) * rise, xz.y)
                temperature = 0.08 + 0.12 * (1 - b.t)          // cold → slightly colder
            } else {
                let ground = SIMD3<Float>(b.start.x, Terrain.height(b.start.x, b.start.y) + 0.015, b.start.y)
                let ease = b.t * b.t
                p = SIMD3<Float>(ground.x + (cloud.x - ground.x) * ease,
                                 ground.y + (cloud.y - ground.y) * b.t,
                                 ground.z + (cloud.z - ground.z) * ease)
                temperature = 1 - 0.85 * b.t                    // hot at the ground, cooling as it rises
            }
            p.x += 0.012 * b.t * sinf(time * 1.1 + b.wobble)
            p.z += 0.012 * b.t * cosf(time * 0.9 + b.wobble)

            let bucket = Int((temperature * Float(Self.scale.count - 1)).rounded())
            if bucket != b.bucket || opacityChanged {
                b.bucket = bucket
                let step = b.moist ? moistStep : landStep
                b.model.model?.materials = [materials[max(0, min(Self.opacitySteps, step))][bucket]]
            }
            let envelope = sinf(Float.pi * b.t)
            let size = b.visible ? b.size * (0.6 + 0.6 * b.t) * envelope : 0
            b.model.isEnabled = size > 0.0005 && (b.moist ? moistStep : landStep) > 0
            b.model.position = p
            b.model.scale = .init(repeating: max(size, 0.00001))
            bubbles[i] = b
        }
    }

    private static func randomLowlandPoint() -> SIMD2<Float> {
        let p = Terrain.lowlands.randomElement()!
        return p + SIMD2<Float>(Float.random(in: -0.03...0.03), Float.random(in: -0.02...0.02))
    }
}
