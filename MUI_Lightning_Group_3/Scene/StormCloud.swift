//
//  StormCloud.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import UIKit
import simd

/// The main cloud, built from the Blender models:
/// condenses as the start cloud, then morphs sprite-by-sprite into the grey anvil (end cloud).
/// Charge carriers inside, rain and mist below, flashes light it up from inside.
@MainActor
final class StormCloud {
    let entity = Entity()

    private let body = Entity()     // scales slightly with storm intensity
    private let core = Entity()     // ice crystals, graupel, droplets
    private let mist = Entity()
    private var rain: RainStreaks?
    private var batch: SpriteBatch?
    private var sprites: [Sprite]
    private let morphSprites: [MorphSprite]
    private let startBox: CloudBox
    private let endBox: CloudBox

    /// Current bounds of the cloud in `body` space.
    private(set) var box: CloudBox
    /// 0 = start cloud, 1 = anvil.
    private(set) var morph: Float = 0
    private(set) var bodyScale: Float = 1

    private struct CoreParticle {
        enum Kind { case positive, negative, droplet }
        let model: ModelEntity
        let kind: Kind
        let index: Int
        let seed: SIMD4<Float>
        var visibility: Float = 0
    }

    private var particles: [CoreParticle] = []
    private var shownPositive = 0
    private var shownNegative = 0
    private var particlesColored = false
    private var glowLevel: Float = 0
    private var flashTime: Float = 0
    private var highlight: Float = 0
    private var highlightTarget: Float = 0
    private var materialKey: SIMD4<Int32>?
    private var rainSources: [SIMD3<Float>] = []
    private var mistTimer: Float = 1
    private var lastMistRate: Float = -1
    private var lastWind = SIMD2<Float>(repeating: 99)

    private let dropletMaterial = Materials.unlit(UIColor(red: 0.62, green: 0.82, blue: 1, alpha: 1))
    private let iceMaterial = Materials.unlit(UIColor(white: 0.98, alpha: 1))
    private let graupelMaterial = Materials.unlit(UIColor(white: 0.8, alpha: 1))
    private let positiveMaterial = Materials.unlit(UIColor(red: 1, green: 0.32, blue: 0.22, alpha: 1))
    private let negativeMaterial = Materials.unlit(UIColor(red: 0.22, green: 0.5, blue: 1, alpha: 1))

    init() {
        let data = CloudAssets.morph
        morphSprites = data?.sprites ?? []
        startBox = data?.startBox ?? CloudBox(min: [-0.12, -0.02, -0.09], max: [0.12, 0.19, 0.09])
        endBox = data?.endBox ?? CloudBox(min: [-0.41, -0.08, -0.16], max: [0.25, 0.47, 0.22])
        box = startBox
        sprites = Array(repeating: Sprite(position: .zero, radius: 0, shade: 1, variant: 0, rotation: 0),
                        count: morphSprites.count)

        entity.addChild(body)
        body.addChild(core)
        entity.addChild(mist)
        do {
            let rain = try RainStreaks()
            entity.addChild(rain.entity)
            self.rain = rain
        } catch {
            print("[StormCloud] Rain mesh failed: \(error)")
        }

        if !morphSprites.isEmpty {
            let lo = simd_min(startBox.min, endBox.min) - 0.15
            let hi = simd_max(startBox.max, endBox.max) + 0.15
            do {
                let batch = try SpriteBatch(capacity: morphSprites.count,
                                            material: CloudAssets.cloudMaterial(tint: [1, 1, 1], opacity: 1),
                                            bounds: BoundingBox(min: lo, max: hi))
                body.addChild(batch.entity)
                self.batch = batch
            } catch {
                print("[StormCloud] Sprite mesh failed: \(error)")
            }
        }

        buildParticles()
        mist.components.set(Self.makeMistEmitter())
    }

    // MARK: - Public

    /// World-space point used for drag & drop (middle of the tower).
    var centerWorld: SIMD3<Float> {
        body.convert(position: [box.center.x, box.min.y + box.size.y * 0.4, box.center.z], to: nil)
    }

    var captureRadius: Float {
        max(0.12, min(box.size.x, box.size.y) * 0.45) * bodyScale
    }

