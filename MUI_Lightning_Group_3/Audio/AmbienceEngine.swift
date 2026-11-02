//
//  AmbienceEngine.swift
//  MUI_Lightning_Group_3
//
//  Author: MUI group 3
//

import AVFoundation

/// Procedural storm ambience (wind, rain, rumble, thunder) – no audio assets needed.
/// Replace with recorded, spatial audio (RealityKit `SpatialAudioComponent`) for the final piece.
@MainActor
final class AmbienceEngine {
    private var engine: AVAudioEngine?
    private let parameters = AmbienceParameters()

    func start() {
        guard engine == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        let engine = AVAudioEngine()
        var sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if sampleRate <= 0 { sampleRate = 48_000 }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }

        let source = Self.makeSourceNode(format: format, sampleRate: sampleRate, parameters: parameters)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            self.engine = engine
        } catch {
            print("[Ambience] Audio engine failed to start: \(error)")
        }
    }

    func pause() {
        engine?.pause()
    }

    func resume() {
        guard let engine, !engine.isRunning else { return }
        try? engine.start()
    }

    func stop() {
        engine?.stop()
        engine = nil
        parameters.rain = 0
        parameters.wind = 0
        parameters.rumble = 0
        parameters.masterTarget = 0.9
        parameters.fadeSeconds = 0.05
    }

    func set(rain: Float, wind: Float, rumble: Float) {
        parameters.rain = rain
        parameters.wind = wind
        parameters.rumble = rumble
    }

    func thunder() {
        parameters.thunderRequests += 1
    }

    /// Confirmation when a charged cloud is absorbed: rising two-note chime (good) or a low,
    /// falling one (wrong charge), each with a soft whoosh.
    func chime(good: Bool) {
        parameters.chimeGood = good
        parameters.chimeRequests += 1
    }

    /// Smoothly changes the overall volume (1 = normal) – used for the ending.
    func fade(to level: Float, seconds: Double) {
        parameters.fadeSeconds = Float(max(0.05, seconds))
        parameters.masterTarget = 0.9 * level
    }

    /// Built outside the main actor: the render block runs on the real-time audio thread.
    nonisolated private static func makeSourceNode(format: AVAudioFormat, sampleRate: Double, parameters: AmbienceParameters) -> AVAudioSourceNode {
        let dsp = AmbienceDSP(sampleRate: sampleRate)
        return AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            dsp.render(parameters, frames: Int(frameCount), buffers: UnsafeMutableAudioBufferListPointer(bufferList))
            return noErr
        }
    }
}

/// Written on the main thread, read on the audio thread.
/// Plain floats are fine for a prototype; use atomics in production.
final class AmbienceParameters: @unchecked Sendable {
    var rain: Float = 0
    var wind: Float = 0
    var rumble: Float = 0
    var thunderRequests = 0
    var chimeRequests = 0
    var chimeGood = true
    var masterTarget: Float = 0.9
    var fadeSeconds: Float = 0.05
}

/// Real-time synthesis. No fixed-period modulation anywhere: gusts and rolling thunder
/// follow random targets, so nothing swells and fades in a regular "sea wave" rhythm.
final class AmbienceDSP: @unchecked Sendable {
    private let sampleRate: Float
    private let smoothing: Float
    private let thunderDecay: Float
    private let crackleDecay: Float
    private let gustSlew: Float
    private let pitchSlew: Float

    private var seed: UInt32 = 0x1234_5678
    private var rain: Float = 0
    private var wind: Float = 0
    private var rumble: Float = 0

    // Wind: band-pass filtered noise (state-variable filter) with random gusts.
    private var windLow: Float = 0
    private var windBand: Float = 0
    private var windFreq: Float = 380
    private var windFreqTarget: Float = 380
    private var gust: Float = 0.8
    private var gustTarget: Float = 0.8
    private var gustTimer = 0

    // Rain: steady high-passed hiss + many tiny drop clicks.
    private var rainLowL: Float = 0
    private var rainLowR: Float = 0
    private var dropL: Float = 0
    private var dropR: Float = 0

    // Low rumble: twice low-passed noise (no random walk → no slow swells).
    private var low1: Float = 0
    private var low2: Float = 0

    // Thunder: crack + long rolling rumble with random rolls.
    private var thunderEnvelope: Float = 0
    private var crackleEnvelope: Float = 0
    private var crackleHigh: Float = 0
    private var roll: Float = 1
    private var rollTarget: Float = 1
    private var rollTimer = 0
    private var handledThunder = 0
    // Thunder mid band: audible on small speakers (Vision Pro can't reproduce deep bass).
    private var mid1: Float = 0
    private var mid2: Float = 0
    // Second, delayed boom (echo from the mountains).
    private var echoCountdown = 0
    private var echoEnvelope: Float = 0

    // Chime + whoosh.
    private var handledChime = 0
    private var notes: [(freq: Float, phase: Float, env: Float, delay: Int)] = []
    private var whooshEnvelope: Float = 0
    private var whooshAttack: Float = 0
    private var whooshBand: Float = 0
    private var whooshLow: Float = 0

    private var master: Float = 0.9

    init(sampleRate: Double) {
        let sr = Float(sampleRate)
        self.sampleRate = sr
        smoothing = 1 / (sr * 0.4)
        thunderDecay = powf(0.001, 1 / (sr * 10))          // long, rolling tail
        crackleDecay = powf(0.001, 1 / (sr * 0.5))
        gustSlew = 1 / (sr * 0.7)
        pitchSlew = 1 / (sr * 1.2)
    }

