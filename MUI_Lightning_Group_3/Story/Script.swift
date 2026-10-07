//
//  Script.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import Foundation

/// One chapter of the fixed intro animation. Silent version: no narration –
/// each chapter is shown for `duration` seconds, then the next one starts.
struct IntroStep {
    /// What the chapter shows (for the team; not displayed in the app).
    let note: String
    let duration: Double
    /// Sets the scene targets for this chapter. Everything animates smoothly towards them.
    let apply: @MainActor (SceneController, AppModel) -> Void
}

enum Script {
    // MARK: - Fixed intro animation

    @MainActor static let intro: [IntroStep] = [
        IntroStep(note: "Landscape, sun rises", duration: 5) { scene, _ in
            scene.target.sunVisible = 1
            scene.target.sunProgress = 0.12
        },
        IntroStep(note: "Sun warms the ground – land heats faster than the lake", duration: 6) { scene, _ in
            scene.target.sunProgress = 0.38
            scene.target.thermals = 0.35
        },
        IntroStep(note: "Warm air pockets rise", duration: 7) { scene, _ in
            scene.target.thermals = 1
        },
        IntroStep(note: "Wind carries moist lake air up the mountain slopes", duration: 6) { scene, _ in
            scene.target.wind = 1
        },
        IntroStep(note: "Air cools, water vapour condenses – a cloud forms", duration: 7) { scene, _ in
            scene.target.cloudGrowth = 0.38
            scene.target.sunProgress = 0.5
        },
        IntroStep(note: "The cloud towers up above the freezing level", duration: 6) { scene, _ in
            scene.target.cloudGrowth = 0.8
        },
        IntroStep(note: "Tropopause reached – anvil, cumulonimbus", duration: 8) { scene, app in
            scene.target.cloudGrowth = 1
            scene.target.anvil = 1
            scene.target.sunProgress = 0.62
            app.infographic = .overview
        },
        IntroStep(note: "Inside: droplets, ice crystals and graupel whirl up and down", duration: 7) { scene, app in
            scene.target.xray = 1
            scene.target.interior = 1
            scene.target.thermals = 0.5
            app.infographic = .precipitation
        },
        IntroStep(note: "Collisions separate charge: ice crystals + on top, graupel − in the middle", duration: 9) { scene, app in
            scene.target.separation = 1
            app.infographic = .charges
        },
        IntroStep(note: "Heavy graupel and hail fall, melt into rain", duration: 7) { scene, app in
            scene.target.rainPulse = 1
            app.infographic = .rain
        },
        IntroStep(note: "Your turn – charged clouds appear", duration: 4) { scene, app in
            scene.target.rainPulse = 0
            scene.target.cloudGrowth = 0.6
            scene.target.anvil = 0.2
            scene.cloud?.setChargeCounts(positive: 0, negative: 0)
            app.infographic = .game
        },
    ]

    // MARK: - Lightning timing (seconds)

    /// Tension builds before the strike.
    static let beforeStrike: Double = 2.5
    /// The storm stays dark and pours after the strike, before the choice appears.
    static let afterStrike: Double = 8
}
