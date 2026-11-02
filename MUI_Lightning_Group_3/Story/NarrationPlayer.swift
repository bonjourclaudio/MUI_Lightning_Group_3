//
//  NarrationPlayer.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import AVFoundation

/// Plays your recorded narration.
///
/// Put audio files named after the line id (e.g. `intro_01_welcome.m4a`, also .mp3/.wav/.caf)
/// into the `Narration` folder. If a file is missing, the step simply lasts its
/// fallback duration from `Script.swift` – the app works with or without recordings.
@MainActor
final class NarrationPlayer {
    private weak var app: AppModel?
    private let callbacks = NarrationCallbacks()
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?

    init() {
        callbacks.onFinish = { [weak self] finished in
            guard let self, finished === self.player else { return }
            self.complete()
        }
    }

    var isPlaying: Bool { player != nil }

    /// Plays the line and returns when it is done. Without a recording it waits `fallback`
    /// seconds. Both respect pause (via `app.wait`).
    func play(_ line: NarrationLine, fallback: Double, app: AppModel) async {
        interrupt()
        guard let url = Self.recordingURL(for: line.id),
              let audioPlayer = try? AVAudioPlayer(contentsOf: url) else {
            await app.wait(fallback)
            return
        }
        audioPlayer.delegate = callbacks
        player = audioPlayer
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuation = continuation
                audioPlayer.play()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.interrupt() }
        }
    }

    /// Short feedback line during play: only if recorded and nothing else is playing.
    func playIfIdle(_ line: NarrationLine) {
        guard player == nil, let url = Self.recordingURL(for: line.id),
              let audioPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        audioPlayer.delegate = callbacks
        player = audioPlayer
        audioPlayer.play()
    }

    func pause() { player?.pause() }
    func resume() { player?.play() }

    func interrupt() {
        player?.stop()
        complete()
    }

    func stop() { interrupt() }

    private func complete() {
        player = nil
        let waiting = continuation
        continuation = nil
        waiting?.resume()
    }

    /// Length of the recording for a line, if there is one.
    static func duration(of line: NarrationLine) -> Double? {
        guard let url = recordingURL(for: line.id),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        return player.duration
    }

    static func recordingURL(for id: String) -> URL? {
        for ext in ["m4a", "mp3", "wav", "caf"] {
            if let url = Bundle.main.url(forResource: id, withExtension: ext)
                ?? Bundle.main.url(forResource: id, withExtension: ext, subdirectory: "Narration") {
                return url
            }
        }
        return nil
    }
}

/// Delegate bridge (AVFoundation calls this off the main actor).
final class NarrationCallbacks: NSObject, AVAudioPlayerDelegate {
    var onFinish: (@MainActor (AVAudioPlayer) -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let callback = onFinish
        DispatchQueue.main.async {
            MainActor.assumeIsolated { callback?(player) }
        }
    }
}
