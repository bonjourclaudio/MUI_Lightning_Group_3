//
//  StoryDirector.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import Foundation

/// Runs the chapters: fixed intro → interactive play → lightning → choice.
/// Each chapter lasts as long as its recorded narration (or its fallback duration).
@MainActor
final class StoryDirector {
    weak var app: AppModel?

    private var task: Task<Void, Never>?
    private var lastFeedback = Date.distantPast
    private var hintedSingleCharge = false

    func startIntro() {
        cancel()
        hintedSingleCharge = false
        task = Task { [weak self] in await self?.runIntro() }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - Intro

    private func runIntro() async {
        guard let app else { return }
        app.phase = .intro
        app.scene.resetForIntro()
        await app.wait(1.2)

        for (index, step) in Script.intro.enumerated() {
            guard !Task.isCancelled else { return }
            app.clearSkipRequest()
            app.chapterDuration = NarrationPlayer.duration(of: step.line) ?? step.fallback
            step.apply(app.scene, app)
            await app.narration.play(step.line, fallback: step.fallback, app: app)
            guard !Task.isCancelled else { return }
            await app.wait(0.6)
            if index == 0 {
                await waitForSunDrag()
                guard !Task.isCancelled else { return }
            }
        }
        guard !Task.isCancelled else { return }
        app.clearSkipRequest()
        beginPlay()
    }

    /// Opening interaction: the story only continues once the visitor has dragged
    /// the sun from sunrise to midday. While dragging, warm air starts to rise.
    private func waitForSunDrag() async {
        guard let app else { return }
        app.awaitingSunDrag = true
        app.scene.setSunInteractive(true)
        let instruction = Task { await app.narration.play(Script.dragSun, fallback: 0, app: app) }
        app.clearSkipRequest()
        while !Task.isCancelled, app.scene.current.sunProgress < Script.sunDragGoal {
            if app.skipRequested {
                // "Next step": the sun moves to midday by itself (no speed limit).
                app.scene.setSunInteractive(false)
                app.scene.target.sunProgress = Script.sunDragGoal + 0.05
                break
            }
            await app.wait(0.1)
        }
        app.clearSkipRequest()
        instruction.cancel()
        app.narration.stop()
        app.scene.setSunInteractive(false)
        app.awaitingSunDrag = false
        await app.wait(0.8)
    }

    /// Jumps straight to the interactive part.
    func skipIntro() {
        guard let app, app.phase == .intro else { return }
        cancel()
        app.narration.stop()
        app.awaitingSunDrag = false
        app.scene.setSunInteractive(false)
        Script.applyEndOfIntro(app.scene)
        app.scene.cloud?.setChargeCounts(positive: 0, negative: 0)
        app.showLabels([])
        beginPlay()
    }

    // MARK: - Interactive part

    func beginPlay() {
        guard let app else { return }
        app.phase = .playing
        app.game.reset()
        app.showLabels([])
        app.scene.enterPlayMode()
        updateStorm()
    }

    /// Storm energy from the charge balance (the sun has no influence any more once
    /// the anvil has formed).
    private func updateStorm() {
        guard let app else { return }
        let level = app.game.intensity
        app.updateStormLevel(level)
        app.scene.setStormIntensity(level)
        app.scene.setCharges(positive: app.game.positive, negative: app.game.negative)
    }

    /// Called when a charged cloud was dropped into the storm.
    func handleAbsorb(_ charge: Charge) {
        guard let app, app.phase == .playing else { return }
        let result = app.game.add(charge)
        updateStorm()

        // Immediate confirmation: sound + the storm lights up and swells briefly.
        let good = result != .weaker
        app.audio.chime(good: good)
        app.scene.cloud?.absorbFeedback(good: good)

        if app.stormLevel >= 0.999 {
            triggerLightning()
            return
        }
        switch result {
        case .stronger:
            feedback(Script.good.randomElement()!)
        case .weaker:
            feedback(Script.bad.randomElement()!, ignoreThrottle: true)
        case .unchanged:
            if app.game.imbalance != 0, !hintedSingleCharge {
                hintedSingleCharge = true
                feedback(Script.needBoth, ignoreThrottle: true)
            }
        }
    }

    private func feedback(_ line: NarrationLine, ignoreThrottle: Bool = false) {
        guard let app else { return }
        let now = Date()
        guard ignoreThrottle || now.timeIntervalSince(lastFeedback) > 7 else { return }
        lastFeedback = now
        app.narration.playIfIdle(line)
    }

    // MARK: - Lightning

    private func triggerLightning() {
        guard let app else { return }
        app.phase = .lightning
        app.scene.charged?.deactivate()
        task?.cancel()
        task = Task { [weak self] in
            guard let app = self?.app else { return }
            await app.narration.play(Script.breakdown, fallback: Script.breakdownFallback, app: app)
            guard !Task.isCancelled else { return }

            await app.scene.strike()
            guard !Task.isCancelled else { return }

            app.stormsBuilt += 1
            app.game.reset()
            app.updateStormLevel(0)
            app.scene.discharge()
            await app.narration.play(Script.afterStrike, fallback: Script.afterStrikeFallback, app: app)
            guard !Task.isCancelled else { return }

            // Stays dark and raining until the visitor chooses.
            app.phase = .afterStrike
            await app.narration.play(Script.choice, fallback: 0, app: app)
        }
    }

    func buildAnother() {
        guard let app, app.phase == .afterStrike else { return }
        task?.cancel()
        app.narration.stop()
        beginPlay()
        app.scene.clearSkySlowly()      // the old storm passes while the new game starts
        app.narration.playIfIdle(Script.again)
    }

    // MARK: - Ending

    /// A calm ending instead of a cut: the storm dissolves, the rain stops, the sky clears and
    /// the sun sets while the outro plays; then a thank-you card, then everything fades out.
    func playEnding() async {
        guard let app else { return }
        task?.cancel()
        app.narration.stop()
        app.phase = .ending
        app.showLabels([])
        app.scene.beginEnding()
        app.audio.fade(to: 0.35, seconds: 6)

        async let outro: Void = app.narration.play(Script.outro, fallback: 0, app: app)
        await app.wait(Script.endingDuration, skippable: false)
        await outro

        app.audio.fade(to: 0, seconds: Script.fadeOutDuration)
        await app.scene.fadeOut(seconds: Script.fadeOutDuration)
    }
}
