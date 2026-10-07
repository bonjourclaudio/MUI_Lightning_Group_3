//
//  ChargedClouds.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import UIKit
import simd

struct ChargeComponent: Component {
    var charge: Charge
    var slot: Int
    var isDragging = false
    var isAbsorbing = false
    var dragOffset: SIMD3<Float> = .zero
    var bob: Float = 0
}

/// A small cloud with the shape and baked lighting of the Blender start cloud.
@MainActor
final class MiniCloud {
    let entity = Entity()
    private var batch: SpriteBatch?
    private var sprites: [Sprite]
    private let source: [MiniSprite]
    private let size: Float

    init(size: Float, tint: SIMD3<Float>) {
        self.size = size
        source = CloudAssets.morph?.mini ?? []
        sprites = Array(repeating: Sprite(position: .zero, radius: 0, shade: 1, variant: 0, rotation: 0), count: source.count)
        if !source.isEmpty,
           let batch = try? SpriteBatch(capacity: source.count,
                                        material: CloudAssets.cloudMaterial(tint: tint, opacity: 1),
                                        bounds: BoundingBox(min: .init(repeating: -size), max: .init(repeating: size))) {
            entity.addChild(batch.entity)
            self.batch = batch
        } else {
            // Fallback if the baked data is missing.
            let puff = ModelEntity(mesh: .generateSphere(radius: size * 0.35),
                                   materials: [Materials.lit(UIColor(red: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1), roughness: 1)])
            entity.addChild(puff)
        }
    }

    func update(time: Float, camera: SIMD3<Float>) {
        guard let batch else { return }
        for i in source.indices {
            let s = source[i]
            let k = Float(i) * 0.37
            sprites[i] = Sprite(position: s.position * size + SIMD3<Float>(0, 0.0015 * sinf(time * 0.8 + k), 0),
                                radius: s.radius * size * (1 + 0.05 * sinf(time * 0.9 + k)),
                                shade: s.shade,
                                variant: i % 4,
                                rotation: k * 2.1 + time * 0.03)
        }
        batch.update(sprites, camera: batch.entity.convert(position: camera, from: nil))
    }
}

/// Small + / − clouds floating around the storm. Drag them onto the storm (or tap them).
@MainActor
final class ChargedCloudField {
    let entity = Entity()
    var onAbsorb: ((Charge) -> Void)?
    private(set) var isActive = false

    private static let cloudSize: Float = 0.13

    private let cloud: StormCloud
    private var clouds: [Entity] = []
    private var minis: [ObjectIdentifier: MiniCloud] = [:]
    private var occupied: Set<Int> = []
    private var pending: [Task<Void, Never>] = []
    private let slots: [SIMD3<Float>]
    private var cameraWorld: SIMD3<Float> = [0, 1.55, 0]

    init(cloud: StormCloud) {
        self.cloud = cloud
        // Arc around the storm, facing the user (+z).
        let center = SceneController.cloudBase + SIMD3<Float>(0, 0.2, 0)
        let angles: [Float] = [-105, -65, -25, 25, 65, 105]
        let heights: [Float] = [0.06, -0.08, 0.12, -0.04, 0.1, -0.07]
        var result: [SIMD3<Float>] = []
        for (angle, height) in zip(angles, heights) {
            let r = angle * .pi / 180
            result.append(center + SIMD3<Float>(0.52 * sinf(r), height, 0.44 * cosf(r) + 0.05))
        }
        slots = result
    }

    // MARK: - Lifecycle

    func activate() {
        guard !isActive else { return }
        isActive = true
        for slot in slots.indices {
            scheduleSpawn(slot: slot, after: 0.3 + Double(slot) * 0.25)
        }
    }