    /// Where lightning leaves the cloud, in the parent's (landscape model) space.
    var strikeOrigin: SIMD3<Float> {
        body.convert(position: [box.center.x, box.min.y + box.size.y * 0.4, box.center.z], to: entity.parent)
    }

    func setChargeCounts(positive: Int, negative: Int) {
        shownPositive = min(positive, 24)
        shownNegative = min(negative, 24)
    }

    func setHighlighted(_ on: Bool) { highlightTarget = on ? 1 : 0 }
    func flash(duration: Float) { flashTime = duration }
    func setGlow(_ level: Float) { glowLevel = level }

    func update(state: AtmosphereState, time: Float, dt: Float, camera: SIMD3<Float>) {
        highlight += (highlightTarget - highlight) * approachFactor(rate: 8, dt: dt)
        bodyScale = 0.95 + 0.12 * state.storm
        let pulse = 1 + 0.05 * highlight * (0.5 + 0.5 * sinf(time * 8))
        body.scale = .init(repeating: bodyScale * pulse)

        let condense = ramp(state.cloudGrowth, from: 0, to: 0.35)
        let grow = max(0, min(1, (state.cloudGrowth - 0.35) / 0.65))
        morph = min(1, 0.85 * grow + 0.15 * state.anvil)
        box = CloudBox.lerp(startBox, endBox, morph)

        // White when it forms, greyer only as the storm builds (and a little as it towers up).
        let grey = max(state.storm, 0.3 * morph * morph)
        updateSprites(condense: condense, grey: grey, time: time, camera: camera)
        updateMaterial(state, dt: dt)
        updateParticles(state, time: time, dt: dt)
        updateRain(state, time: time, dt: dt, camera: camera)
    }

    // MARK: - Morph

    private func updateSprites(condense: Float, grey: Float, time: Float, camera: SIMD3<Float>) {
        let lift = 0.5 * (1 - grey)        // brightens shadows of a young cloud
        let dim = 1 - 0.3 * grey
        func shade(_ baked: Float) -> Float { (baked + (1 - baked) * lift) * dim }
        guard let batch else { return }
        for i in morphSprites.indices {
            let d = morphSprites[i]
            let s = d.seed * 40
            // Condensation: puffs appear one after another and drift up slightly.
            let appear = ramp(condense, from: d.seed * 0.6, to: d.seed * 0.6 + 0.4)
            // Growth: rise first (tower), spread sideways later (anvil).
            let t = ramp(morph, from: d.delay, to: d.delay + 0.5)
            let ty = ramp(t, from: 0, to: 0.75)
            let txz = ramp(t, from: 0.35, to: 1)
            var p = SIMD3<Float>(d.start.x + (d.end.x - d.start.x) * txz,
                                 d.start.y + (d.end.y - d.start.y) * ty,
                                 d.start.z + (d.end.z - d.start.z) * txz)
            let billow = t * (1 - t) * 4
            p += SIMD3<Float>(sinf(s + t * 6), 0, cosf(s * 0.77 + t * 5)) * (0.02 * billow)
            p += SIMD3<Float>(sinf(time * 0.23 + s), 0.5 * sinf(time * 0.17 + s * 0.6), cosf(time * 0.19 + s * 0.8)) * 0.003
            p.y -= (1 - appear) * 0.03

            let radius = (d.startRadius + (d.endRadius - d.startRadius) * t)
                * appear * (1 + 0.2 * billow) * (1 + 0.04 * sinf(time * 0.5 + s))
            sprites[i] = Sprite(position: p,
                                radius: radius,
                                shade: shade(d.startShade + (d.endShade - d.startShade) * t),
                                variant: Int(d.seed * 997) % 4,
                                rotation: d.seed * 6.283 + time * 0.04 * (d.seed - 0.5))
        }
        batch.update(sprites, camera: body.convert(position: camera, from: nil))
    }

