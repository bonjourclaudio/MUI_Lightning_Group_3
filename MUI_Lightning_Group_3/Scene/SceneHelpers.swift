//
//  SceneHelpers.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import UIKit
import simd

enum Materials {
    static func unlit(_ color: UIColor, opacity: Float? = nil) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        if let opacity {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    static func lit(_ color: UIColor, roughness: Float = 0.9, opacity: Float? = nil) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        if let opacity {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }

    /// White fair-weather cloud → dark blue-grey storm cloud.
    static func cloud(brightness b: Float, storm s: Float) -> PhysicallyBasedMaterial {
        let color = UIColor(red: CGFloat(b * (1 - 0.07 * s)),
                            green: CGFloat(b * (1 - 0.035 * s)),
                            blue: CGFloat(b),
                            alpha: 1)
        return lit(color, roughness: 1)
    }
}

/// Deterministic random numbers so the cloud looks the same every run.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    mutating func next() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(state >> 40) / Float(1 << 24)
    }

    mutating func range(_ lower: Float, _ upper: Float) -> Float {
        lower + (upper - lower) * next()
    }
}

/// Smooth 0…1 ramp of `x` between `a` and `b`.
func ramp(_ x: Float, from a: Float, to b: Float) -> Float {
    let t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

func lerp3(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

/// Frame-rate independent smoothing factor.
func approachFactor(rate: Float, dt: Float) -> Float {
    1 - expf(-rate * dt)
}

extension Entity {
    func setOpacity(_ value: Float) {
        if value >= 0.999 {
            components.remove(OpacityComponent.self)
        } else {
            components.set(OpacityComponent(opacity: max(0, value)))
        }
    }
}
