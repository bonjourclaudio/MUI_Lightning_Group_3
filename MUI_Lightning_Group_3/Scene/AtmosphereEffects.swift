//
//  AtmosphereEffects.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import UIKit
import simd

enum Wind {
    /// From the lake (front left) towards the mountains (back right), model x/z.
    static let direction = simd_normalize(SIMD2<Float>(0.55, -0.75))
}

/// Sun (glow + real directional light on the landscape), warm-air haze rising from
/// heated ground, and wind streamlines flowing over the terrain.
@MainActor
final class AtmosphereEffects {
    let entity = Entity()

    private let sun = ModelEntity()
    private let sunLight = Entity()
    private var sunKey: SIMD4<Int32>?

    private var hazeBatch: SpriteBatch?
    private var haze: [Haze] = []
    private var hazeSprites: [Sprite] = []
    private var hazeKey: Int32 = -1

    private var wind: WindRibbons?

    private struct Haze {
        var spot: Int
        var t: Float
        var speed: Float
        var wobble: Float
        var visible: Bool
    }

    init() {
        sun.model = ModelComponent(mesh: .generatePlane(width: 0.26, height: 0.26),
                                   materials: [CloudAssets.sunMaterial(tint: [1, 0.9, 0.7], opacity: 0)])
        sun.components.set(BillboardComponent())
        sun.isEnabled = false
        entity.addChild(sun)

        sunLight.components.set(DirectionalLightComponent(color: .white, intensity: 0))
        entity.addChild(sunLight)

        let count = 36
        haze = (0..<count).map { i in
            Haze(spot: i % Terrain.hotSpots.count, t: Float.random(in: 0...1),
                 speed: Float.random(in: 0.12...0.2), wobble: Float.random(in: 0...6.28), visible: false)
        }
        hazeSprites = Array(repeating: Sprite(position: .zero, radius: 0, shade: 0.95, variant: 0, rotation: 0), count: count)
        if let batch = try? SpriteBatch(capacity: count,
                                        material: CloudAssets.cloudMaterial(tint: [1, 0.74, 0.5], opacity: 0),
                                        bounds: BoundingBox(min: [-0.7, -0.1, -0.6], max: [0.7, 0.8, 0.6])) {
            batch.entity.isEnabled = false
            entity.addChild(batch.entity)
            hazeBatch = batch
        }

        if let ribbons = try? WindRibbons() {
            entity.addChild(ribbons.entity)
            wind = ribbons
        }
    }

    /// `camera` in landscape-model space.
    func update(state: AtmosphereState, time: Float, dt: Float, camera: SIMD3<Float>) {
        updateSun(state)
        updateHaze(state, time: time, dt: dt, camera: camera)
        wind?.update(state: state, time: time, dt: dt, camera: camera)
    }

    // MARK: - Sun

    private func updateSun(_ s: AtmosphereState) {
        let angle = Float.pi * (1 - s.sunProgress)
        let altitude = sinf(angle)
        sun.position = [cosf(angle) * 0.85, 0.2 + altitude * 0.65, -0.55]
        let visibility = s.sunVisible * (1 - 0.92 * s.storm)
        sun.isEnabled = visibility > 0.01

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

    // MARK: - Warm air rising from the heated ground

    private func updateHaze(_ s: AtmosphereState, time: Float, dt: Float, camera: SIMD3<Float>) {
        guard let batch = hazeBatch else { return }
        let opacity = 0.3 * s.thermals * (1 - 0.6 * s.storm)
        let key = Int32(opacity * 200)
        if key != hazeKey {
            hazeKey = key
            batch.entity.model?.materials = [CloudAssets.cloudMaterial(tint: [1, 0.74, 0.5], opacity: opacity)]
        }
        batch.entity.isEnabled = opacity > 0.004
        guard batch.entity.isEnabled else { return }

        let active = Int((s.thermals * Float(haze.count)).rounded())
        let top = SceneController.cloudBase + SIMD3<Float>(0, 0.02, 0)
        for i in haze.indices {
            var h = haze[i]
            h.t += h.speed * dt
            if h.t >= 1 {
                h.t = 0
                h.spot = Int.random(in: 0..<Terrain.hotSpots.count)
                h.visible = i < active
            }
            let spot = Terrain.hotSpots[h.spot]
            let ground = SIMD3<Float>(spot.x, Terrain.height(spot.x, spot.y) + 0.015, spot.y)
            let ease = h.t * h.t
            var p = SIMD3<Float>(ground.x + (top.x - ground.x) * ease,
                                 ground.y + (top.y - ground.y) * h.t,
                                 ground.z + (top.z - ground.z) * ease)
            // Wandering, spiralling ascent.
            p.x += 0.018 * h.t * sinf(time * 1.1 + h.wobble)
            p.z += 0.018 * h.t * cosf(time * 0.9 + h.wobble)
            let envelope = sinf(Float.pi * h.t)
            hazeSprites[i] = Sprite(position: p,
                                    radius: h.visible ? (0.02 + 0.045 * h.t) * envelope : 0,
                                    shade: 0.95,
                                    variant: i % 4,
                                    rotation: h.wobble + time * 0.15)
            haze[i] = h
        }
        batch.update(hazeSprites, camera: camera)
    }
}
