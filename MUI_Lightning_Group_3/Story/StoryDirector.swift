//
//  StoryDirector.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import Foundation

/// Runs the chapters: fixed intro → interactive play → lightning → choice.
/// Silent version: chapters advance on timers instead of narration.
@MainActor
final class StoryDirector {
    weak var app: AppModel?

    private var task: Task<Void, Never>?

    func startIntro() {
        cancel()
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
        try? await Task.sleep(for: .seconds(1.2))

        for step in Script.intro {
            guard !Task.isCancelled else { return }
            step.apply(app.scene, app)
            try? await Task.sleep(for: .seconds(step.duration))
        }
        guard !Task.isCancelled else { return }
        beginPlay()
    }

    // MARK: - Interactive part

    func beginPlay() {
        guard let app else { return }
        app.phase = .playing
        app.game.reset()
        app.infographic = .game
        app.scene.enterPlayMode()
    }

    /// Called when a charged cloud was dropped into the storm.
    /// Feedback is purely visual: cloud size, darkness, rain, wind and the charge meter.
    func handleAbsorb(_ charge: Charge) {
        guard let app, app.phase == .playing else { return }
        app.game.add(charge)
        app.scene.setCharges(positive: app.game.positive, negative: app.game.negative)
        app.scene.setStormIntensity(app.game.intensity)
        if app.game.isReady {
            triggerLightning()
        }
    }

    // MARK: - Lightning

    private func triggerLightning() {
        guard let app else { return }
        app.phase = .lightning
        app.scene.charged?.deactivate()
        task?.cancel()
        task = Task { [weak self] in
            guard let app = self?.app else { return }
            try? await Task.sleep(for: .seconds(Script.beforeStrike))
            guard !Task.isCancelled else { return }

            await app.scene.strike()
            guard !Task.isCancelled else { return }

            app.stormsBuilt += 1
            app.game.reset()
            app.scene.discharge()
            try? await Task.sleep(for: .seconds(Script.afterStrike))
            guard !Task.isCancelled else { return }

            app.phase = .afterStrike
            app.scene.clearSky()
        }
    }

    func buildAnother() {
        guard let app, app.phase == .afterStrike else { return }
        task?.cancel()
        beginPlay()
    }
}
