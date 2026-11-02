//
//  SceneController.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import RealityKit
import SwiftUI
import UIKit

/// All animated values of the scene. Story chapters set a *target*,
/// the update loop eases the *current* state towards it every frame.
struct AtmosphereState {
    var sunVisible: Float = 0
    var sunProgress: Float = 0      // 0 = sunrise (left) … 1 = sunset (right)
    var thermals: Float = 0         // rising warm-air bubbles
    var wind: Float = 0             // wind strength (rain slant, sound)
    var windVisible: Float = 0      // wind lines – intro only
    var moistAir: Float = 0         // blue moist air rising from the lowlands – short, in the intro
    var cloudGrowth: Float = 0      // 0 = no cloud … 1 = full tower
    var anvil: Float = 0
    var interior: Float = 0         // show particles inside the cloud
    var separation: Float = 0       // 0 = mixed, 1 = + on top / − in the middle
    var xray: Float = 0             // cloud shell transparency
    var storm: Float = 0            // darkness, rain, sound
    var rainPulse: Float = 0        // extra rain for explanations

    mutating func approach(_ t: AtmosphereState, dt: Float, stormRate: Float = 1.1, sunVisibleRate: Float = 1.0) {
        func step(_ value: inout Float, _ target: Float, _ rate: Float) {
            value += (target - value) * approachFactor(rate: rate, dt: dt)
        }
        step(&sunVisible, t.sunVisible, sunVisibleRate)
        step(&sunProgress, t.sunProgress, 0.35)
        step(&thermals, t.thermals, 0.8)
        step(&wind, t.wind, 0.8)
        step(&windVisible, t.windVisible, 0.6)
        step(&moistAir, t.moistAir, 1.2)
        step(&cloudGrowth, t.cloudGrowth, 0.45)
        step(&anvil, t.anvil, 0.5)
        step(&interior, t.interior, 1.2)
        step(&separation, t.separation, 0.5)
        step(&xray, t.xray, 1.2)
        step(&storm, t.storm, stormRate)
        step(&rainPulse, t.rainPulse, 1.5)
    }
}

/// Marks the see-through landscape used to place the model.
struct PlacementComponent: Component {}

@MainActor
final class SceneController {
    weak var app: AppModel?

    // Placements live in `Layout`; these keep older call sites working.
    static var modelPosition: SIMD3<Float> { Layout.modelPosition }
    static var cloudBase: SIMD3<Float> { Layout.cloudBase }

    /// Opening: the fastest the sun may travel along its path (progress per second),
    /// so dragging can't rush through the morning – ~9 s from sunrise to midday.
    static let maxSunSpeed: Float = 0.045

    var target = AtmosphereState()
    /// How fast the storm darkness follows its target (slower when the sky clears after a strike).
    private var stormRate: Float = 1.1
    private var sunVisibleRate: Float = 1.0
    private(set) var current = AtmosphereState()
    private(set) var isPaused = false

    let root = Entity()
    let modelRoot = Entity()
    let head = HeadLockedFollower()

    private(set) var landscape: LandscapeEntity?
    private(set) var cloud: StormCloud?
    private(set) var effects: AtmosphereEffects?
    private(set) var charged: ChargedCloudField?
    private(set) var bolt: LightningBolt?

    private let dimmer = SkyDimmer()
    private let overcast = OvercastLayer()
    private var flashLevel: Float = 0
    private var dashboardEntity: Entity?
    private var badges: [Int: Entity] = [:]
    private var time: Float = 0
    private var duck: Float = 1
    private var rainResetTask: Task<Void, Never>?
    private var isDraggingSun = false
    /// The sun can only be moved during the opening ("drag the sun to start the day").
    private(set) var sunInteractive = false

