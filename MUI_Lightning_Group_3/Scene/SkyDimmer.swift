//
//  SkyDimmer.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import UIKit
import CoreGraphics
import simd

/// Darkens the room as the storm builds, and flashes it with lightning.
///
/// A dome ~5 m around the viewer with a vertical gradient instead of a mask: the sky and the
/// walls (looking straight ahead or up) get the full storm darkness, looking down towards the
/// table and the model it fades out. So the real model stays readable and there are no hard
/// edges – nothing has to line up exactly with the physical model.
///
/// The dome is split into patches, each its own entity a few metres away, so RealityKit draws
/// it *before* the clouds, rain and wind (transparent content is sorted back to front).
@MainActor
final class SkyDimmer {
    let entity = Entity()
    private var patches: [ModelEntity] = []
    private var key: SIMD4<Int32>?
    private let alphaTexture: TextureResource?

    // Gradient (elevation of the view direction, degrees): full darkness above `fullAbove`,
    // fading to `floorLevel` of it at `clearBelow` and further down. The model is usually seen
    // 25–35° below eye level, so it sits in the light part.
    static let fullAbove: Float = 0
    static let clearBelow: Float = -35
    static let floorLevel: Float = 0.22

    private static let radius: Float = 5
    private static let sectors = 8
    private static let bands: [(Float, Float)] = [(-90, -45), (-45, -15), (-15, 20), (20, 90)]

    init() {
        alphaTexture = Self.makeGradientTexture()
        let material = Self.material(color: [0, 0, 0], opacity: 0, alpha: alphaTexture)
        for s in 0..<Self.sectors {
            for band in Self.bands {
                guard let piece = Self.makePatch(sector: s, band: band) else { continue }
                let patch = ModelEntity(mesh: piece.mesh, materials: [material])
                patch.position = piece.centre
                entity.addChild(patch)
                patches.append(patch)
            }
        }
        entity.isEnabled = false
    }

    /// - Parameters: darkness 0…1 (storm), flash 0…1 (lightning), head = world position of the viewer.
    func update(darkness: Float, flash: Float, head: SIMD3<Float>) {
        entity.position = head
        // Up to 85 % dimming of the sky at the storm's peak.
        let opacity = max(0.85 * darkness * darkness * (3 - 2 * darkness), 0.5 * flash)
        entity.isEnabled = opacity > 0.01
        guard entity.isEnabled else { return }
        // Storm: dull blue-grey, like the light under a thunderstorm. Lightning: bluish white.
        let color = lerp3([0.09, 0.1, 0.12], [0.85, 0.88, 1.0], min(1, flash))
        let newKey = SIMD4<Int32>(Int32(color.x * 60), Int32(color.y * 60), Int32(color.z * 60), Int32(opacity * 120))
        guard newKey != key else { return }
        key = newKey
        let material = Self.material(color: color, opacity: opacity, alpha: alphaTexture)
        for patch in patches { patch.model?.materials = [material] }
    }

    private static func material(color: SIMD3<Float>, opacity: Float, alpha: TextureResource?) -> UnlitMaterial {
        var material = UnlitMaterial(color: UIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1))
        if let alpha {
            material.blending = .transparent(opacity: .init(scale: opacity, texture: .init(alpha)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity * 0.5))
        }
        material.faceCulling = .none
        material.writesDepth = false
        return material
    }

    // MARK: - Gradient

    /// Opacity factor (0…1) for a view direction's elevation in degrees.
    static func gradient(elevation: Float) -> Float {
        let t = max(0, min(1, (elevation - clearBelow) / (fullAbove - clearBelow)))
        let smooth = t * t * (3 - 2 * t)
        return floorLevel + (1 - floorLevel) * smooth
    }

    /// 256 × 4 greyscale texture along u (u has the same direction in every convention):
    /// u = 0 straight down … u = 1 straight up.
    private static func makeGradientTexture() -> TextureResource? {
        let w = 256, h = 4
        var pixels = [UInt8](repeating: 0, count: w * h)
        for col in 0..<w {
            let u = Float(col) / Float(w - 1)
            let value = UInt8(max(0, min(255, gradient(elevation: u * 180 - 90) * 255)))
            for row in 0..<h { pixels[row * w + col] = value }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .raw))
    }

    // MARK: - Mesh

    /// One piece of the dome (a sector between two elevations), vertices relative to its centre.
    private static func makePatch(sector: Int, band: (Float, Float)) -> (mesh: MeshResource, centre: SIMD3<Float>)? {
        let lonSteps = 6, latSteps = 8
        let lon0 = Float(sector) / Float(sectors) * 2 * .pi
        let lon1 = Float(sector + 1) / Float(sectors) * 2 * .pi
        var points: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        for j in 0...latSteps {
            let elevation = band.0 + (band.1 - band.0) * Float(j) / Float(latSteps)
            let e = elevation * .pi / 180
            for i in 0...lonSteps {
                let lon = lon0 + (lon1 - lon0) * Float(i) / Float(lonSteps)
                points.append(radius * SIMD3<Float>(cosf(e) * cosf(lon), sinf(e), cosf(e) * sinf(lon)))
                uvs.append([(elevation + 90) / 180, 0.5])
            }
        }
        let centre = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        var indices: [UInt32] = []
        let row = UInt32(lonSteps + 1)
        for j in 0..<UInt32(latSteps) {
            for i in 0..<UInt32(lonSteps) {
                let a = j * row + i, b = a + 1, c = a + row, d = c + 1
                indices += [a, c, b, b, c, d]
            }
        }
        var descriptor = MeshDescriptor(name: "SkyDimmerPatch")
        descriptor.positions = MeshBuffers.Positions(points.map { $0 - centre })
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        return (mesh: mesh, centre: centre)
    }
}
