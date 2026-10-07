//
//  SkyDimmer.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import UIKit
import simd

/// Darkens the room as the storm builds, and flashes it with lightning.
///
/// A box of large, semi-transparent planes ~5 m around the viewer. Because each plane is far
/// away, RealityKit draws it *before* the clouds, rain and wind (transparent content is sorted
/// back to front), so soft cloud edges blend smoothly over the darkened room – unlike the system
/// passthrough dimming, which left hard-edged cut-outs around semi-transparent content.
@MainActor
final class SkyDimmer {
    let entity = Entity()
    private var walls: [ModelEntity] = []
    private var key: SIMD4<Int32>?

    init() {
        let mesh = MeshResource.generatePlane(width: 10, height: 10)
        let material = Self.material(color: [0, 0, 0], opacity: 0)
        let quarter = Float.pi / 2
        let placements: [(SIMD3<Float>, simd_quatf)] = [
            ([0, 0, -5], simd_quatf(angle: 0, axis: [0, 1, 0])),
            ([0, 0, 5], simd_quatf(angle: .pi, axis: [0, 1, 0])),
            ([-5, 0, 0], simd_quatf(angle: quarter, axis: [0, 1, 0])),
            ([5, 0, 0], simd_quatf(angle: -quarter, axis: [0, 1, 0])),
            ([0, 5, 0], simd_quatf(angle: quarter, axis: [1, 0, 0])),
            ([0, -5, 0], simd_quatf(angle: -quarter, axis: [1, 0, 0])),
        ]
        for (position, orientation) in placements {
            let wall = ModelEntity(mesh: mesh, materials: [material])
            wall.position = position
            wall.orientation = orientation
            entity.addChild(wall)
            walls.append(wall)
        }
        entity.isEnabled = false
    }

    /// - Parameters: darkness 0…1 (storm), flash 0…1 (lightning), head = world position of the viewer.
    func update(darkness: Float, flash: Float, head: SIMD3<Float>) {
        entity.position = head
        let opacity = max(0.6 * darkness, 0.45 * flash)
        entity.isEnabled = opacity > 0.01
        guard entity.isEnabled else { return }
        // Storm: cool blue-grey dusk. Lightning: bluish white.
        let color = lerp3([0.035, 0.045, 0.07], [0.85, 0.88, 1.0], min(1, flash))
        let newKey = SIMD4<Int32>(Int32(color.x * 60), Int32(color.y * 60), Int32(color.z * 60), Int32(opacity * 120))
        guard newKey != key else { return }
        key = newKey
        let material = Self.material(color: color, opacity: opacity)
        for wall in walls { wall.model?.materials = [material] }
    }

    private static func material(color: SIMD3<Float>, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: UIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: 1))
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        material.faceCulling = .none
        material.writesDepth = false
        return material
    }
}