    private struct LabelParts {
        let view: Entity
        let leader: ModelEntity
        let dot: ModelEntity
        var fade: Float = 0
        var lastOpacity: Float = -1
    }
    private var labelParts: [InfoLabel: LabelParts] = [:]
    private let leaderMesh = MeshResource.generateCylinder(height: 1, radius: 1)
    private let dotMesh = MeshResource.generateSphere(radius: 0.004)
    /// Opaque on purpose: opaque objects are drawn before the glass cards and depth-tested,
    /// so a card always covers its leader line (a transparent line was drawn on top of it).
    private let leaderMaterial = UnlitMaterial(color: UIColor(white: 0.85, alpha: 1))

    // MARK: - Building

    func build(showVirtualLandscape: Bool) {
        guard cloud == nil else { return }
        root.name = "LightningRoot"
        placeModel(position: Self.modelPosition, yaw: 0)
        root.addChild(modelRoot)

        let landscape = LandscapeEntity(showVirtual: showVirtualLandscape)
        modelRoot.addChild(landscape.entity)

        let effects = AtmosphereEffects()
        modelRoot.addChild(effects.entity)

        let cloud = StormCloud()
        cloud.entity.position = Self.cloudBase
        modelRoot.addChild(cloud.entity)

        let charged = ChargedCloudField(cloud: cloud)
        charged.onAbsorb = { [weak self] charge in
            self?.app?.director.handleAbsorb(charge)
        }
        charged.badgeForSlot = { [weak self] slot in self?.badges[slot] }
        charged.onSlotChanged = { [weak self] slot, charge in
            self?.app?.setSlotCharge(slot, charge)
        }
        modelRoot.addChild(charged.entity)

        let bolt = LightningBolt()
        modelRoot.addChild(bolt.entity)

        root.addChild(dimmer.entity)
        root.addChild(overcast.entity)

        self.landscape = landscape
        self.effects = effects
        self.cloud = cloud
        self.charged = charged
        self.bolt = bolt

        head.onObjectAnchor = { [weak self] transform in
            guard let self, !self.placing else { return }
            self.applyTrackedModel(transform)
        }
        if !showVirtualLandscape && Layout.useOcclusionMask { loadScanOcclusion() }
        head.onModelAnchor = { [weak self] transform in
            guard let self, !self.placing else { return }
            self.placeModel(matrix: transform)
            self.modelFound = true
        }
        isBuilt = true
    }

    // MARK: - Where the model is in the room

    private(set) var isBuilt = false
    private var objectFound = false
    private var scanEntity: Entity?

    /// Object tracking found the real model: snap to it the first time, then follow gently
    /// (tracking poses jitter by a few millimetres). Only the vertical rotation is used.
    func applyTrackedModel(_ anchor: simd_float4x4) {
        let m = anchor * Layout.scanAlignment.matrix
        let front = SIMD3<Float>(m.columns.2.x, 0, m.columns.2.z)
        let yaw = simd_length(front) > 0.01 ? atan2f(front.x, front.z) : 0
        let p = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        guard objectFound else {
            placeModel(position: p, yaw: yaw)
            objectFound = true
            return
        }
        let k = Layout.trackingSmoothing
        let currentFront = modelRoot.orientation.act([0, 0, 1])
        let currentYaw = atan2f(currentFront.x, currentFront.z)
        var delta = yaw - currentYaw
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        placeModel(position: modelRoot.position + (p - modelRoot.position) * k, yaw: currentYaw + delta * k)
    }

    func waitForTrackedModel(timeout: Double) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !objectFound && Date() < end {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return objectFound
    }

    /// The scan (`LandscapeScan.usdz`) as an exact, invisible mask: hides rain, lightning and
    /// clouds behind the real model. Replaces the slice-based mask when present.
    private func loadScanOcclusion() {
        Task { [weak self] in
            guard let scan = try? await Entity(named: "LandscapeScan") else { return }
            guard let self else { return }
            Self.applyOcclusion(to: scan)
            scan.transform = Transform(matrix: Layout.scanAlignment.matrix.inverse)
            self.modelRoot.addChild(scan)
            self.scanEntity = scan
            self.landscape?.entity.isEnabled = false
        }
    }