    private func updateMaterial(_ state: AtmosphereState, dt: Float) {
        // Random flashes inside the cloud once the storm is strong.
        if state.storm > 0.65, Float.random(in: 0...1) < dt * (state.storm - 0.6) * 1.6 {
            flashTime = Float.random(in: 0.05...0.15)
        }
        var flash = glowLevel
        if flashTime > 0 {
            flashTime -= dt
            flash = max(flash, Float.random(in: 0.5...1))
        }
        let base = 1 - 0.45 * state.storm
        var tint = SIMD3<Float>(base * (1 - 0.06 * state.storm), base * (1 - 0.03 * state.storm), base)
        tint = lerp3(tint, [0.9, 0.93, 1.0], min(1, flash))
        let opacity = 1 - 0.55 * state.xray
        let key = SIMD4<Int32>(Int32(tint.x * 100), Int32(tint.y * 100), Int32(tint.z * 100), Int32(opacity * 100))
        if key != materialKey {
            materialKey = key
            batch?.entity.model?.materials = [CloudAssets.cloudMaterial(tint: tint, opacity: opacity)]
        }
    }

    // MARK: - Inside the cloud

    private func buildParticles() {
        var rng = SeededRandom(seed: 99)
        let mesh = MeshResource.generateSphere(radius: 1)
        func add(_ kind: CoreParticle.Kind, _ index: Int) {
            let model = ModelEntity(mesh: mesh, materials: [material(for: kind, colored: false)])
            model.isEnabled = false
            core.addChild(model)
            let seed = SIMD4<Float>(rng.next(), rng.next(), rng.next(), rng.next())
            particles.append(CoreParticle(model: model, kind: kind, index: index, seed: seed))
        }
        for i in 0..<24 { add(.positive, i) }   // small ice crystals
        for i in 0..<24 { add(.negative, i) }   // graupel / hail
        for i in 0..<20 { add(.droplet, i) }    // supercooled droplets
    }

    private func material(for kind: CoreParticle.Kind, colored: Bool) -> UnlitMaterial {
        switch kind {
        case .positive: return colored ? positiveMaterial : iceMaterial
        case .negative: return colored ? negativeMaterial : graupelMaterial
        case .droplet: return dropletMaterial
        }
    }

    private func updateParticles(_ state: AtmosphereState, time: Float, dt: Float) {
        let colored = state.separation > 0.25
        if colored != particlesColored {
            particlesColored = colored
            for p in particles { p.model.model?.materials = [material(for: p.kind, colored: colored)] }
        }

        // Positions are relative to the current cloud bounds, so they follow the morph.
        let b = box
        let size = b.size
        let tower = SIMD2<Float>(min(size.x, startBox.size.x * 1.2), min(size.z, startBox.size.z * 1.2))
        let k = approachFactor(rate: 4, dt: dt)

        for i in particles.indices {
            var p = particles[i]
            let shown: Bool
            switch p.kind {
            case .positive: shown = p.index < shownPositive
            case .negative: shown = p.index < shownNegative
            case .droplet: shown = true
            }
            p.visibility += ((shown ? 1 : 0) - p.visibility) * k

            let s = p.seed
            let phase = time * (0.5 + s.x * 0.6) + s.y * 6.283
            let angle = s.w * 6.283 + time * 0.35
            let radius = 0.15 + 0.25 * s.z
            let mixed = SIMD3<Float>(b.center.x + cosf(angle) * radius * tower.x,
                                     b.min.y + size.y * (0.4 + 0.22 * sinf(phase)),
                                     b.center.z + sinf(angle) * radius * tower.y)
            var position = mixed
            switch p.kind {
            case .positive:   // light ice crystals → top / anvil
                let separated = SIMD3<Float>(b.center.x + (s.x - 0.5) * size.x * 0.6 + 0.004 * sinf(time + s.y * 6),
                                             b.min.y + size.y * (0.76 + 0.12 * s.y),
                                             b.center.z + (s.z - 0.5) * size.z * 0.4)
                position = lerp3(mixed, separated, state.separation)
            case .negative:   // heavy graupel → middle / lower part
                let separated = SIMD3<Float>(b.center.x + (s.x - 0.5) * tower.x * 0.6,
                                             b.min.y + size.y * (0.3 + 0.15 * s.y) + 0.004 * sinf(time * 1.3 + s.z * 6),
                                             b.center.z + (s.z - 0.5) * tower.y * 0.5)
                position = lerp3(mixed, separated, state.separation)
            case .droplet:
                break
            }

            let particleSize: Float = p.kind == .negative ? 0.009 : (p.kind == .positive ? 0.007 : 0.0045)
            let v = p.visibility * state.interior
            p.model.isEnabled = v > 0.01
            p.model.position = position
            p.model.scale = .init(repeating: max(particleSize * v, 0.00001))
            particles[i] = p
        }
    }