    func deactivate() {
        isActive = false
        pending.forEach { $0.cancel() }
        pending.removeAll()
        let leaving = clouds
        clouds.removeAll()
        occupied.removeAll()
        cloud.setHighlighted(false)
        for c in leaving {
            c.components.remove(InputTargetComponent.self)
            if let visual = c.children.first {
                visual.move(to: Transform(scale: .init(repeating: 0.01)), relativeTo: c, duration: 0.4, timingFunction: .easeIn)
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            for c in leaving {
                c.removeFromParent()
                self.minis[ObjectIdentifier(c)] = nil
            }
        }
    }

    func update(time: Float, dt: Float, camera: SIMD3<Float>) {
        cameraWorld = camera
        let k = approachFactor(rate: 3, dt: dt)
        for c in clouds {
            minis[ObjectIdentifier(c)]?.update(time: time, camera: camera)
            guard let comp = c.components[ChargeComponent.self], !comp.isDragging, !comp.isAbsorbing else { continue }
            let target = slots[comp.slot] + SIMD3<Float>(0.012 * sinf(time * 0.7 + comp.bob),
                                                         0.018 * sinf(time * 1.1 + comp.bob),
                                                         0)
            c.position += (target - c.position) * k
        }
    }

    // MARK: - Gestures

    func drag(_ hit: Entity, to worldPosition: SIMD3<Float>, start worldStart: SIMD3<Float>) {
        guard isActive, let c = cloudRoot(for: hit),
              var comp = c.components[ChargeComponent.self], !comp.isAbsorbing else { return }
        if !comp.isDragging {
            comp.isDragging = true
            comp.dragOffset = c.position(relativeTo: nil) - worldStart
            c.components.set(comp)
            c.children.first?.move(to: Transform(scale: .init(repeating: 1.12)), relativeTo: c, duration: 0.2, timingFunction: .easeOut)
        }
        c.setPosition(worldPosition + comp.dragOffset, relativeTo: nil)
        cloud.setHighlighted(isOverStorm(c))
    }

    func endDrag(_ hit: Entity) {
        guard let c = cloudRoot(for: hit), var comp = c.components[ChargeComponent.self] else { return }
        comp.isDragging = false
        c.components.set(comp)
        cloud.setHighlighted(false)
        if isActive && isOverStorm(c) {
            absorb(c)
        } else {
            c.children.first?.move(to: Transform(scale: .one), relativeTo: c, duration: 0.25, timingFunction: .easeOut)
        }
        // Otherwise `update` floats it back to its place.
    }

    /// Tap alternative.
    func sendToStorm(_ hit: Entity) {
        guard isActive, let c = cloudRoot(for: hit),
              let comp = c.components[ChargeComponent.self], !comp.isDragging else { return }
        absorb(c)
    }

    // MARK: - Private

    private func cloudRoot(for entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let e = current {
            if e.components.has(ChargeComponent.self) { return e }
            current = e.parent
        }
        return nil
    }

    /// True when the small cloud *looks* like it is on the storm from the viewer's position.
    /// A drag keeps the object's depth (especially with a mouse in the simulator), so a pure
    /// 3D distance check almost never succeeds – compare viewing directions instead.
    private func isOverStorm(_ c: Entity) -> Bool {
        let position = c.position(relativeTo: nil)
        let storm = cloud.centerWorld
        if simd_distance(position, storm) < cloud.captureRadius { return true }
        let toCloud = position - cameraWorld
        let toStorm = storm - cameraWorld
        let stormDistance = simd_length(toStorm)
        guard stormDistance > 0.05, simd_length(toCloud) > 0.05 else { return false }
        let cosine = simd_dot(simd_normalize(toCloud), simd_normalize(toStorm))
        let angle = acosf(max(-1, min(1, cosine)))
        let angularRadius = atanf((cloud.captureRadius + Self.cloudSize * 0.3) / stormDistance)
        return angle < angularRadius
    }

    private func absorb(_ c: Entity) {
        guard var comp = c.components[ChargeComponent.self], !comp.isAbsorbing else { return }
        comp.isAbsorbing = true
        c.components.set(comp)
        c.components.remove(InputTargetComponent.self)
        cloud.setHighlighted(false)

        let destination = entity.convert(position: cloud.centerWorld, from: nil)
        c.move(to: Transform(scale: .init(repeating: 0.25), rotation: c.orientation, translation: destination),
               relativeTo: entity, duration: 0.6, timingFunction: .easeIn)

        let slot = comp.slot
        let charge = comp.charge
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(620))
            guard let self else { return }
            c.removeFromParent()
            self.minis[ObjectIdentifier(c)] = nil
            self.clouds.removeAll { $0 === c }
            self.occupied.remove(slot)
            guard self.isActive else { return }
            self.onAbsorb?(charge)
            if self.isActive { self.scheduleSpawn(slot: slot, after: 1.2) }
        }
    }

    private func scheduleSpawn(slot: Int, after delay: Double) {
        pending.removeAll { $0.isCancelled }
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.isActive, !self.occupied.contains(slot) else { return }
            self.spawn(slot: slot)
        }
        pending.append(task)
    }

    private func chooseCharge() -> Charge {
        let floating = clouds.compactMap { $0.components[ChargeComponent.self] }.filter { !$0.isAbsorbing }
        let positives = floating.filter { $0.charge == .positive }.count
        let negatives = floating.count - positives
        if positives < 2 { return .positive }
        if negatives < 2 { return .negative }
        return Bool.random() ? .positive : .negative
    }

    private func spawn(slot: Int) {
        let charge = chooseCharge()
        let root = Entity()
        root.name = "ChargedCloud-\(charge.rawValue)"
        root.position = slots[slot]

        let visual = Entity()
        visual.scale = .init(repeating: 0.01)
        root.addChild(visual)

        let tint: SIMD3<Float> = charge == .positive ? [1.0, 0.86, 0.83] : [0.84, 0.9, 1.0]
        let mini = MiniCloud(size: Self.cloudSize, tint: tint)
        visual.addChild(mini.entity)
        visual.addChild(makeLabel(for: charge))

        root.components.set(ChargeComponent(charge: charge, slot: slot, bob: Float.random(in: 0...6.28)))
        root.components.set(InputTargetComponent())
        root.components.set(CollisionComponent(shapes: [.generateSphere(radius: Self.cloudSize * 0.55)]))
        // No HoverEffectComponent: the system highlight lights up the square geometry of
        // every soft puff (visible "hitbox"). Feedback comes from the grab scale + storm pulse.

        entity.addChild(root)
        clouds.append(root)
        minis[ObjectIdentifier(root)] = mini
        occupied.insert(slot)
        visual.move(to: Transform(scale: .one), relativeTo: root, duration: 0.8, timingFunction: .easeOut)
    }

    private func makeLabel(for charge: Charge) -> Entity {
        let pivot = Entity()
        pivot.components.set(BillboardComponent())
        let mesh = MeshResource.generateText(charge.symbol,
                                             extrusionDepth: 0.003,
                                             font: .systemFont(ofSize: 0.06, weight: .heavy),
                                             containerFrame: .zero,
                                             alignment: .center,
                                             lineBreakMode: .byClipping)
        let color = charge == .positive
            ? UIColor(red: 0.92, green: 0.16, blue: 0.1, alpha: 1)
            : UIColor(red: 0.1, green: 0.36, blue: 0.95, alpha: 1)
        let text = ModelEntity(mesh: mesh, materials: [Materials.unlit(color)])
        let center = mesh.bounds.center
        text.position = [-center.x, -center.y, Self.cloudSize * 0.5]
        pivot.addChild(text)
        return pivot
    }
}
