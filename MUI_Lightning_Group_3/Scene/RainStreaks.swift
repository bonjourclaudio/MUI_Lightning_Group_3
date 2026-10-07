//
//  RainStreaks.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import Metal
import RealityKit
import simd

/// Rain as long, thin, motion-blurred drops (like real rain seen with your eyes),
/// each aligned to its own velocity so gusts visibly slant the rain.
/// All positions are in the space of the entity this is attached to.
@MainActor
final class RainStreaks {
    let entity = ModelEntity()

    private static let capacity = 900
    private let mesh: LowLevelMesh
    private var drops: [Drop]
    private var opacityKey: Int32 = -1

    private struct Drop {
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var length: Float
        var width: Float
        var phase: Float
        var active: Bool
    }

    private struct Vertex {
        var px: Float, py: Float, pz: Float
        var nx: Float, ny: Float, nz: Float
        var u: Float, v: Float
    }

    init() throws {
        let n = Self.capacity
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: 0),
            .init(semantic: .normal, format: .float3, offset: MemoryLayout<Float>.stride * 3),
            .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Float>.stride * 6),
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
        descriptor.vertexCapacity = n * 4
        descriptor.indexCapacity = n * 6
        descriptor.indexType = .uint32
        mesh = try LowLevelMesh(descriptor: descriptor)

        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            _ = raw.initializeMemory(as: UInt8.self, repeating: 0)
        }
        mesh.withUnsafeMutableIndices { raw in
            let indices = raw.bindMemory(to: UInt32.self)
            for i in 0..<n {
                let b = UInt32(i * 4), k = i * 6
                indices[k] = b; indices[k + 1] = b + 1; indices[k + 2] = b + 2
                indices[k + 3] = b; indices[k + 4] = b + 2; indices[k + 5] = b + 3
            }
        }
        mesh.parts.replaceAll([LowLevelMesh.Part(indexCount: n * 6, topology: .triangle,
                                                 bounds: BoundingBox(min: [-0.8, -0.7, -0.8], max: [0.8, 0.3, 0.8]))])
        entity.model = ModelComponent(mesh: try MeshResource(from: mesh), materials: [CloudAssets.rainMaterial(opacity: 0)])
        entity.isEnabled = false
        drops = (0..<n).map { _ in
            Drop(position: .zero, velocity: .zero, length: 0, width: 0, phase: Float.random(in: 0...6.28), active: false)
        }
    }

    /// - Parameters:
    ///   - rate: 0…1 rain intensity
    ///   - wind: horizontal wind (x/z) in m/s
    ///   - sources: points on the underside of the cloud (this entity's space) – rain falls from there
    ///   - groundOffset: position of this entity's space inside the landscape model (for terrain hits)
    ///   - camera: camera position in this entity's space
    func update(rate: Float, wind: SIMD2<Float>, time: Float, dt: Float,
                sources: [SIMD3<Float>], groundOffset: SIMD3<Float>, camera: SIMD3<Float>) {
        guard !sources.isEmpty else { return }
        let lowest = sources.map(\.y).min() ?? 0
        let activeCount = Int(rate * Float(Self.capacity))
        let opacity = min(1, 0.35 + rate * 0.65)
        entity.isEnabled = activeCount > 0 || drops.contains { $0.active }
        guard entity.isEnabled else { return }

        let key = Int32(opacity * 50)
        if key != opacityKey {
            opacityKey = key
            entity.model?.materials = [CloudAssets.rainMaterial(opacity: opacity)]
        }

        for i in drops.indices {
            var d = drops[i]
            if !d.active {
                guard i < activeCount else { continue }
                spawn(&d, sources: sources, wind: wind, time: time, anywhereInShaft: true)
            }
            // Gravity, wind drag and a little turbulence; real drops reach terminal speed quickly.
            let turbulence = SIMD2<Float>(sinf(time * 3.1 + d.phase), cosf(time * 2.7 + d.phase * 1.3)) * 0.25 * simd_length(wind)
            d.velocity.y = max(d.velocity.y - 4.0 * dt, -2.4)
            d.velocity.x += ((wind.x + turbulence.x) - d.velocity.x) * min(1, 3 * dt)
            d.velocity.z += ((wind.y + turbulence.y) - d.velocity.z) * min(1, 3 * dt)
            d.position += d.velocity * dt

            let world = d.position + groundOffset
            if world.y < Terrain.height(world.x, world.z) || d.position.y < lowest - 0.9 {
                if i < activeCount {
                    spawn(&d, sources: sources, wind: wind, time: time, anywhereInShaft: false)
                } else {
                    d.active = false
                }
            }
            drops[i] = d
        }
        writeVertices(camera: camera)
    }

    private func spawn(_ d: inout Drop, sources: [SIMD3<Float>], wind: SIMD2<Float>, time: Float, anywhereInShaft: Bool) {
        // Pick a point under the cloud. Slowly drifting "rain shafts": some areas rain harder.
        var source = sources[Int.random(in: 0..<sources.count)]
        for _ in 0..<3 {
            let shaft = 0.5 + 0.5 * sinf(source.x * 21 + time * 0.6) * cosf(source.z * 17 - time * 0.45)
            if Float.random(in: 0...1) < 0.25 + 0.75 * shaft { break }
            source = sources[Int.random(in: 0..<sources.count)]
        }
        let jitter = SIMD3<Float>(Float.random(in: -0.015...0.015), Float.random(in: -0.02...0), Float.random(in: -0.015...0.015))
        // Spread new drops over the whole shaft when rain starts, so it doesn't arrive as one sheet.
        let drop = anywhereInShaft ? Float.random(in: 0...0.35) : Float.random(in: 0...0.02)
        d.position = source + jitter - SIMD3<Float>(0, drop, 0)
        d.velocity = SIMD3<Float>(wind.x * 0.7, -Float.random(in: 1.3...1.9), wind.y * 0.7)
        d.length = Float.random(in: 0.03...0.06)
        d.width = Float.random(in: 0.0005...0.0009)
        d.active = true
    }

    private func writeVertices(camera: SIMD3<Float>) {
        let drops = self.drops
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: Vertex.self)
            for (i, d) in drops.enumerated() {
                let base = i * 4
                guard d.active else {
                    let zero = Vertex(px: 0, py: 0, pz: 0, nx: 0, ny: 0, nz: 1, u: 0, v: 0)
                    for k in 0..<4 { vertices[base + k] = zero }
                    continue
                }
                let speed = simd_length(d.velocity)
                let direction = speed > 1e-4 ? d.velocity / speed : SIMD3<Float>(0, -1, 0)
                let head = d.position
                let tail = head - direction * d.length
                let toCamera = camera - head
                var side = simd_cross(direction, toCamera)
                let l = simd_length(side)
                side = l > 1e-6 ? side / l * d.width : SIMD3<Float>(d.width, 0, 0)
                let cl = simd_length(toCamera)
                let n = cl > 1e-5 ? toCamera / cl : SIMD3<Float>(0, 0, 1)
                func vertex(_ q: SIMD3<Float>, _ u: Float, _ v: Float) -> Vertex {
                    Vertex(px: q.x, py: q.y, pz: q.z, nx: n.x, ny: n.y, nz: n.z, u: u, v: v)
                }
                vertices[base] = vertex(tail - side, 0, 0)
                vertices[base + 1] = vertex(head - side, 1, 0)
                vertices[base + 2] = vertex(head + side, 1, 1)
                vertices[base + 3] = vertex(tail + side, 0, 1)
            }
        }
    }
}
