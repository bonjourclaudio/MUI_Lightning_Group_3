//
//  Script.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import Foundation

/// One narrated line. Record it as `<id>.m4a` and put it into the `Narration` folder.
/// `text` is the narration script (not shown in the app).
struct NarrationLine: Sendable {
    let id: String
    let text: String

    init(_ id: String, _ text: String) {
        self.id = id
        self.text = text
    }
}

struct IntroStep {
    let line: NarrationLine
    /// Seconds the chapter lasts when there is no recording for it.
    let fallback: Double
    /// Sets scene targets and visible info labels. Everything animates smoothly.
    let apply: @MainActor (SceneController, AppModel) -> Void
}

enum Script {
    // MARK: - Fixed intro animation

    @MainActor static let intro: [IntroStep] = [
        IntroStep(line: .init("intro_01_welcome",
            "Welcome! In front of you is a landscape of mountains, valleys and open land. Let's watch how a thunderstorm is born."),
                  fallback: 5) { scene, app in
            scene.target.sunVisible = 1
            scene.target.sunProgress = Script.sunrise
            app.showLabels([])
        },
        // ← here the visitor drags the sun from sunrise to midday (see StoryDirector).
        IntroStep(line: .init("intro_02_sun",
            "The sun climbs higher and warms the ground. Bare rock and soil heat up quickly – much faster than the air above them."),
                  fallback: 7) { scene, app in
            scene.target.thermals = 0.6
            app.showLabels([.sun, .land])
        },
        IntroStep(line: .init("intro_03_thermals",
            "Above the warm ground, pockets of air heat up. Warm air is lighter than the cooler air around it, so it starts to rise – like a hot-air balloon."),
                  fallback: 8) { scene, app in
            scene.target.thermals = 1
            app.showLabels([.thermals])
        },
        IntroStep(line: .init("intro_04_wind",
            "At the same time, wind carries moist air from the lowlands towards the mountains. The slopes force the air upwards."),
                  fallback: 7) { scene, app in
            scene.target.wind = 1
            scene.target.windVisible = 1       // wind lines: only in the intro
            scene.target.moistAir = 1          // blue moist air: only while the wind chapter plays
            app.showLabels([.slope])
        },
        IntroStep(line: .init("intro_05_condense",
            "The higher the air rises, the colder it gets. At some point the water vapour condenses into countless tiny droplets – a cloud is born."),
                  fallback: 8) { scene, app in
            scene.target.cloudGrowth = 0.38
            scene.target.moistAir = 0          // the moist air has arrived – it condenses into the cloud
            scene.target.sunProgress = max(scene.current.sunProgress, 0.55)
            app.showLabels([.condensation])
        },
        IntroStep(line: .init("intro_06_tower",
            "Fed by warm, rising air, the cloud keeps growing. It towers up far above the level where water freezes."),
                  fallback: 7) { scene, app in
            scene.target.cloudGrowth = 0.8
            scene.target.thermals = 0          // warm air pockets only during the morning
            app.showLabels([.updraft, .freezing])
        },
        IntroStep(line: .init("intro_07_anvil",
            "At about ten to twelve kilometres the rising air reaches the tropopause – a layer it cannot break through. The top spreads out sideways into an anvil. Now it is a cumulonimbus: a thunderstorm cloud."),
                  fallback: 10) { scene, app in
            scene.target.cloudGrowth = 1
            scene.target.anvil = 1
            scene.target.sunProgress = max(scene.current.sunProgress, 0.62)
            app.showLabels([.anvil, .freezing])
        },
        IntroStep(line: .init("intro_08_inside",
            "Let's look inside. Strong updrafts whirl water droplets, ice crystals and soft hail pellets – called graupel – up and down."),
                  fallback: 8) { scene, app in
            scene.target.xray = 1
            scene.target.interior = 1
            app.showLabels([.droplets, .iceCrystals, .graupel])
        },
        IntroStep(line: .init("intro_09_charge",
            "When light ice crystals collide with heavier graupel, electric charge is transferred. The small ice crystals become positive and are carried to the top. The heavy graupel becomes negative and gathers in the middle of the cloud."),
                  fallback: 11) { scene, app in
            scene.target.separation = 1
            app.showLabels([.iceCrystals, .graupel])
        },
        IntroStep(line: .init("intro_10_rain",
            "Graupel and hail that grow too heavy fall out of the cloud. On the way down they melt and reach the ground as rain – or, in strong storms, as hail."),
                  fallback: 8) { scene, app in
            scene.target.rainPulse = 1
            app.showLabels([.rain])
        },
        IntroStep(line: .init("intro_11_your_turn",
            "Now it's your turn! Charged clouds are appearing around the storm. Drag them into the big cloud. The storm needs both positive and negative charge – only then can it build up enough tension for lightning."),
                  fallback: 9) { scene, app in
            scene.target.rainPulse = 0
            scene.target.cloudGrowth = 0.6
            scene.target.anvil = 0.2
            scene.cloud?.setChargeCounts(positive: 0, negative: 0)
            app.showLabels([])
        },
    ]

