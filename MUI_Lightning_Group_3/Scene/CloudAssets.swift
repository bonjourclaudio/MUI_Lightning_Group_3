//
//  CloudAssets.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import UIKit
import simd

/// One sprite of the main cloud: where it sits in the start cloud and in the end (anvil) cloud.
struct MorphSprite {
    let start: SIMD3<Float>
    let startRadius: Float
    let startShade: Float
    let end: SIMD3<Float>
    let endRadius: Float
    let endShade: Float
    /// 0…0.5 – higher parts of the anvil start moving later.
    let delay: Float
    let seed: Float
}

struct MiniSprite {
    let position: SIMD3<Float>   // normalised, cloud extent = 1
    let radius: Float
    let shade: Float
}

struct CloudBox {
    var min: SIMD3<Float>
    var max: SIMD3<Float>

    var size: SIMD3<Float> { max - min }
    var center: SIMD3<Float> { (min + max) * 0.5 }

    static func lerp(_ a: CloudBox, _ b: CloudBox, _ t: Float) -> CloudBox {
        CloudBox(min: lerp3(a.min, b.min, t), max: lerp3(a.max, b.max, t))
    }
}

/// Baked data from the Blender clouds (see Tools/bake_clouds.py) + shared textures/materials.
@MainActor
enum CloudAssets {
    struct Morph {
        let sprites: [MorphSprite]
        let startBox: CloudBox
        let endBox: CloudBox
        let mini: [MiniSprite]
    }

    private struct File: Decodable {
        let sprites: [[Float]]
        let startBounds: [[Float]]
        let endBounds: [[Float]]
        let mini: [[Float]]
    }

    static let morph: Morph? = loadMorph()

    private static let puffColor = texture("cloud_puff_atlas", semantic: .color)
    private static let puffAlpha = texture("cloud_puff_atlas_alpha", semantic: .raw)
    private static let windColor = texture("wind_streak", semantic: .color)
    private static let windAlpha = texture("wind_streak_alpha", semantic: .raw)
    private static let sunColor = texture("sun_glow", semantic: .color)
    private static let sunAlpha = texture("sun_glow_alpha", semantic: .raw)

    // MARK: - Materials

    /// Cloud material: baked light & shadow live in the puff atlas, `tint` darkens/greys it for the storm.
    static func cloudMaterial(tint: SIMD3<Float>, opacity: Float) -> UnlitMaterial {
        spriteMaterial(color: puffColor, alpha: puffAlpha, tint: tint, opacity: opacity)
    }

    static func windMaterial(opacity: Float) -> UnlitMaterial {
        spriteMaterial(color: windColor, alpha: windAlpha, tint: [0.92, 0.96, 1.0], opacity: opacity)
    }

    /// Uses the streak texture: soft tail, brighter head.
    static func rainMaterial(opacity: Float) -> UnlitMaterial {
        spriteMaterial(color: windColor, alpha: windAlpha, tint: [0.8, 0.86, 0.95], opacity: opacity)
    }

    static func sunMaterial(tint: SIMD3<Float>, opacity: Float) -> UnlitMaterial {
        spriteMaterial(color: sunColor, alpha: sunAlpha, tint: tint, opacity: opacity)
    }

    private static func spriteMaterial(color: TextureResource?, alpha: TextureResource?, tint: SIMD3<Float>, opacity: Float) -> UnlitMaterial {
        let tintColor = UIColor(red: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1)
        var material = UnlitMaterial()
        if let color {
            material.color = .init(tint: tintColor, texture: .init(color))
        } else {
            material.color = .init(tint: tintColor)
        }
        if let alpha {
            material.blending = .transparent(opacity: .init(scale: max(0, opacity), texture: .init(alpha)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: max(0, opacity) * 0.5))
        }
        material.faceCulling = .none
        // Soft sprites must not write depth, otherwise their transparent corners punch
        // square holes into clouds, rain and wind drawn behind them.
        material.writesDepth = false
        return material
    }

    // MARK: - Loading

    private static func resourceURL(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }

    private static func texture(_ name: String, semantic: TextureResource.Semantic) -> TextureResource? {
        guard let url = resourceURL(name, "png"),
              let image = UIImage(contentsOfFile: url.path)?.cgImage else {
            print("[CloudAssets] Missing texture \(name).png – run Tools/bake_clouds.py")
            return nil
        }
        do {
            return try TextureResource.generate(from: image, options: .init(semantic: semantic))
        } catch {
            print("[CloudAssets] Could not load \(name): \(error)")
            return nil
        }
    }

    private static func loadMorph() -> Morph? {
        guard let url = resourceURL("cloud_morph", "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            print("[CloudAssets] Missing cloud_morph.json – run Tools/bake_clouds.py")
            return nil
        }
        let sprites = file.sprites.compactMap { r -> MorphSprite? in
            guard r.count >= 12 else { return nil }
            return MorphSprite(start: [r[0], r[1], r[2]], startRadius: r[3], startShade: r[4],
                               end: [r[5], r[6], r[7]], endRadius: r[8], endShade: r[9],
                               delay: r[10], seed: r[11])
        }
        let mini = file.mini.compactMap { r -> MiniSprite? in
            guard r.count >= 5 else { return nil }
            return MiniSprite(position: [r[0], r[1], r[2]], radius: r[3], shade: r[4])
        }
        func box(_ b: [[Float]]) -> CloudBox {
            CloudBox(min: [b[0][0], b[0][1], b[0][2]], max: [b[1][0], b[1][1], b[1][2]])
        }
        return Morph(sprites: sprites, startBox: box(file.startBounds), endBox: box(file.endBounds), mini: mini)
    }
}
