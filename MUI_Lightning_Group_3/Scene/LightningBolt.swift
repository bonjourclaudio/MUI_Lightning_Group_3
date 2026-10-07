//
//  LightningBolt.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import UIKit
import simd

/// Procedural, branching lightning bolt made of thin glowing cylinders.
@MainActor
final class LightningBolt {
    let entity = Entity()

    private let segmentMesh = MeshResource.generateCylinder(height: 1, radius: 1)
    private let coreMaterial = Materials.unlit(UIColor(red: 0.94, green: 0.96, blue: 1, alpha: 1))
    private let glowMaterial = Materials.unlit(UIColor(red: 0.62, green: 0.72, blue: 1, alpha: 1), opacity: 0.35)
    private let impactMaterial = Materials.unlit(UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1), opacity: 0.6)

    init() {
        entity.isEnabled = false
    }

    func build(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        for child in Array(entity.children) { child.removeFromParent() }

        // Main channel: from inside the cloud down to the ground.
        let main = Self.jagged(from: start, to: end, iterations: 6, roughness: 0.2)
        addPolyline(main, width: 0.0032)

        // Downward branches, longer near the top.
        for _ in 0..<7 {
            let index = Int.random(in: (main.count / 8)..<(main.count * 3 / 4))
            let origin = main[index]
            let heightFactor = 1 - Float(index) / Float(main.count)
            let direction = simd_normalize(SIMD3<Float>(Float.random(in: -1...1),
                                                        -Float.random(in: 0.5...1.3),
                                                        Float.random(in: -1...1)))
            let branchEnd = origin + direction * Float.random(in: 0.06...0.16) * (0.6 + heightFactor)
            let branch = Self.jagged(from: origin, to: branchEnd, iterations: 4, roughness: 0.3)
            addPolyline(branch, width: 0.0015)
            // Some branches fork again.
            if Bool.random(), branch.count > 4 {
                let fork = branch[branch.count / 2]
                let forkEnd = fork + simd_normalize(SIMD3<Float>(Float.random(in: -1...1), -1, Float.random(in: -1...1))) * Float.random(in: 0.03...0.07)
                addPolyline(Self.jagged(from: fork, to: forkEnd, iterations: 3, roughness: 0.35), width: 0.0009)
            }
        }

        // Horizontal channels spreading through the cloud ("spider lightning").
        for _ in 0..<3 {
            let angle = Float.random(in: 0...(2 * .pi))
            let spread = SIMD3<Float>(cosf(angle), Float.random(in: -0.1...0.25), sinf(angle) * 0.6)
            let channelEnd = start + spread * Float.random(in: 0.1...0.2)
            addPolyline(Self.jagged(from: start, to: channelEnd, iterations: 4, roughness: 0.28), width: 0.0014)
        }

        let impact = ModelEntity(mesh: .generateSphere(radius: 0.03), materials: [impactMaterial])
        impact.position = end
        entity.addChild(impact)
    }

    /// Leader flicker + return strokes, then fade. `onFlash` receives 0…1 brightness.
    func play(onFlash: (Float) -> Void) async {
        entity.isEnabled = true
        // Several return strokes, like a real flash that flickers 3–5 times.
        let pattern: [(level: Float, ms: Int)] = [(1, 90), (0.15, 70), (1, 120), (0.25, 60), (1, 140),
                                                  (0.3, 80), (0.9, 110), (0.2, 60), (1, 260)]
        for step in pattern {
            entity.setOpacity(step.level)
            onFlash(step.level)
            try? await Task.sleep(for: .milliseconds(step.ms))
        }
        for k in 1...18 {
            let v = 1 - Float(k) / 18
            entity.setOpacity(v)
            onFlash(v * 0.5)
            try? await Task.sleep(for: .milliseconds(28))
        }
        entity.isEnabled = false
        onFlash(0)
    }

    // MARK: - Geometry

    private static func jagged(from a: SIMD3<Float>, to b: SIMD3<Float>, iterations: Int, roughness: Float) -> [SIMD3<Float>] {
        var points = [a, b]
        var amplitude = simd_distance(a, b) * roughness
        for _ in 0..<iterations {
            var next: [SIMD3<Float>] = []
            for i in 0..<(points.count - 1) {
                let p = points[i], q = points[i + 1]
                next.append(p)
                let offset = SIMD3<Float>(Float.random(in: -amplitude...amplitude),
                                          Float.random(in: -amplitude...amplitude) * 0.3,
                                          Float.random(in: -amplitude...amplitude))
                next.append((p + q) * 0.5 + offset)
            }
            next.append(points[points.count - 1])
            points = next
            amplitude *= 0.55
        }
        return points
    }

    private func addPolyline(_ points: [SIMD3<Float>], width: Float) {
        for i in 0..<(points.count - 1) {
            let p = points[i], q = points[i + 1]
            let length = simd_distance(p, q)
            guard length > 0.0001 else { continue }
            var direction = (q - p) / length
            if direction.y < 0 { direction = -direction }   // avoid the antiparallel quaternion case
            let rotation = simd_quatf(from: [0, 1, 0], to: direction)
            let middle = (p + q) * 0.5

            let core = ModelEntity(mesh: segmentMesh, materials: [coreMaterial])
            core.position = middle
            core.orientation = rotation
            core.scale = [width, length * 1.02, width]
            entity.addChild(core)

            let glow = ModelEntity(mesh: segmentMesh, materials: [glowMaterial])
            glow.position = middle
            glow.orientation = rotation
            glow.scale = [width * 4.5, length, width * 4.5]
            entity.addChild(glow)
        }
    }
}