    /// Sun progress at sunrise (start of the drag) and the point that counts as midday.
    static let sunrise: Float = 0.06
    static let sunDragGoal: Float = 0.45

    /// Shown with the instruction card while the visitor drags the sun.
    static let dragSun = NarrationLine("intro_01b_drag_sun",
        "Take the sun and move it across the sky. Pinch it and drag it along the white line – and watch what happens to the ground.")

    /// Scene state at the end of the intro – used by "Skip intro".
    @MainActor static func applyEndOfIntro(_ scene: SceneController) {
        scene.target.sunVisible = 1
        scene.target.sunProgress = max(scene.current.sunProgress, 0.62)
        scene.target.wind = 1
        scene.target.windVisible = 0
        scene.target.moistAir = 0
        scene.target.thermals = 0
        scene.target.interior = 1
        scene.target.separation = 1
        scene.target.xray = 1
        scene.target.rainPulse = 0
        scene.target.cloudGrowth = 0.6
        scene.target.anvil = 0.2
    }

    // MARK: - Interactive feedback (played only if recorded, never blocking)

    static let good: [NarrationLine] = [
        .init("play_good_1", "Yes! The charges separate – the storm gains energy."),
        .init("play_good_2", "The cloud grows darker and taller."),
        .init("play_good_3", "Listen – the storm is getting stronger."),
    ]

    static let bad: [NarrationLine] = [
        .init("play_bad_1", "Too much of the same charge – the storm loses energy and the sky clears."),
        .init("play_bad_2", "Unbalanced! Try the opposite charge."),
    ]

    static let needBoth = NarrationLine("play_need_both",
        "One kind of charge alone is not enough. A thunderstorm needs both positive and negative charge.")

    // MARK: - Lightning

    static let breakdown = NarrationLine("strike_01_breakdown",
        "So much charge has built up that the air can no longer insulate it. Watch out…")
    static let breakdownFallback: Double = 2.5

    static let afterStrike = NarrationLine("strike_02_after",
        "Lightning! In a fraction of a second it equalises the charge. It heats the air to around thirty thousand degrees – the air expands explosively, and we hear thunder. The cloud has discharged and becomes smaller.")
    static let afterStrikeFallback: Double = 8

    static let choice = NarrationLine("strike_03_choice",
        "You can build another thunderstorm – or end the experience.")

    static let again = NarrationLine("play_again",
        "Let's build another storm. Bring positive and negative charge together.")

    /// Ending: how long the storm takes to dissolve and the sun to set, then the final fade.
    static let endingDuration: Double = 8
    static let fadeOutDuration: Double = 2.5

    static let outro = NarrationLine("outro",
        "Thank you! Next time you see a thunderstorm, you'll know what's happening inside the cloud.")
}
