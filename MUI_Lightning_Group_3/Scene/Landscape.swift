//
//  Landscape.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import UIKit
import simd

/// Shape of the laser-cut landscape: 60 vertical profile slices, baked from the cutting SVGs
/// (Tools/bake_terrain.py → Resources/terrain_slices.json).
///
/// Model space, metres: origin = centre of the model's footprint on the table (y = 0 is the
/// table top), +x to the visitor's right, +z towards the visitor. Heights are above the table.
enum Terrain {
    private struct File: Decodable {
        let widthMM: Float
        let stepMM: Float
        let slices: [[Float]]
    }

    private struct Grid {
        let columns: Int          // samples along a slice
        let rows: Int             // number of slices
        let step: Float           // metres between samples along a slice
        let heights: [Float]      // metres, row-major: [slice][sample]
    }

    private static let grid: Grid = {
        if let url = Bundle.main.url(forResource: "terrain_slices", withExtension: "json")
                ?? Bundle.main.url(forResource: "terrain_slices", withExtension: "json", subdirectory: "Resources"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(File.self, from: data),
           let columns = file.slices.map(\.count).min(), columns > 1, !file.slices.isEmpty {
            var heights: [Float] = []
            heights.reserveCapacity(columns * file.slices.count)
            for slice in file.slices {
                heights.append(contentsOf: slice.prefix(columns).map { $0 / 1000 })
            }
            return Grid(columns: columns, rows: file.slices.count, step: file.stepMM / 1000, heights: heights)
        }
        print("[Terrain] terrain_slices.json missing – run Tools/bake_terrain.py. Using a flat placeholder.")
        return Grid(columns: 2, rows: 2, step: 0.545, heights: [0.044, 0.044, 0.044, 0.044])
    }()

    // MARK: - Dimensions

    static var width: Float { Float(grid.columns - 1) * grid.step }
    static var depth: Float { Float(grid.rows - 1) * Layout.slicePitch }
    static var sliceCount: Int { grid.rows }
    /// Height of the flat edge of the model (lowest point of the slices).
    static let baseHeight: Float = grid.heights.min() ?? 0.044
    static let maxHeight: Float = grid.heights.max() ?? 0.25

    // MARK: - Height

    /// Grid coordinates (column, row) for a model-space point.
    private static func gridCoordinates(_ x: Float, _ z: Float) -> SIMD2<Float> {
        var u = (x + width / 2) / grid.step
        if !Layout.numberSideOnLeft { u = Float(grid.columns - 1) - u }
        var v = (depth / 2 - z) / Layout.slicePitch            // 0 = front slice
        if !Layout.firstSliceAtFront { v = Float(grid.rows - 1) - v }
        return [u, v]
    }

    private static func sample(_ column: Int, _ row: Int) -> Float {
        let c = max(0, min(grid.columns - 1, column))
        let r = max(0, min(grid.rows - 1, row))
        return grid.heights[r * grid.columns + c]
    }

    static func isInside(_ x: Float, _ z: Float) -> Bool {
        abs(x) <= width / 2 && abs(z) <= depth / 2 + Layout.slicePitch / 2
    }

    /// Height above the table (bilinear between samples and slices); 0 outside the model.
    static func height(_ x: Float, _ z: Float) -> Float {
        guard isInside(x, z) else { return 0 }
        let g = gridCoordinates(x, z)
        let c0 = Int(floorf(g.x)), r0 = Int(floorf(g.y))
        let fx = g.x - Float(c0), fz = g.y - Float(r0)
        let a = sample(c0, r0), b = sample(c0 + 1, r0)
        let c = sample(c0, r0 + 1), d = sample(c0 + 1, r0 + 1)
        return (a + (b - a) * fx) * (1 - fz) + (c + (d - c) * fx) * fz
    }

    /// Smooth height (Catmull-Rom across slices) – used for the virtual terrain mesh.
    static func detailedHeight(_ x: Float, _ z: Float) -> Float {
        guard isInside(x, z) else { return 0 }
        let g = gridCoordinates(x, z)
        let c0 = Int(floorf(g.x)), fx = g.x - Float(c0)
        let r1 = Int(floorf(g.y)), t = g.y - Float(r1)
        func row(_ r: Int) -> Float { sample(c0, r) + (sample(c0 + 1, r) - sample(c0, r)) * fx }
        let p0 = row(r1 - 1), p1 = row(r1), p2 = row(r1 + 1), p3 = row(r1 + 2)
        let t2 = t * t, t3 = t2 * t
        let h = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
        return max(min(p1, p2) - 0.01, min(max(p1, p2) + 0.01, h))
    }

    // MARK: - Points the story uses (computed from the shape)

    /// Lightning hits the highest point of the model.
    static let strikePoint: SIMD3<Float> = {
        var best = SIMD3<Float>(0, 0, 0)
        for r in 0..<grid.rows {
            for c in 0..<grid.columns where sample(c, r) > best.y {
                best = [point(column: c, row: r).x, sample(c, r), point(column: c, row: r).y]
            }
        }
        return best
    }()

    /// Model x/z of a grid sample.
    private static func point(column: Int, row: Int) -> SIMD2<Float> {
        var c = Float(column), r = Float(row)
        if !Layout.numberSideOnLeft { c = Float(grid.columns - 1) - c }
        if !Layout.firstSliceAtFront { r = Float(grid.rows - 1) - r }
        return [-width / 2 + c * grid.step, depth / 2 - r * Layout.slicePitch]
    }

    /// Spread-out points from a candidate list (farthest-point sampling).
    private static func spread(_ candidates: [SIMD2<Float>], count: Int) -> [SIMD2<Float>] {
        guard var chosen = candidates.first else { return [[0, 0]] }
        var result = [chosen]
        while result.count < count {
            guard let next = candidates.max(by: { a, b in
                result.map { simd_distance($0, a) }.min()! < result.map { simd_distance($0, b) }.min()!
            }) else { break }
            chosen = next
            result.append(chosen)
        }
        return result
    }

    private static func candidates(_ keep: (SIMD2<Float>, Float) -> Bool) -> [SIMD2<Float>] {
        var list: [SIMD2<Float>] = []
        for r in stride(from: 2, to: grid.rows - 2, by: 2) {
            for c in stride(from: 6, to: grid.columns - 6, by: 6) {
                let p = point(column: c, row: r)
                if keep(p, sample(c, r)) { list.append(p) }
            }
        }
        return list
    }

    /// Sun-warmed open ground where warm-air pockets start: low, gentle terrain.
    static let hotSpots: [SIMD2<Float>] = {
        let relief = maxHeight - baseHeight
        let list = candidates { _, h in h > baseHeight + 0.15 * relief && h < baseHeight + 0.45 * relief }
        return list.isEmpty ? [[0, 0.1]] : spread(list, count: 6)
    }()

    /// Low ground at the front, where cool, moist air starts (blue air bubbles).
    static let lowlands: [SIMD2<Float>] = {
        let relief = maxHeight - baseHeight
        let list = candidates { p, h in p.y > depth * 0.12 && h < baseHeight + 0.2 * relief }
        return list.isEmpty ? [[-0.15, depth * 0.35]] : spread(list, count: 8)
    }()

    /// For the "Land heats quickly" label.
    static var landSpot: SIMD2<Float> {
        let front = SIMD2<Float>(0, depth / 2)
        return hotSpots.min { simd_distance($0, front) < simd_distance($1, front) } ?? front
    }

    /// A slope facing the wind, for the "Forced upwards" label.
    static let slopeSpot: SIMD2<Float> = {
        let relief = maxHeight - baseHeight
        let list = candidates { p, h in
            let e: Float = 0.01
            let uphill = height(p.x + Wind.direction.x * e, p.y + Wind.direction.y * e) - height(p.x, p.y)
            return h > baseHeight + 0.4 * relief && h < baseHeight + 0.7 * relief && uphill > 0.002
        }
        return list.min { $0.y > $1.y } ?? [-0.1, 0]
    }()
}

/// Small deterministic value noise (no assets needed).
enum Noise {
    @inline(__always) private static func hash(_ x: Int32, _ y: Int32) -> Float {
        var h = UInt32(bitPattern: x) &* 374_761_393 &+ UInt32(bitPattern: y) &* 668_265_263
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Float(h ^ (h >> 16)) / Float(UInt32.max)
    }

