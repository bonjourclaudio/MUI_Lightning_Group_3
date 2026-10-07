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
    var wind: Float = 0
    var cloudGrowth: Float = 0      // 0 = no cloud … 1 = full tower
    var anvil: Float = 0
    var interior: Float = 0         // show particles inside the cloud
    var separation: Float = 0       // 0 = mixed, 1 = + on top / − in the middle
    var xray: Float = 0             // cloud shell transparency
    var storm: Float = 0            // darkness, rain, sound
    var rainPulse: Float = 0        // extra rain for explanations

    mutating func approach(_ t: AtmosphereState, dt: Float, stormRate: Float = 1.1) {
        func step(_ value: inout Float, _ target: Float, _ rate: Float) {
            value += (target - value) * approachFactor(rate: rate, dt: dt)
        }
        step(&sunVisible, t.sunVisible, 1.0)
        step(&sunProgress, t.sunProgress, 0.35)
        step(&thermals, t.thermals, 0.8)
        step(&wind, t.wind, 0.8)
        step(&cloudGrowth, t.cloudGrowth, 0.45)
        step(&anvil, t.anvil, 0.5)
        step(&interior, t.interior, 1.2)
        step(&separation, t.separation, 0.5)
        step(&xray, t.xray, 1.2)
        step(&storm, t.storm, stormRate)
        step(&rainPulse, t.rainPulse, 1.5)
    }
}

@MainActor
final class SceneController {
    weak var app: AppModel?

    /// Where the (physical) landscape model stands, relative to the immersive-space
    /// origin (on the floor, below the user's start position). Metres.
    /// Adjust to the real table, or replace with object tracking (see README).
    static let modelPosition: SIMD3<Float> = [0, 0.9, -1.2]
    /// Base of the main cloud, relative to the landscape model.
    static let cloudBase: SIMD3<Float> = [0.05, 0.45, -0.06]

    var target = AtmosphereState()
    /// How fast the storm darkness follows its target (slower when the sky clears after a strike).
    private var stormRate: Float = 1.1
    private(set) var current = AtmosphereState()

    let root = Entity()
    let modelRoot = Entity()
    let head = HeadLockedFollower()

    private(set) var landscape: LandscapeEntity?
    private(set) var cloud: StormCloud?
    private(set) var effects: AtmosphereEffects?
    private(set) var charged: ChargedCloudField?
    private(set) var bolt: LightningBolt?

    private let dimmer = SkyDimmer()
    private var flashLevel: Float = 0
    private var infographicEntity: Entity?
    private var afterStrikeEntity: Entity?
    private var time: Float = 0
    private var rainResetTask: Task<Void, Never>?

    // MARK: - Building

    func build(showVirtualLandscape: Bool) {
        guard cloud == nil else { return }
        root.name = "LightningRoot"
        modelRoot.position = Self.modelPosition
        root.addChild(modelRoot)
        root.addChild(head.entity)

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
        modelRoot.addChild(charged.entity)

        let bolt = LightningBolt()
        modelRoot.addChild(bolt.entity)

        root.addChild(dimmer.entity)

        self.landscape = landscape
        self.effects = effects
        self.cloud = cloud
        self.charged = charged
        self.bolt = bolt
    }

    func attachHeadLocked(stop: Entity, hint: Entity) {
        head.add(stop, offset: [0.34, -0.30, -0.95])        // bottom right of the view
        head.add(hint, offset: [0, -0.40, -1.1])
    }

    func attachInfographic(_ entity: Entity) {
        entity.position = [-0.74, 0.55, 0.1]
        entity.components.set(BillboardComponent())
        entity.isEnabled = false
        modelRoot.addChild(entity)
        infographicEntity = entity
    }

    func attachAfterStrike(_ entity: Entity) {
        entity.position = [0, 0.26, 0.42]
        entity.components.set(BillboardComponent())
        entity.isEnabled = false
        modelRoot.addChild(entity)
        afterStrikeEntity = entity
    }

    func setUI(infographicVisible: Bool, afterStrikeVisible: Bool) {
        infographicEntity?.isEnabled = infographicVisible
        afterStrikeEntity?.isEnabled = afterStrikeVisible
    }

    func teardown() {
        rainResetTask?.cancel()
        charged?.deactivate()
        head.stop()
        root.removeFromParent()
    }

    // MARK: - Frame update

    func update(dt rawDt: Float) {
        guard let cloud, let effects, let charged else { return }
        let dt = min(max(rawDt, 0), 0.05)
        time += dt
        current.approach(target, dt: dt, stormRate: stormRate)

        head.update(dt: dt)
        let camera = head.headPosition
        let cameraInModel = modelRoot.convert(position: camera, from: nil)

        effects.update(state: current, time: time, dt: dt, camera: cameraInModel)
        cloud.update(state: current, time: time, dt: dt, camera: camera)
        charged.update(time: time, dt: dt, camera: camera)

        dimmer.update(darkness: current.storm, flash: flashLevel, head: camera)

        guard let app else { return }
        app.updateSky(darkness: current.storm)
    }

    // MARK: - Story hooks

    func resetForIntro() {
        target = AtmosphereState()
        current = AtmosphereState()
        cloud?.setChargeCounts(positive: 14, negative: 14)
    }

    func enterPlayMode() {
        rainResetTask?.cancel()
        target.sunVisible = 1
        target.sunProgress = 0.7
        target.thermals = 0.35
        target.interior = 1
        target.separation = 1
        target.xray = 0.55
        target.rainPulse = 0
        cloud?.setChargeCounts(positive: 0, negative: 0)
        setStormIntensity(0)
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

    /// When the restart / finish choice appears: the storm slowly passes, the sky clears.
    func clearSky() {
        rainResetTask?.cancel()
        stormRate = 0.35
        target.storm = 0
        target.cloudGrowth = 0.5
        target.anvil = 0.1
        target.wind = 0.35
        target.rainPulse = 0.3
        rainResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.target.rainPulse = 0
        }
    }
}