    // MARK: - Rain & mist (driven by the wind)

    /// Soft grey veil under the cloud (rain shaft), slower and more wind-blown.
    private static func makeMistEmitter() -> ParticleEmitterComponent {
        var e = ParticleEmitterComponent()
        e.emitterShape = .sphere
        e.emitterShapeSize = [0.08, 0.015, 0.06]
        e.birthLocation = .volume
        e.birthDirection = .world
        e.emissionDirection = [0, -1, 0]
        e.speed = 0.3
        e.speedVariation = 0.1
        e.mainEmitter.birthRate = 0
        e.mainEmitter.lifeSpan = 1.0
        e.mainEmitter.lifeSpanVariation = 0.3
        e.mainEmitter.size = 0.03
        e.mainEmitter.sizeMultiplierAtEndOfLifespan = 2.2
        e.mainEmitter.acceleration = [0, -0.25, 0]
        e.mainEmitter.color = .constant(.single(UIColor(white: 0.75, alpha: 0.06)))
        e.mainEmitter.blendMode = .alpha
        e.mainEmitter.noiseScale = 1.5
        e.mainEmitter.noiseAnimationSpeed = 0.6
        e.mainEmitter.noiseStrength = 0.1
        e.isEmitting = false
        return e
    }

    /// Points on the underside of the cloud (entity space) – rain falls from the real cloud base,
    /// not from a rectangle.
    private func collectRainSources() {
        rainSources.removeAll(keepingCapacity: true)
        let limit = box.min.y + box.size.y * 0.22
        let scale = body.scale.x
        for s in sprites where s.radius > 0.004 && s.position.y < limit {
            rainSources.append(SIMD3<Float>(s.position.x, s.position.y - s.radius * 0.4, s.position.z) * scale)
        }
        if rainSources.isEmpty {
            rainSources.append(SIMD3<Float>(box.center.x, box.min.y, box.center.z) * scale)
        }
    }

    private func updateRain(_ state: AtmosphereState, time: Float, dt: Float, camera: SIMD3<Float>) {
        let rate = min(1, state.storm + state.rainPulse * 0.8)
        let gust = 0.75 + 0.25 * sinf(time * 1.3) + 0.15 * sinf(time * 3.7 + 1)
        let strength = state.wind * gust * (0.4 + 0.6 * rate)
        let wind = Wind.direction * (strength * 0.9)

        collectRainSources()
        rain?.update(rate: rate, wind: wind, time: time, dt: dt, sources: rainSources,
                     groundOffset: entity.position, camera: entity.convert(position: camera, from: nil))

        // Mist: soft ellipsoid under the cloud base (no box), centred on the rain sources.
        var centre = SIMD3<Float>.zero
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in rainSources {
            centre += p
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        centre /= Float(rainSources.count)
        mist.position = centre - SIMD3<Float>(0, 0.03, 0)

        mistTimer += dt
        guard mistTimer > 0.25 else { return }
        mistTimer = 0
        guard abs(rate - lastMistRate) > 0.02 || simd_distance(wind, lastWind) > 0.05 else { return }
        lastMistRate = rate
        lastWind = wind
        let extent = simd_max(hi - lo, SIMD3<Float>(repeating: 0.06))
        if var e = mist.components[ParticleEmitterComponent.self] {
            e.emitterShapeSize = [extent.x * 0.4, 0.015, extent.z * 0.4]
            e.emissionDirection = simd_normalize(SIMD3<Float>(wind.x * 1.5, -1, wind.y * 1.5))
            e.mainEmitter.acceleration = [wind.x * 0.8, -0.25, wind.y * 0.8]
            e.mainEmitter.birthRate = (rate * 70).rounded()
            e.isEmitting = rate > 0.05
            mist.components.set(e)
        }
    }
}