    static func value(_ p: SIMD2<Float>) -> Float {
        let i = SIMD2<Float>(floorf(p.x), floorf(p.y))
        let f = p - i
        let u = f * f * (3 - 2 * f)
        let x = Int32(i.x), y = Int32(i.y)
        let a = hash(x, y), b = hash(x + 1, y), c = hash(x, y + 1), d = hash(x + 1, y + 1)
        return a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y
    }

    static func fbm(_ p: SIMD2<Float>, octaves: Int) -> Float {
        var sum: Float = 0, amplitude: Float = 0.5, total: Float = 0, q = p
        for _ in 0..<octaves {
            sum += value(q) * amplitude
            total += amplitude
            amplitude *= 0.5
            q = q * 2.03 + SIMD2<Float>(17.1, 9.7)
        }
        return sum / total
    }

    /// Sharp crests – mountain ridges.
    static func ridged(_ p: SIMD2<Float>, octaves: Int) -> Float {
        var sum: Float = 0, amplitude: Float = 0.5, total: Float = 0, q = p
        for _ in 0..<octaves {
            let n = 1 - abs(value(q) * 2 - 1)
            sum += n * n * amplitude
            total += amplitude
            amplitude *= 0.5
            q = q * 2.1 + SIMD2<Float>(5.3, 11.2)
        }
        return sum / total
    }
}

/// Virtual stand-in for the physical model. With the physical model present it
/// becomes invisible but still occludes rain, wind and lightning behind real mountains.
@MainActor
final class LandscapeEntity {
    let entity = Entity()

