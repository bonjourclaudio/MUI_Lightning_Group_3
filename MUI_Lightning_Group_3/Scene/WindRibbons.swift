//
//  WindRibbons.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import Metal
import RealityKit
import simd

/// Wind as thin, soft streamlines (like a weather visualisation): particles flow in a
/// wind field that follows the terrain, gets lifted on the slopes and sucked up under
/// the storm (updraft). Each particle leaves a fading ribbon trail.
@MainActor
final class WindRibbons {
    let entity = ModelEntity()

    private static let trailCount = 28
    private static let pointCount = 18

    private let mesh: LowLevelMesh
    private var trails: [Trail] = []
    private var opacityKey: Int32 = -1

    private struct Trail {
        var points: [SIMD3<Float>]
        var position: SIMD3<Float>
        var age: Float
        var life: Float
        var sampleTimer: Float
        var width: Float
        var pace: Float
    }

    private struct Vertex {
        var px: Float, py: Float, pz: Float
        var nx: Float, ny: Float, nz: Float
        var u: Float, v: Float
    }

    init() throws {
        let k = Self.pointCount
        let n = Self.trailCount
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: 0),
            .init(semantic: .normal, format: .float3, offset: MemoryLayout<Float>.stride * 3),
            .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Float>.stride * 6),
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
        descriptor.vertexCapacity = n * k * 2
        descriptor.indexCapacity = n * (k - 1) * 6
        descriptor.indexType = .uint32
        mesh = try LowLevelMesh(descriptor: descriptor)

        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            _ = raw.initializeMemory(as: UInt8.self, repeating: 0)
        }
        mesh.withUnsafeMutableIndices { raw in
            let indices = raw.bindMemory(to: UInt32.self)
            var w = 0
            for t in 0..<n {
                for j in 0..<(k - 1) {
                    let a0 = UInt32((t * k + j) * 2)
                    let b0 = a0 + 1, a1 = a0 + 2, b1 = a0 + 3
                    for index in [a0, a1, b1, a0, b1, b0] {
                        indices[w] = index
                        w += 1
                    }
                }
            }
        }
        mesh.parts.replaceAll([LowLevelMesh.Part(indexCount: n * (k - 1) * 6, topology: .triangle,
                                                 bounds: BoundingBox(min: [-0.8, -0.1, -0.8], max: [0.8, 1.0, 0.8]))])
        entity.model = ModelComponent(mesh: try MeshResource(from: mesh), materials: [CloudAssets.windMaterial(opacity: 0)])
        entity.isEnabled = false
        trails = (0..<n).map { _ in Self.spawn(randomStart: true) }
    }

    func update(state: AtmosphereState, time: Float, dt: Float, camera: SIMD3<Float>) {
        let opacity = 0.55 * state.wind
        entity.isEnabled = opacity > 0.01
        guard entity.isEnabled else { return }
        let key = Int32(opacity * 100)
        if key != opacityKey {
            opacityKey = key
            entity.model?.materials = [CloudAssets.windMaterial(opacity: opacity)]
        }

        let cloud = SceneController.cloudBase
        for i in trails.indices {
            var tr = trails[i]
            tr.age += dt
            tr.position += velocity(at: tr.position, wind: state.wind, time: time, pace: tr.pace) * dt
            tr.sampleTimer += dt
            if tr.sampleTimer > 0.06 {
                tr.sampleTimer = 0
                tr.points.removeFirst()
                tr.points.append(tr.position)
            } else {
                tr.points[tr.points.count - 1] = tr.position
            }
            let p = tr.position
            if tr.age > tr.life || p.y > cloud.y - 0.01 || abs(p.x) > 0.75 || abs(p.z) > 0.6 {
                tr = Self.spawn(randomStart: false)
            }
            trails[i] = tr
        }
        writeVertices(camera: camera)
    }

    // MARK: - Flow field

    private func velocity(at p: SIMD3<Float>, wind: Float, time: Float, pace: Float) -> SIMD3<Float> {
        let d = Wind.direction
        let speed = (0.05 + 0.13 * wind) * pace
        var v = SIMD3<Float>(d.x, 0, d.y) * speed

        // Follow the terrain, looking a little ahead so air rises before the slope.
        let ahead = SIMD2<Float>(p.x, p.z) + d * 0.05
        let ground = max(Terrain.height(p.x, p.z), Terrain.height(ahead.x, ahead.y))

        // Updraft under the storm: converge and rise.
        let cloud = SceneController.cloudBase
        let toCloud = SIMD2<Float>(cloud.x - p.x, cloud.z - p.z)
        let r = simd_length(toCloud)
        let pull = max(0, 1 - r / 0.28)

        v.y += (ground + 0.035 - p.y) * 2.0 * (1 - pull)
        v.y += speed * 1.6 * pull
        if r > 1e-3 {
            v.x += toCloud.x / r * speed * 0.5 * pull
            v.z += toCloud.y / r * speed * 0.5 * pull
        }

        // Gentle turbulence.
        v += SIMD3<Float>(sinf(p.z * 17 + time * 0.9),
                          0.4 * sinf(p.x * 13 + p.z * 7 + time * 1.1),
                          cosf(p.x * 15 + time * 0.8)) * (speed * 0.3)
        return v
    }

    private static func spawn(randomStart: Bool) -> Trail {
        let d = Wind.direction
        let perpendicular = SIMD2<Float>(-d.y, d.x)
        let along = randomStart ? Float.random(in: -0.55...0.2) : Float.random(in: -0.6 ... -0.45)
        let p2 = d * along + perpendicular * Float.random(in: -0.42...0.42)
        let p = SIMD3<Float>(p2.x, Terrain.height(p2.x, p2.y) + Float.random(in: 0.02...0.06), p2.y)
        return Trail(points: Array(repeating: p, count: pointCount), position: p, age: 0,
                     life: Float.random(in: 5...9), sampleTimer: 0,
                     width: Float.random(in: 0.003...0.007), pace: Float.random(in: 0.8...1.2))
    }

    // MARK: - Geometry

    private func writeVertices(camera: SIMD3<Float>) {
        let k = Self.pointCount
        let trails = self.trails
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: Vertex.self)
            for (t, tr) in trails.enumerated() {
                let envelope = min(1, tr.age / 0.8) * min(1, max(0, (tr.life - tr.age) / 1.2))
                for j in 0..<k {
                    let p = tr.points[j]
                    let tangent = tr.points[min(j + 1, k - 1)] - tr.points[max(j - 1, 0)]
                    let toCamera = camera - p
                    var side = simd_cross(tangent, toCamera)
                    let l = simd_length(side)
                    side = l > 1e-8 ? side / l * (tr.width * envelope) : .zero
                    let cl = simd_length(toCamera)
                    let n = cl > 1e-5 ? toCamera / cl : SIMD3<Float>(0, 0, 1)
                    let u = Float(j) / Float(k - 1)
                    let a = p - side, b = p + side
                    let index = (t * k + j) * 2
                    vertices[index] = Vertex(px: a.x, py: a.y, pz: a.z, nx: n.x, ny: n.y, nz: n.z, u: u, v: 0)
                    vertices[index + 1] = Vertex(px: b.x, py: b.y, pz: b.z, nx: n.x, ny: n.y, nz: n.z, u: u, v: 1)
                }
            }
        }
    }
}