    private static func applyOcclusion(to entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { _ in OcclusionMaterial() as any RealityKit.Material }
            entity.components.set(model)
        }
        for child in entity.children { applyOcclusion(to: child) }
    }
    private(set) var placing = false
    private var modelFound = false
    private var ghost: Entity?
    private var modelDragOrigin: SIMD3<Float>?
    private var modelRotateOrigin: simd_quatf?

    /// Upright placement: position of the footprint centre + rotation about the vertical.
    func placeModel(position: SIMD3<Float>, yaw: Float) {
        modelRoot.position = position
        modelRoot.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        overcast.entity.position = [position.x, 0, position.z]
    }

    /// From a saved anchor; only the vertical rotation is used, so the model never tilts.
    func placeModel(matrix m: simd_float4x4) {
        let front = SIMD3<Float>(m.columns.2.x, 0, m.columns.2.z)
        let yaw = simd_length(front) > 0.01 ? atan2f(front.x, front.z) : 0
        placeModel(position: [m.columns.3.x, m.columns.3.y, m.columns.3.z], yaw: yaw)
    }

    /// Puts the model in front of the viewer, its front edge facing them.
    func placeInFrontOfViewer() async {
        var device: simd_float4x4?
        for _ in 0..<30 {
            if let d = head.deviceTransform() { device = d; break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let m = device else {
            placeModel(position: Layout.modelPosition, yaw: 0)
            return
        }
        let eye = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        var forward = SIMD3<Float>(-m.columns.2.x, 0, -m.columns.2.z)
        forward = simd_length(forward) > 0.1 ? simd_normalize(forward) : [0, 0, -1]
        var position = eye + forward * Layout.viewerDistance
        position.y = max(0.5, eye.y - Layout.baseBelowEyes)
        placeModel(position: position, yaw: atan2f(-forward.x, -forward.z))
    }

    /// Waits until visionOS reports the saved model position (relocalisation can take a moment).
    func waitForSavedModel(timeout: Double) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !modelFound && Date() < end {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return modelFound
    }

    func setPlacementMode(_ on: Bool) {
        placing = on
        if on && ghost == nil {
            let g = makeGhost()
            modelRoot.addChild(g)
            ghost = g
        }
        ghost?.isEnabled = on
        modelDragOrigin = nil
        modelRotateOrigin = nil
    }

    @discardableResult
    func saveModelPlacement() async -> Bool {
        modelFound = true
        return await head.saveModelAnchor(modelRoot.transformMatrix(relativeTo: nil))
    }

    func dragModel(to location: SIMD3<Float>, start: SIMD3<Float>) {
        guard placing else { return }
        if modelDragOrigin == nil { modelDragOrigin = modelRoot.position }
        let p = modelDragOrigin! + (location - start)
        modelRoot.position = p
        overcast.entity.position = [p.x, 0, p.z]
    }

    func endModelDrag() { modelDragOrigin = nil }

    func rotateModel(by yaw: Float) {
        guard placing else { return }
        if modelRotateOrigin == nil { modelRotateOrigin = modelRoot.orientation }
        modelRoot.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * modelRotateOrigin!
    }

    func endModelRotate() { modelRotateOrigin = nil }

    /// Fine adjustment buttons. `right` / `back` move along the model's own axes
    /// (as seen by a visitor standing at the front), so the arrows always match what you see.
    func nudgeModel(yaw: Float = 0, height: Float = 0, right: Float = 0, back: Float = 0) {
        guard placing else { return }
        modelRoot.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * modelRoot.orientation
        let move = modelRoot.orientation.act([right, 0, -back])
        modelRoot.position += SIMD3<Float>(move.x, height, move.z)
        overcast.entity.position = [modelRoot.position.x, 0, modelRoot.position.z]
    }

    /// Calibration model: a see-through copy of the landscape inside a wire box with the real
    /// model's outer dimensions (41 × 42 × 18 cm). Line up the box corners with the corners of
    /// the real slices, then the mountains. The orange edges mark the front (towards the visitors).
    private func makeGhost() -> Entity {
        let root = Entity()
        root.name = "PlacementGhost"
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.35, green: 0.8, blue: 1, alpha: 1))
        material.roughness = .init(floatLiteral: 0.6)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.5))
        if let mesh = try? LandscapeEntity.makeTerrainMesh() {
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }
        // Outer faces of the slice stack: the outermost slices add half a board on each side.
        let w = Terrain.width, d = Terrain.depth + 0.004, h = Terrain.maxHeight
        func edge(_ size: SIMD3<Float>, _ p: SIMD3<Float>, _ color: UIColor) {
            let e = ModelEntity(mesh: .generateBox(size: size), materials: [UnlitMaterial(color: color)])
            e.position = p
            root.addChild(e)
        }
        let t: Float = 0.003
        for y in [Float(0), h] {
            edge([w, t, t], [0, y, d / 2], .orange)                  // front, bottom and top
            edge([w, t, t], [0, y, -d / 2], .white)
            edge([t, t, d], [-w / 2, y, 0], .white)
            edge([t, t, d], [w / 2, y, 0], .white)
        }
        for x in [-w / 2, w / 2] {
            for z in [-d / 2, d / 2] {
                edge([t, h, t], [x, h / 2, z], z > 0 ? .orange : .white)   // corner posts
                let dot = ModelEntity(mesh: .generateSphere(radius: 0.007), materials: [UnlitMaterial(color: .yellow)])
                dot.position = [x, 0, z]                                   // bottom corners: line these up first
                root.addChild(dot)
            }
        }
        root.components.set(PlacementComponent())
        root.components.set(InputTargetComponent())
        root.components.set(CollisionComponent(shapes: [
            ShapeResource.generateBox(width: w, height: h, depth: d)
                .offsetBy(translation: [0, h / 2, 0])
        ]))
        root.isEnabled = false
        return root
    }

    /// The dashboard (storm bar / sun instruction / choice / controls) at `Layout.dashboard`,
    /// turned towards the viewer.
    func attachDashboard(_ entity: Entity) {
        entity.position = Layout.dashboard
        entity.components.set(BillboardComponent())
        modelRoot.addChild(entity)
        dashboardEntity = entity
    }

    /// Glass +/− badge for a charged-cloud slot (re-parented onto the cloud when it spawns).
    func attachBadge(slot: Int, _ entity: Entity) {
        badges[slot] = entity
    }

    func attachLabel(_ label: InfoLabel, view: Entity) {
        view.components.set(BillboardComponent())
        view.isEnabled = false
        let leader = ModelEntity(mesh: leaderMesh, materials: [leaderMaterial])
        let dot = ModelEntity(mesh: dotMesh, materials: [leaderMaterial])
        leader.isEnabled = false
        dot.isEnabled = false
        modelRoot.addChild(view)
        modelRoot.addChild(leader)
        modelRoot.addChild(dot)
        labelParts[label] = LabelParts(view: view, leader: leader, dot: dot)
    }


    func teardown() {
        rainResetTask?.cancel()
        charged?.deactivate()
        head.stop()
        root.removeFromParent()
    }

    /// Back to the very beginning (Restart).
    func resetAll() {
        rainResetTask?.cancel()
        charged?.deactivate()
        isPaused = false
        setSunInteractive(false)
        charged?.isFrozen = false
        cloud?.setPaused(false)
        flashLevel = 0
        stormRate = 1.1
        sunVisibleRate = 1.0
        root.setOpacity(1)
        target = AtmosphereState()
        current = AtmosphereState()
        cloud?.setChargeCounts(positive: 0, negative: 0)
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        charged?.isFrozen = paused
        cloud?.setPaused(paused)
    }

    // MARK: - Frame update

    func update(dt rawDt: Float) {
        guard let cloud, let effects, let charged else { return }
        let dt = min(max(rawDt, 0), 0.05)

        head.update(dt: dt)
        let camera = head.headPosition

        if isPaused {
            // Frozen picture.
            dimmer.update(darkness: current.storm, flash: 0, head: camera)
            return
        }

        time += dt

        // While the visitor moves the sun through the morning, the ground heats up
        // and warm air pockets start to rise – live.
        if sunInteractive {
            target.thermals = AtmosphereEffects.heat(for: current.sunProgress)
            let progress = (current.sunProgress - Script.sunrise) / (Script.sunDragGoal - Script.sunrise)
            app?.updateSunDragProgress(max(0, min(1, progress)))
        }
        let sunBefore = current.sunProgress
        current.approach(target, dt: dt, stormRate: stormRate, sunVisibleRate: sunVisibleRate)
        if sunInteractive {
            // The sun travels at most `maxSunSpeed`, however fast the hand moves.
            let limit = Self.maxSunSpeed * dt
            current.sunProgress = sunBefore + max(-limit, min(limit, current.sunProgress - sunBefore))
        }

        let cameraInModel = modelRoot.convert(position: camera, from: nil)
        effects.update(state: current, time: time, dt: dt, camera: cameraInModel)
        cloud.update(state: current, time: time, dt: dt, camera: camera)
        charged.update(time: time, dt: dt, camera: camera)
        updateLabels(dt: dt, camera: cameraInModel)

        dimmer.update(darkness: current.storm, flash: flashLevel, head: camera)
        // Grey cover gathers overhead as the storm nears its peak (and stays while it's dark).
        overcast.update(amount: ramp(current.storm, from: 0.25, to: 0.85), storm: current.storm,
                        flash: flashLevel, time: time, camera: camera)

        guard let app else { return }
        // Mix: 1 = original level. Lower a value to make that sound quieter.
        let windVolume: Float = 0.45
        let rainVolume: Float = 0.8
        let rumbleVolume: Float = 1.0
        // How quiet the ambience gets while the narrator speaks (0.5 = half, 0.25 = a quarter).
        let duckLevel: Float = 0.3

        duck += ((app.narration.isPlaying ? duckLevel : 1) - duck) * approachFactor(rate: 4, dt: dt)
        app.audio.set(
            rain: min(1, current.storm + current.rainPulse * 0.6) * duck * rainVolume,
            wind: min(1, 0.12 + 0.5 * current.wind + 0.35 * current.storm) * duck * windVolume,
            rumble: current.storm * current.storm * (0.4 + 0.6 * duck) * rumbleVolume
        )
    }

    // MARK: - Sun interaction

    func setSunInteractive(_ on: Bool) {
        sunInteractive = on
        effects?.sunInteractive = on
        if !on { isDraggingSun = false }
    }

    /// Called while the user drags the sun: it follows the hand along its path.
    func dragSun(to worldPosition: SIMD3<Float>) {
        guard sunInteractive, !isPaused, current.sunVisible > 0.3 else { return }
        isDraggingSun = true
        // Only the target follows the hand; the sun itself moves at a limited speed (see update).
        target.sunProgress = AtmosphereEffects.sunProgress(nearest: modelRoot.convert(position: worldPosition, from: nil))
    }

    func endSunDrag() {
        isDraggingSun = false
    }

    // MARK: - Info labels on the objects

    /// Point on the object a label explains (landscape-model space).
    private func anchor(for label: InfoLabel) -> SIMD3<Float>? {
        func ground(_ x: Float, _ z: Float) -> SIMD3<Float> { [x, Terrain.height(x, z), z] }
        switch label {
        case .sun: return effects?.sunPosition
        case .land: return ground(Terrain.landSpot.x, Terrain.landSpot.y)
        case .thermals:
            let spot = Terrain.hotSpots[min(1, Terrain.hotSpots.count - 1)]
            return ground(spot.x, spot.y) + SIMD3<Float>(0, 0.12, 0)
        case .slope: return ground(Terrain.slopeSpot.x, Terrain.slopeSpot.y) + SIMD3<Float>(0, 0.02, 0)
        case .condensation: return cloud?.modelPoint([0.5, 0.06, 0.5])
        case .updraft: return cloud?.modelPoint([0.5, 0.45, 0.5])
        case .freezing: return cloud?.modelPoint([0.65, 0.33, 0.5])
        case .anvil: return cloud?.modelPoint([0.85, 0.93, 0.5])
        case .droplets: return cloud?.modelPoint([0.55, 0.5, 0.5])
        case .iceCrystals: return cloud?.modelPoint([0.4, 0.85, 0.5])
        case .graupel: return cloud?.modelPoint([0.45, 0.36, 0.5])
        case .rain:
            guard let base = cloud?.modelPoint([0.5, 0.0, 0.5]) else { return nil }
            return base - SIMD3<Float>(0, 0.1, 0)
        }
    }

    /// Where the label floats relative to its anchor (model space, metres).
    private func offset(for label: InfoLabel) -> SIMD3<Float> {
        switch label {
        case .sun: return [0, 0.12, 0.04]
        case .land: return [0.12, 0.12, 0.08]
        case .thermals: return [0.2, 0.06, 0.06]
        case .slope: return [-0.26, 0.1, 0.12]
        case .condensation: return [0.3, -0.04, 0.08]
        case .updraft: return [0.32, 0.02, 0.08]
        case .freezing: return [0.3, -0.02, 0.1]
        case .anvil: return [0.22, 0.1, 0.08]
        case .droplets: return [0.34, 0.0, 0.08]
        case .iceCrystals: return [-0.36, 0.06, 0.08]
        case .graupel: return [-0.36, -0.02, 0.08]
        case .rain: return [0.26, -0.04, 0.1]
        }
    }

    private func updateLabels(dt: Float, camera: SIMD3<Float>) {
        guard let app else { return }
        let k = approachFactor(rate: 4, dt: dt)
        let focused = app.focusedLabel
        for label in InfoLabel.allCases {
            guard var parts = labelParts[label] else { continue }
            // In focus: full opacity. Shown earlier in this chapter: dimmed. Otherwise hidden.
            let goal: Float = app.visibleLabels.contains(label) ? (label == focused ? 1 : 0.35) : 0
            parts.fade += (goal - parts.fade) * k
            let shown = parts.fade > 0.02
            parts.view.isEnabled = shown
            parts.leader.isEnabled = shown
            parts.dot.isEnabled = shown
            if shown, let anchor = anchor(for: label) {
                let position = anchor + offset(for: label)
                parts.view.position = position
                parts.dot.position = anchor
                let opacity = (parts.fade * 40).rounded() / 40
                if opacity != parts.lastOpacity {
                    parts.lastOpacity = opacity
                    parts.view.setOpacity(opacity)
                    parts.dot.setOpacity(opacity)
                    parts.leader.setOpacity(opacity)
                }
                // Leader from the anchor to a point just *behind* the card (away from the viewer),
                // so it disappears under the glass instead of crossing over it.
                let toCamera = camera - position
                let cameraDistance = simd_length(toCamera)
                let back = cameraDistance > 1e-3 ? -toCamera / cameraDistance * 0.015 : .zero
                let end = position + back
                let length = simd_distance(anchor, end)
                if length > 0.001 {
                    var direction = (end - anchor) / length
                    if direction.y < 0 { direction = -direction }
                    parts.leader.position = (anchor + end) * 0.5
                    parts.leader.orientation = simd_quatf(from: [0, 1, 0], to: direction)
                    parts.leader.scale = [0.0008, length, 0.0008]
                }
            }
            labelParts[label] = parts
        }
    }

    // MARK: - Story hooks

    func resetForIntro() {
        target = AtmosphereState()
        current = AtmosphereState()
        stormRate = 1.1
        cloud?.setChargeCounts(positive: 14, negative: 14)
    }

    func enterPlayMode() {
        rainResetTask?.cancel()
        target.sunVisible = 1
        target.interior = 1
        target.separation = 1
        target.xray = 0.55
        target.rainPulse = 0
        target.windVisible = 0          // wind has no role after the intro
        target.moistAir = 0
        cloud?.setChargeCounts(positive: 0, negative: 0)
        setStormIntensity(0)
        target.thermals = 0
        charged?.activate()
    }

    /// The main feedback channel: size, darkness, wind, rain and sound all follow this.
    func setStormIntensity(_ intensity: Float) {
        stormRate = 1.1
        target.storm = intensity
        target.cloudGrowth = 0.6 + 0.4 * intensity
        target.anvil = 0.2 + 0.8 * intensity
        target.wind = 0.35 + 0.65 * intensity
    }

    /// Each absorbed charged cloud shows up as three charge carriers inside the storm.
    func setCharges(positive: Int, negative: Int) {
        cloud?.setChargeCounts(positive: positive * 3, negative: negative * 3)
    }

    func strike() async {
        guard let cloud, let bolt, let app else { return }

        // Build-up: flickering inside the cloud.
        for _ in 0..<3 {
            cloud.flash(duration: 0.12)
            try? await Task.sleep(for: .milliseconds(Int.random(in: 220...420)))
        }

        bolt.build(from: cloud.strikeOrigin, to: Terrain.strikePoint)

        let audio = app.audio
        Task {
            // Sound is slower than light.
            try? await Task.sleep(for: .milliseconds(650))
            audio.thunder()
        }

        await bolt.play { [weak self, weak app, weak cloud] level in
            self?.flashLevel = level
            app?.skyFlash = level
            cloud?.setGlow(level)
        }
        cloud.setGlow(0)
        flashLevel = 0
        app.skyFlash = 0
    }

    /// Right after the strike: charges are gone and the cloud shrinks a little,
    /// but it stays dark and keeps pouring while the narration explains what happened.
    func discharge() {
        rainResetTask?.cancel()
        cloud?.setChargeCounts(positive: 0, negative: 0)
        target.storm = 0.85
        target.cloudGrowth = 0.82
        target.anvil = 0.6
        target.wind = 0.8
        target.rainPulse = 0.6
    }

    /// After "Build another storm": the old storm slowly passes, the sky clears.
    /// (Until then it stays dark and raining.)
    func clearSkySlowly() {
        rainResetTask?.cancel()
        stormRate = 0.35
        target.storm = 0
        target.rainPulse = 0.3
        rainResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.target.rainPulse = 0
        }
    }

    // MARK: - Ending

    /// The storm dissolves, rain stops, the sky clears and the sun sets – slowly.
    func beginEnding() {
        rainResetTask?.cancel()
        charged?.deactivate()
        stormRate = 0.3
        sunVisibleRate = 0.25
        target.storm = 0
        target.rainPulse = 0
        target.wind = 0.15
        target.windVisible = 0
        target.moistAir = 0
        target.thermals = 0
        target.cloudGrowth = 0           // the cloud evaporates puff by puff
        target.anvil = 0
        target.interior = 0
        target.separation = 0
        target.xray = 0
        target.sunProgress = 0.97        // sunset …
        target.sunVisible = 0            // … and gone
    }

    /// Fades the whole scene out before the immersive space closes.
    func fadeOut(seconds: Double) async {
        let steps = max(1, Int(seconds * 30))
        for i in 1...steps {
            root.setOpacity(1 - Float(i) / Float(steps))
            try? await Task.sleep(for: .seconds(seconds / Double(steps)))
        }
    }
}