    init(showVirtual: Bool) {
        let material: any Material
        if showVirtual {
            var ground = PhysicallyBasedMaterial()
            if let texture = Self.makeTerrainTexture() {
                ground.baseColor = .init(tint: .white, texture: .init(texture))
            } else {
                ground.baseColor = .init(tint: UIColor(red: 0.36, green: 0.48, blue: 0.27, alpha: 1))
            }
            ground.roughness = .init(floatLiteral: 0.93)
            ground.metallic = .init(floatLiteral: 0)
            material = ground
        } else if Layout.useOcclusionMask {
            // Invisible, but hides everything behind the real slices.
            material = OcclusionMaterial()
        } else {
            return   // physical model without a mask: nothing to draw
        }
        if let mesh = try? Self.makeTerrainMesh() {
            entity.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }
    }

    // MARK: - Mesh

    /// Height field over the model's footprint; the outer ring of vertices drops to the table,
    /// forming the model's side walls.
    static func makeTerrainMesh() throws -> MeshResource {
        let columns = Int(Terrain.width / 0.002) + 3
        let rows = (Terrain.sliceCount - 1) * 3 + 3
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        positions.reserveCapacity(columns * rows)
        let e: Float = 0.003
        let halfW = Terrain.width / 2, halfD = Terrain.depth / 2

        for j in 0..<rows {
            for i in 0..<columns {
                let u = Float(max(0, min(columns - 3, i - 1))) / Float(columns - 3)
                let v = Float(max(0, min(rows - 3, j - 1))) / Float(rows - 3)
                let x = -halfW + Terrain.width * u
                let z = -halfD + Terrain.depth * v
                let border = i == 0 || j == 0 || i == columns - 1 || j == rows - 1
                positions.append([x, border ? 0 : Terrain.detailedHeight(x, z), z])
                if border {
                    let outward = SIMD3<Float>(i == 0 ? -1 : (i == columns - 1 ? 1 : 0), 0, j == 0 ? -1 : (j == rows - 1 ? 1 : 0))
                    normals.append(simd_normalize(outward + SIMD3<Float>(0, 0.0001, 0)))
                } else {
                    let nx = Terrain.detailedHeight(x - e, z) - Terrain.detailedHeight(x + e, z)
                    let nz = Terrain.detailedHeight(x, z - e) - Terrain.detailedHeight(x, z + e)
                    normals.append(simd_normalize(SIMD3<Float>(nx, 2 * e, nz)))
                }
                // Texture row 0 = back edge (−z); RealityKit's v runs bottom-up.
                uvs.append([u, 1 - v])
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity((columns - 1) * (rows - 1) * 6)
        for j in 0..<(rows - 1) {
            for i in 0..<(columns - 1) {
                let a = UInt32(j * columns + i)
                let b = a + 1
                let c = a + UInt32(columns)
                let d = c + 1
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        var descriptor = MeshDescriptor(name: "terrain")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    // MARK: - Surface texture (generated once at start)

    /// Meadows, forest patches, rock on steep slopes, snow on the summits.
    static func makeTerrainTexture(width: Int = 768) -> TextureResource? {
        let height = max(64, Int(Float(width) * Terrain.depth / Terrain.width))
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let e: Float = 0.007        // slope over ~1.5 cm, like the gentle shading of the model

        func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * max(0, min(1, t)) }

        let meadowA = SIMD3<Float>(0.30, 0.42, 0.18), meadowB = SIMD3<Float>(0.45, 0.52, 0.25)
        let forest = SIMD3<Float>(0.11, 0.2, 0.1)
        let alpine = SIMD3<Float>(0.44, 0.43, 0.3)
        let rockA = SIMD3<Float>(0.38, 0.36, 0.33), rockB = SIMD3<Float>(0.55, 0.52, 0.47)
        let snow = SIMD3<Float>(0.92, 0.94, 0.97)

        for row in 0..<height {
            for col in 0..<width {
                let x = -Terrain.width / 2 + Terrain.width * Float(col) / Float(width - 1)
                let z = -Terrain.depth / 2 + Terrain.depth * Float(row) / Float(height - 1)
                guard Terrain.isInside(x, z) else { continue }
                let p = SIMD2<Float>(x, z)
                // Relief 0 (flat edge) … 1 (highest summit) – colour bands follow the model's own range.
                let r = (Terrain.detailedHeight(x, z) - Terrain.baseHeight) / max(0.01, Terrain.maxHeight - Terrain.baseHeight)
                let gx = (Terrain.detailedHeight(x + e, z) - Terrain.detailedHeight(x - e, z)) / (2 * e)
                let gz = (Terrain.detailedHeight(x, z + e) - Terrain.detailedHeight(x, z - e)) / (2 * e)
                let slope = sqrtf(gx * gx + gz * gz)
                let n1 = Noise.fbm(p * 22, octaves: 4)
                let n2 = Noise.fbm(p * 60 + 3, octaves: 3)
                let fine = Noise.value(p * 400)

                // Meadow with patches of lighter and darker grass.
                var c = mix(meadowA, meadowB, n1 * 1.4 - 0.2)
                // Forests in the foothills, in irregular patches.
                let forestAmount = ramp(n2 + 0.25 * (n1 - 0.5), from: 0.5, to: 0.58) * ramp(r, from: 0.06, to: 0.14)
                    * (1 - ramp(r, from: 0.42 + 0.08 * n1, to: 0.52 + 0.08 * n1))
                c = mix(c, forest * (0.85 + 0.3 * fine), forestAmount)
                // Alpine meadow above the tree line.
                c = mix(c, alpine * (0.9 + 0.2 * fine), ramp(r, from: 0.45, to: 0.58) * (1 - forestAmount))
                // Bare rock on steep high slopes and on the upper mountain.
                let rockAmount = max(ramp(slope, from: 2.2, to: 3.2) * ramp(r, from: 0.3, to: 0.5),
                                     ramp(r, from: 0.62 + 0.08 * n2, to: 0.74 + 0.08 * n2))
                c = mix(c, mix(rockA, rockB, n2 + 0.3 * fine - 0.15), rockAmount)
                // Snow caps on the summits.
                let ridges = Noise.ridged(p * 30, octaves: 3)
                let snowLine: Float = 0.84 + 0.06 * (n1 - 0.5) + 0.05 * (ridges - 0.5)
                let snowAmount = ramp(r, from: snowLine, to: snowLine + 0.04)
                    * (1 - ramp(slope, from: 3, to: 4.5)) * ramp(ridges + 0.3 * n2, from: 0.3, to: 0.5)
                c = mix(c, snow * (0.94 + 0.06 * fine), snowAmount)
                // A little grain everywhere.
                c *= 0.93 + 0.14 * fine

                let k = (row * width + col) * 4
                pixels[k] = UInt8(max(0, min(255, c.x * 255)))
                pixels[k + 1] = UInt8(max(0, min(255, c.y * 255)))
                pixels[k + 2] = UInt8(max(0, min(255, c.z * 255)))
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }
}
