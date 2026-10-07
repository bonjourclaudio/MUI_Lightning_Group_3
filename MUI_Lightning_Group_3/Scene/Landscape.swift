//
//  Landscape.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import UIKit
import simd

/// Shape of the landscape model (metres, model-local, origin = centre of the base plate).
/// Keep this in sync with the physical model so wind, thermals and the lightning
/// strike point line up with the real mountains and lake.
enum Terrain {
    static let width: Float = 1.0
    static let depth: Float = 0.7
    static let lakeCenter = SIMD2<Float>(-0.22, 0.14)
    static let lakeRadius = SIMD2<Float>(0.2, 0.12)
    static let waterLevel: Float = 0.014

    struct Peak {
        let center: SIMD2<Float>
        let height: Float
        let spread: Float
    }

    static let peaks: [Peak] = [
        Peak(center: [-0.28, -0.17], height: 0.16, spread: 0.10),
        Peak(center: [0.04, -0.20], height: 0.21, spread: 0.095),
        Peak(center: [0.29, -0.12], height: 0.13, spread: 0.085),
        Peak(center: [0.36, 0.14], height: 0.06, spread: 0.07),
    ]

    /// Sun-heated land where thermals start.
    static let hotSpots: [SIMD2<Float>] = [
        [0.17, 0.17], [0.0, 0.22], [0.3, 0.03], [-0.42, 0.0], [0.12, 0.05], [-0.05, 0.08],
    ]

    static func height(_ x: Float, _ z: Float) -> Float {
        var h: Float = 0.025 + 0.004 * sinf(x * 23) * cosf(z * 19)
        let p = SIMD2<Float>(x, z)
        for peak in peaks {
            let d = p - peak.center
            h += peak.height * expf(-simd_length_squared(d) / (2 * peak.spread * peak.spread))
        }
        let r2 = simd_length_squared((p - lakeCenter) / lakeRadius)
        if r2 < 1.6 {
            h -= 0.032 * (1 - r2 / 1.6)
        }
        return h
    }

    static func isNearLake(_ x: Float, _ z: Float) -> Bool {
        simd_length_squared((SIMD2<Float>(x, z) - lakeCenter) / lakeRadius) < 1.35
    }

    /// Lightning hits the highest summit.
    static var strikePoint: SIMD3<Float> {
        let c = peaks[1].center
        return [c.x, height(c.x, c.y), c.y]
    }
}

/// Virtual stand-in for the physical model. With the physical model present it
/// becomes invisible but still occludes rain, wind and lightning behind real mountains.
@MainActor
final class LandscapeEntity {
    let entity = Entity()

    init(showVirtual: Bool) {
        let occlusion: any Material = OcclusionMaterial()

        let terrainMaterials: [any Material]
        let baseMaterial: any Material
        if showVirtual {
            terrainMaterials = [
                Materials.lit(UIColor(red: 0.36, green: 0.52, blue: 0.27, alpha: 1)),              // meadow
                Materials.lit(UIColor(red: 0.47, green: 0.44, blue: 0.40, alpha: 1)),              // rock
                Materials.lit(UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1), roughness: 0.7), // snow
                Materials.lit(UIColor(red: 0.78, green: 0.72, blue: 0.54, alpha: 1)),              // shore
            ]
            baseMaterial = Materials.lit(UIColor(red: 0.30, green: 0.24, blue: 0.18, alpha: 1))
        } else {
            terrainMaterials = Array(repeating: occlusion, count: 4)
            baseMaterial = occlusion
        }

        if let mesh = try? Self.makeTerrainMesh() {
            entity.addChild(ModelEntity(mesh: mesh, materials: terrainMaterials))
        }

        let base = ModelEntity(mesh: .generateBox(width: Terrain.width, height: 0.03, depth: Terrain.depth),
                               materials: [baseMaterial])
        base.position.y = -0.015
        entity.addChild(base)

        if showVirtual {
            let water = Materials.lit(UIColor(red: 0.16, green: 0.42, blue: 0.68, alpha: 1), roughness: 0.15, opacity: 0.9)
            let lake = ModelEntity(mesh: .generateCylinder(height: 0.003, radius: 1), materials: [water])
            lake.scale = [Terrain.lakeRadius.x * 1.05, 1, Terrain.lakeRadius.y * 1.05]
            lake.position = [Terrain.lakeCenter.x, Terrain.waterLevel, Terrain.lakeCenter.y]
            entity.addChild(lake)
        }
    }

    static func makeTerrainMesh(columns: Int = 90, rows: Int = 64) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        positions.reserveCapacity(columns * rows)
        normals.reserveCapacity(columns * rows)
        let e: Float = 0.004

        for j in 0..<rows {
            for i in 0..<columns {
                let x = -Terrain.width / 2 + Terrain.width * Float(i) / Float(columns - 1)
                let z = -Terrain.depth / 2 + Terrain.depth * Float(j) / Float(rows - 1)
                let border = i == 0 || j == 0 || i == columns - 1 || j == rows - 1
                positions.append([x, border ? 0 : Terrain.height(x, z), z])
                let nx = Terrain.height(x - e, z) - Terrain.height(x + e, z)
                let nz = Terrain.height(x, z - e) - Terrain.height(x, z + e)
                normals.append(simd_normalize(SIMD3<Float>(nx, 2 * e, nz)))
            }
        }

        var indices: [UInt32] = []
        var faceMaterials: [UInt32] = []
        for j in 0..<(rows - 1) {
            for i in 0..<(columns - 1) {
                let a = UInt32(j * columns + i)
                let b = a + 1
                let c = a + UInt32(columns)
                let d = c + 1
                for triangle in [[a, c, b], [b, c, d]] {
                    indices.append(contentsOf: triangle)
                    let centre = (positions[Int(triangle[0])] + positions[Int(triangle[1])] + positions[Int(triangle[2])]) / 3
                    faceMaterials.append(materialIndex(for: centre))
                }
            }
        }

        var descriptor = MeshDescriptor(name: "terrain")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .perFace(faceMaterials)
        return try MeshResource.generate(from: [descriptor])
    }

    private static func materialIndex(for p: SIMD3<Float>) -> UInt32 {
        if p.y > 0.15 { return 2 }
        if p.y > 0.075 { return 1 }
        if p.y < 0.03 && Terrain.isNearLake(p.x, p.z) { return 3 }
        return 0
    }
}