    @inline(__always) private func noise() -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(Int32(bitPattern: seed)) / Float(Int32.max)
    }

    @inline(__always) private func random01() -> Float {
        noise() * 0.5 + 0.5
    }

    func render(_ p: AmbienceParameters, frames: Int, buffers: UnsafeMutableAudioBufferListPointer) {
        if p.thunderRequests != handledThunder {
            handledThunder = p.thunderRequests
            thunderEnvelope = 1
            crackleEnvelope = 1
            echoCountdown = Int(sampleRate * 1.4)
        }
        if p.chimeRequests != handledChime {
            handledChime = p.chimeRequests
            let delay = Int(sampleRate * (p.chimeGood ? 0.09 : 0.13))
            notes = p.chimeGood
                ? [(880, 0, 1, 0), (1318.5, 0, 1, delay)]      // A5 → E6, rising
                : [(392, 0, 1, 0), (293.7, 0, 1, delay)]       // G4 → D4, falling
            whooshEnvelope = 0
            whooshAttack = 1
        }
        let masterCoefficient = 1 / (sampleRate * p.fadeSeconds)
        let noteDecay = powf(0.001, 1 / (sampleRate * 0.55))
        let midCoefficient = 2 * Float.pi * 240 / sampleRate
        let left = buffers[0].mData?.assumingMemoryBound(to: Float.self)
        let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let lowCoefficient = 2 * Float.pi * 60 / sampleRate

        for i in 0..<frames {
            rain += (p.rain - rain) * smoothing
            wind += (p.wind - wind) * smoothing
            rumble += (p.rumble - rumble) * smoothing

            // --- Wind: irregular gusts, drifting pitch.
            gustTimer -= 1
            if gustTimer <= 0 {
                gustTimer = Int(sampleRate * (0.3 + 1.6 * random01()))
                gustTarget = 0.6 + 0.4 * random01()
                windFreqTarget = 260 + 360 * random01()
            }
            gust += (gustTarget - gust) * gustSlew
            windFreq += (windFreqTarget - windFreq) * pitchSlew
            let f = 2 * sinf(Float.pi * windFreq / sampleRate)
            let high = noise() - windLow - 1.2 * windBand
            windBand += f * high
            windLow += f * windBand
            let windSample = (windBand * 3.5 + windLow * 0.4) * wind * gust

            // --- Rain: hiss + drops (independent left/right).
            let nl = noise(), nr = noise()
            rainLowL += 0.25 * (nl - rainLowL)
            rainLowR += 0.25 * (nr - rainLowR)
            if random01() < 0.0025 * rain { dropL = 0.2 + 0.4 * random01() }
            if random01() < 0.0025 * rain { dropR = 0.2 + 0.4 * random01() }
            let rainL = (nl - rainLowL) * 0.09 * rain + noise() * dropL
            let rainR = (nr - rainLowR) * 0.09 * rain + noise() * dropR
            dropL *= 0.985
            dropR *= 0.985

            // --- Low rumble of the storm.
            low1 += lowCoefficient * (noise() - low1)
            low2 += lowCoefficient * (low1 - low2)
            var lowSample = low2 * 12 * rumble

            // --- Thunder: sharp crack, then a long, irregularly rolling rumble.
            mid1 += midCoefficient * (noise() - mid1)
            mid2 += midCoefficient * (mid1 - mid2)
            if echoCountdown > 0 {
                echoCountdown -= 1
                if echoCountdown == 0 { echoEnvelope = 0.75 }
            }
            if echoEnvelope > 0.0005 {
                echoEnvelope *= thunderDecay * 0.99999
                lowSample += (low2 * 60 + mid2 * 10) * echoEnvelope * roll
            }
            if thunderEnvelope > 0.0005 {
                thunderEnvelope *= thunderDecay
                crackleEnvelope *= crackleDecay
                rollTimer -= 1
                if rollTimer <= 0 {
                    rollTimer = Int(sampleRate * (0.08 + 0.35 * random01()))
                    rollTarget = 0.35 + 0.65 * random01()
                }
                roll += (rollTarget - roll) * (1 / (sampleRate * 0.06))
                let crack = noise()
                crackleHigh += 0.5 * (crack - crackleHigh)
                lowSample += low2 * 70 * thunderEnvelope * roll
                lowSample += mid2 * 16 * thunderEnvelope * roll
                lowSample += (crack - crackleHigh) * 1.3 * crackleEnvelope * crackleEnvelope
            }

            // --- Chime (sine notes with a soft octave) + whoosh (band-passed noise swell).
            var chimeSample: Float = 0
            for k in notes.indices where notes[k].env > 0.0005 {
                if notes[k].delay > 0 { notes[k].delay -= 1; continue }
                notes[k].phase += notes[k].freq / sampleRate
                if notes[k].phase > 1 { notes[k].phase -= 1 }
                let angle = 2 * Float.pi * notes[k].phase
                chimeSample += (sinf(angle) + 0.25 * sinf(2 * angle)) * notes[k].env * 0.22
                notes[k].env *= noteDecay
            }
            if whooshAttack > 0 {
                whooshEnvelope += (1 - whooshEnvelope) * (1 / (sampleRate * 0.04))
                if whooshEnvelope > 0.95 { whooshAttack = 0 }
            } else {
                whooshEnvelope *= 0.99985
            }
            if whooshEnvelope > 0.0005 {
                let n = noise()
                whooshLow += 0.08 * (n - whooshLow)
                whooshBand += 0.3 * (whooshLow - whooshBand)
                chimeSample += (whooshLow - whooshBand) * 0.9 * whooshEnvelope
            }

            master += (p.masterTarget - master) * masterCoefficient
            left?[i] = tanhf((windSample + rainL + lowSample + chimeSample) * master)
            right?[i] = tanhf((windSample * 0.92 + rainR + lowSample + chimeSample) * master)
        }
    }
}
