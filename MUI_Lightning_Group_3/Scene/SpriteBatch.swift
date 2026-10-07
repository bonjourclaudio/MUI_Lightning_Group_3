//
//  SpriteBatch.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import Metal
import RealityKit
import simd

struct Sprite {
    var position: SIMD3<Float>
    var radius: Float
    /// 0…1 brightness → column of the puff atlas (baked light & shadow).
    var shade: Float
    /// 0…3 → row of the puff atlas (different puff shapes).
    var variant: Int
    var rotation: Float
}

/// Draws many soft, camera-facing sprites as ONE mesh (LowLevelMesh, visionOS 2).
/// Sprites are sorted back-to-front every frame so the alpha blending reads as volume.
@MainActor
final class SpriteBatch {
    let entity = ModelEntity()
    let capacity: Int

    static let columns = 16
    static let rows = 4

    private let mesh: LowLevelMesh

    /// Octagon around the round puff: 8 vertices, 6 triangles per sprite.
    private static let corners: [SIMD2<Float>] = (0..<8).map { k in
        let a = (Float(k) + 0.5) * .pi / 4
        let r: Float = 1.04
        return SIMD2<Float>(max(-1, min(1, cosf(a) * r)), max(-1, min(1, sinf(a) * r)))
    }
    private static let verticesPerSprite = 8
    private static let indicesPerSprite = 18
    private var order: [Int]
    private var depth: [Float]

    private struct Vertex {
        var px: Float, py: Float, pz: Float
        var nx: Float, ny: Float, nz: Float
        var u: Float, v: Float
    }

    init(capacity: Int, material: any Material, bounds: BoundingBox) throws {
        self.capacity = capacity
        order = Array(0..<capacity)
        depth = Array(repeating: 0, count: capacity)

        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: 0),
            .init(semantic: .normal, format: .float3, offset: MemoryLayout<Float>.stride * 3),
            .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Float>.stride * 6),
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
        descriptor.vertexCapacity = capacity * Self.verticesPerSprite
        descriptor.indexCapacity = capacity * Self.indicesPerSprite
        descriptor.indexType = .uint32
        mesh = try LowLevelMesh(descriptor: descriptor)

        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            _ = raw.initializeMemory(as: UInt8.self, repeating: 0)
        }
        writeIndices()
        mesh.parts.replaceAll([LowLevelMesh.Part(indexCount: capacity * Self.indicesPerSprite, topology: .triangle, bounds: bounds)])
        entity.model = ModelComponent(mesh: try MeshResource(from: mesh), materials: [material])
    }

    /// `camera` must be in this entity's local space.
    func update(_ sprites: [Sprite], camera: SIMD3<Float>) {
        let count = min(sprites.count, capacity)
        guard count > 0 else { return }

        var centre = SIMD3<Float>.zero
        for i in 0..<count { centre += sprites[i].position }
        centre /= Float(count)

        var forward = camera - centre
        let fl = simd_length(forward)
        forward = fl > 1e-4 ? forward / fl : [0, 0, 1]
        var right = simd_cross(SIMD3<Float>(0, 1, 0), forward)
        let rl = simd_length(right)
        right = rl > 1e-4 ? right / rl : [1, 0, 0]
        let up = simd_cross(forward, right)

        let du = 1 / Float(Self.columns)
        let dv = 1 / Float(Self.rows)
        let capacity = self.capacity
        var newDepth = depth

        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: Vertex.self)
            for i in 0..<capacity {
                let base = i * Self.verticesPerSprite
                guard i < count, sprites[i].radius > 0.0002 else {
                    let zero = Vertex(px: 0, py: 0, pz: 0, nx: 0, ny: 0, nz: 1, u: 0, v: 0)
                    for k in 0..<Self.verticesPerSprite { vertices[base + k] = zero }
                    newDepth[i] = -1
                    continue
                }
                let s = sprites[i]
                let c = cosf(s.rotation), sn = sinf(s.rotation)
                let rx = (right * c + up * sn) * s.radius
                let uy = (up * c - right * sn) * s.radius
                let column = Float(max(0, min(Self.columns - 1, Int((s.shade * Float(Self.columns - 1)).rounded()))))
                let row = Float(((s.variant % Self.rows) + Self.rows) % Self.rows)
                let u0 = (column + 0.03) * du, u1 = (column + 0.97) * du
                let v0 = (row + 0.03) * dv, v1 = (row + 0.97) * dv
                let p = s.position

                for (k, corner) in Self.corners.enumerated() {
                    let q = p + rx * corner.x + uy * corner.y
                    let u = u0 + (corner.x * 0.5 + 0.5) * (u1 - u0)
                    let v = v1 - (corner.y * 0.5 + 0.5) * (v1 - v0)
                    vertices[base + k] = Vertex(px: q.x, py: q.y, pz: q.z,
                                                nx: forward.x, ny: forward.y, nz: forward.z, u: u, v: v)
                }
                newDepth[i] = simd_distance_squared(p, camera)
            }
        }

        depth = newDepth
        let d = newDepth
        order.sort { d[$0] > d[$1] }   // far → near
        writeIndices()
    }

    private func writeIndices() {
        let order = self.order
        mesh.withUnsafeMutableIndices { raw in
            let indices = raw.bindMemory(to: UInt32.self)
            for (rank, sprite) in order.enumerated() {
                let b = UInt32(sprite * Self.verticesPerSprite)
                var k = rank * Self.indicesPerSprite
                for t in 1...6 {   // triangle fan around the octagon
                    indices[k] = b
                    indices[k + 1] = b + UInt32(t)
                    indices[k + 2] = b + UInt32(t + 1)
                    k += 3
                }
            }
        }
    }
}
