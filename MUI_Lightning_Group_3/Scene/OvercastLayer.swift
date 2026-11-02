//
//  OvercastLayer.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import simd

/// Grey cloud cover above and around the visitor that gathers as the storm approaches its
/// peak – the feeling of standing under a real thunderstorm sky.
///
/// Uses the same baked puff look as the main cloud. Split into 8 sectors around the viewer:
/// each sector is its own entity a few metres away, so RealityKit draws them *behind* the
/// main storm cloud (transparent objects are sorted by distance).
@MainActor
final class OvercastLayer {
    let entity = Entity()

    private struct Puff {
        let angle: Float
        let radius: Float
        let height: Float
        let size: Float
        let shade: Float
        /// 0…0.6 – when this puff appears (puffs gather one by one as the storm builds).
        let threshold: Float
        let variant: Int
        let seed: Float
    }

    private struct Sector {
        let batch: SpriteBatch
        let puffs: [Puff]
        var sprites: [Sprite]
    }

    private var sectors: [Sector] = []
    private var materialKey: SIMD4<Int32>?

    // Layout around the start position (metres, world space).
    private static let sectorCount = 8
    private static let puffsPerSector = 60
    private static let innerRadius: Float = 1.9
    private static let outerRadius: Float = 4.6
    private static let baseHeight: Float = 2.5

    init() {
        var rng = SeededRandom(seed: 2026)
        let span = 2 * Float.pi / Float(Self.sectorCount)
        for s in 0..<Self.sectorCount {
            var puffs: [Puff] = []
            var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            for _ in 0..<Self.puffsPerSector {
                let angle = (Float(s) + rng.next()) * span
                let r2 = Self.innerRadius * Self.innerRadius
                let radius = sqrtf(r2 + rng.next() * (Self.outerRadius * Self.outerRadius - r2))
                // A shallow dome: slightly lower towards the horizon.
                let height = Self.baseHeight + rng.range(0, 0.55) - (radius - Self.innerRadius) * 0.12
                let size = rng.range(0.35, 0.75)
                // Seen from below: the undersides are dark, thicker parts darker still.
                let shade = rng.range(0.42, 0.68)
                let puff = Puff(angle: angle, radius: radius, height: height, size: size, shade: shade,
                                threshold: rng.range(0, 0.6), variant: Int(rng.next() * 4), seed: rng.next())
                puffs.append(puff)
                let p = SIMD3<Float>(cosf(angle) * radius, height, sinf(angle) * radius)
                lo = simd_min(lo, p)
                hi = simd_max(hi, p)
            }
            let margin = SIMD3<Float>(repeating: 1.0)
            guard let batch = try? SpriteBatch(capacity: Self.puffsPerSector,
                                               material: CloudAssets.cloudMaterial(tint: [0.6, 0.62, 0.66], opacity: 0),
                                               bounds: BoundingBox(min: lo - margin, max: hi + margin)) else { continue }
            batch.perSpriteFacing = true
            entity.addChild(batch.entity)
            let empty = Sprite(position: .zero, radius: 0, shade: 0.5, variant: 0, rotation: 0)
            sectors.append(Sector(batch: batch, puffs: puffs,
                                  sprites: Array(repeating: empty, count: Self.puffsPerSector)))
        }
        entity.isEnabled = false
    }

    /// - Parameters:
    ///   - amount: 0…1 how much of the sky is covered
    ///   - storm: 0…1 storm intensity (darkens the cover)
    ///   - flash: 0…1 lightning (lights the cloud base from below)
    ///   - camera: viewer position, world space
    func update(amount: Float, storm: Float, flash: Float, time: Float, camera: SIMD3<Float>) {
        entity.isEnabled = amount > 0.005
        guard entity.isEnabled else { return }

        let base = 0.75 - 0.35 * storm
        var tint = SIMD3<Float>(base * 0.95, base * 0.97, base)
        tint = lerp3(tint, [0.88, 0.91, 1.0], min(1, flash))
        let opacity = min(1, amount * 1.3)
        let key = SIMD4<Int32>(Int32(tint.x * 80), Int32(tint.y * 80), Int32(tint.z * 80), Int32(opacity * 80))
        if key != materialKey {
            materialKey = key
            let material = CloudAssets.cloudMaterial(tint: tint, opacity: opacity)
            for sector in sectors { sector.batch.entity.model?.materials = [material] }
        }

        for s in sectors.indices {
            var sector = sectors[s]
            for (i, p) in sector.puffs.enumerated() {
                // Slow, bounded drift and boiling – no rotation, so sectors stay in place.
                let wobble = 0.03 * sinf(time * 0.07 + p.seed * 20)
                let angle = p.angle + wobble / max(p.radius, 1)
                let position = SIMD3<Float>(cosf(angle) * p.radius + wobble,
                                            p.height + 0.04 * sinf(time * 0.11 + p.seed * 13),
                                            sinf(angle) * p.radius)
                let grow = ramp(amount, from: p.threshold, to: p.threshold + 0.4)
                sector.sprites[i] = Sprite(position: position,
                                           radius: p.size * grow * (1 + 0.06 * sinf(time * 0.13 + p.seed * 9)),
                                           shade: p.shade,
                                           variant: p.variant,
                                           rotation: p.seed * 6.283 + time * 0.01)
            }
            sector.batch.update(sector.sprites, camera: camera)
            sectors[s] = sector
        }
    }
}
