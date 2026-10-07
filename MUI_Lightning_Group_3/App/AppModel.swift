//
//  AppModel.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import SwiftUI
import Observation

enum Phase: Equatable {
    case idle, intro, playing, lightning, afterStrike
}

enum ImmersiveSpaceState {
    case closed, inTransition, open
}

/// What the floating infographic next to the landscape shows.
enum InfographicFocus: Equatable {
    case hidden, overview, precipitation, charges, rain, game
}

@MainActor
@Observable
final class AppModel {
    static let startWindowID = "StartWindow"
    static let immersiveSpaceID = "LightningSpace"

    var immersiveSpaceState: ImmersiveSpaceState = .closed
    var phase: Phase = .idle
    var infographic: InfographicFocus = .hidden
    var showVirtualLandscape = true
    var stormsBuilt = 0

    /// 0 = clear sky, 1 = darkest storm. Drives the passthrough tint.
    private(set) var skyDarkness: Float = 0
    /// Brief brightening while lightning flashes.
    var skyFlash: Float = 0

    let game = StormGame()
    let director = StoryDirector()
    @ObservationIgnored private(set) var scene = SceneController()

    init() {
        scene.app = self
        director.app = self
    }

    func startExperience() {
        guard phase == .idle else { return }
        stormsBuilt = 0
        game.reset()
        director.startIntro()
    }

    /// Safe to call several times (stop button + space disappearing).
    func stopExperience() {
        director.cancel()
        scene.teardown()
        scene = SceneController()
        scene.app = self
        game.reset()
        phase = .idle
        infographic = .hidden
        skyDarkness = 0
        skyFlash = 0
    }

    func updateSky(darkness: Float) {
        // Quantised so SwiftUI isn't re-rendered every frame.
        let q = (darkness * 40).rounded() / 40
        if q != skyDarkness { skyDarkness = q }
    }
}
