//
//  AppModel.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI
import Observation

enum Phase: Equatable {
    case idle, locating, placing, intro, playing, lightning, afterStrike, ending
}

enum ImmersiveSpaceState {
    case closed, inTransition, open
}

@MainActor
@Observable
final class AppModel {
    static let startWindowID = "StartWindow"
    static let immersiveSpaceID = "LightningSpace"

    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var phase: Phase = .idle
    /// Chosen in the start window: virtual landscape, or the physical model on the table.
    var showVirtualLandscape = true
    /// Start window → "Place the model again": ignore the saved position this time.
    var forcePlacement = false
    var stormsBuilt = 0

    /// Info labels on the objects, in the order they appeared in the current chapter.
    /// The newest one is in focus; earlier ones are dimmed.
    private(set) var visibleLabels: [InfoLabel] = []
    var focusedLabel: InfoLabel? { visibleLabels.last }
    /// Length of the current chapter (recording or fallback) – labels are spread across it.
    @ObservationIgnored var chapterDuration: Double = 6
    @ObservationIgnored private var revealTask: Task<Void, Never>?

    /// Paused: scene, story timers, narration and sound stand still.
    private(set) var isPaused = false

    /// Opening: waiting for the visitor to drag the sun from sunrise to midday.
    var awaitingSunDrag = false
    /// 0…1 – how far the sun has been dragged towards midday (for the instruction card).
    private(set) var sunDragProgress: Float = 0
    /// 0…1 – storm energy from the charge balance. Lightning at 1.
    private(set) var stormLevel: Float = 0

    /// Charge shown on each charged-cloud slot (nil = empty slot).
    private(set) var slotCharges: [Charge?] = Array(repeating: nil, count: ChargedCloudField.slotCount)

    func setSlotCharge(_ slot: Int, _ charge: Charge?) {
        guard slot >= 0, slot < slotCharges.count, slotCharges[slot] != charge else { return }
        slotCharges[slot] = charge
    }

    /// Brief brightening while lightning flashes.
    var skyFlash: Float = 0

    let game = StormGame()
    let narration = NarrationPlayer()
    let audio = AmbienceEngine()
    let director = StoryDirector()
    @ObservationIgnored private(set) var scene = SceneController()

    init() {
        scene.app = self
        director.app = self
    }

    // MARK: - Lifecycle

    /// Runs when the immersive space opens: puts the landscape where it belongs, then starts.
    /// - Virtual landscape: in front of the viewer.
    /// - Physical model: at the saved room position; if there is none (or it can't be found),
    ///   the team places it first.
    func beginSession() async {
        let scene = self.scene
        for _ in 0..<60 where !scene.isBuilt {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await scene.head.start(objectTracking: !showVirtualLandscape && Layout.useObjectTracking)

        if showVirtualLandscape {
            await scene.placeInFrontOfViewer()
            startExperience()
            return
        }
        // 1. Object tracking (scan): the Vision Pro recognises the real model.
        if !forcePlacement && scene.head.usesObjectTracking {
            phase = .locating
            if await scene.waitForTrackedModel(timeout: 20) {
                phase = .idle
                startExperience()
                return
            }
        }
        // 2. Fallback: position saved by hand in this room.
        if !forcePlacement && HeadLockedFollower.hasSavedModel {
            phase = .locating
            if await scene.waitForSavedModel(timeout: 8) {
                phase = .idle
                startExperience()
                return
            }
        }
        forcePlacement = false
        await scene.placeInFrontOfViewer()
        phase = .placing
        scene.setPlacementMode(true)
    }

    /// "Save position": remember where the model is and start.
    func finishPlacement() async {
        guard phase == .placing else { return }
        scene.setPlacementMode(false)
        await scene.saveModelPlacement()
        phase = .idle
        startExperience()
    }

    func startExperience() {
        guard phase == .idle else { return }
        stormsBuilt = 0
        game.reset()
        audio.start()
        director.startIntro()
    }

    /// Safe to call several times (end button + space disappearing).
    func stopExperience() {
        director.cancel()
        narration.stop()
        audio.stop()
        scene.teardown()
        scene = SceneController()
        scene.app = self
        resetState()
    }

    /// Back to the beginning of the intro without leaving the immersive space.
    func restartExperience() {
        if isPaused { resume() }
        director.cancel()
        narration.stop()
        scene.resetAll()
        resetState()
        startExperience()
    }

    private func resetState() {
        game.reset()
        phase = .idle
        revealTask?.cancel()
        visibleLabels = []
        isPaused = false
        awaitingSunDrag = false
        sunDragProgress = 0
        skipRequested = false
        slotCharges = Array(repeating: nil, count: ChargedCloudField.slotCount)
        stormLevel = 0
        skyFlash = 0
    }

    // MARK: - Pause

    func togglePause() {
        isPaused ? resume() : pause()
    }

    func pause() {
        guard !isPaused, ![.idle, .locating, .placing, .ending].contains(phase) else { return }
        isPaused = true
        narration.pause()
        audio.pause()
        scene.setPaused(true)
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        narration.resume()
        audio.resume()
        scene.setPaused(false)
    }

    // MARK: - Next step

    /// Set by the "Next step" button: the current chapter ends right away.
    @ObservationIgnored private(set) var skipRequested = false

    func requestNextStep() {
        guard phase == .intro, !isPaused else { return }
        skipRequested = true
        narration.interrupt()
    }

    func clearSkipRequest() {
        skipRequested = false
    }

    // MARK: - Info labels, one after another

    /// Shows the labels of a chapter one by one, spread across the chapter.
    /// The labels of the previous chapter fade out first.
    func showLabels(_ list: [InfoLabel]) {
        revealTask?.cancel()
        visibleLabels = []
        guard !list.isEmpty else { return }
        let interval = max(1.4, min(3.2, chapterDuration * 0.75 / Double(list.count)))
        revealTask = Task { [weak self] in
            guard let self else { return }
            await self.wait(0.7, skippable: false)
            for (index, label) in list.enumerated() {
                guard !Task.isCancelled else { return }
                self.visibleLabels.append(label)
                if index < list.count - 1 { await self.wait(interval, skippable: false) }
            }
        }
    }

    /// Waits `seconds` of *unpaused* time. Ends early on "Next step" (if skippable). Cancellable.
    func wait(_ seconds: Double, skippable: Bool = true) async {
        var remaining = seconds
        while remaining > 0, !Task.isCancelled, !(skippable && skipRequested) {
            let step = min(0.05, remaining)
            try? await Task.sleep(for: .seconds(step))
            if !isPaused { remaining -= step }
        }
    }

    // MARK: - Values from the scene

    func updateSunDragProgress(_ value: Float) {
        let q = (value * 50).rounded() / 50
        if q != sunDragProgress { sunDragProgress = q }
    }

    func updateStormLevel(_ value: Float) {
        stormLevel = value
    }
}
