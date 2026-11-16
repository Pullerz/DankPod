//
//  ClickSoundPlayer.swift
//  Classic
//
//  A tiny, low-latency player for the iPod's piezo clicker. Both sounds are
//  synthesised once at start-up into PCM buffers and replayed on a pre-started
//  AVAudioEngine, so playing a click never allocates.
//

import UIKit
import AVFoundation

final class ClickSoundPlayer {

    static let shared = ClickSoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let tickBuffer: AVAudioPCMBuffer
    private let clunkBuffer: AVAudioPCMBuffer
    private var sessionConfigured = false
    private var isStarting = false

    private init() {
        let sampleRate: Double = 44_100
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        tickBuffer = ClickSoundPlayer.makeTick(format: format)
        clunkBuffer = ClickSoundPlayer.makeClunk(format: format)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleInterruption(_:)),
                       name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleRestartNeeded),
                       name: AVAudioSession.routeChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleRestartNeeded),
                       name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleRestartNeeded),
                       name: .AVAudioEngineConfigurationChange, object: engine)
        nc.addObserver(self, selector: #selector(handleRestartNeeded),
                       name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    // MARK: - Public

    /// Starts the engine ahead of time so the first click isn't late.
    func prepare() {
        startIfNeeded()
    }

    /// The dry "tick" of a wheel step.
    func playTick() {
        play(tickBuffer)
    }

    /// The slightly heavier "clunk" of a button press.
    func playButton() {
        play(clunkBuffer)
    }

    // MARK: - Playback

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard startIfNeeded() else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    @discardableResult
    private func startIfNeeded() -> Bool {
        if engine.isRunning { return true }
        guard !isStarting else { return false }
        isStarting = true
        defer { isStarting = false }

        if !sessionConfigured {
            // Ambient + mixWithOthers: never interrupts or ducks the music.
            do {
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                sessionConfigured = true
            } catch {
                return false
            }
        }
        do {
            engine.prepare()
            try engine.start()
            player.play()
            return true
        } catch {
            return false
        }
    }

    private func restart() {
        player.stop()
        engine.stop()
        startIfNeeded()
    }

    // MARK: - Notifications

    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch type {
            case .began:
                self.player.stop()
            case .ended:
                // Only restart if the user still wants sounds; otherwise wait for the next click.
                if SettingsStore.shared.clickerSoundEnabled { self.restart() } else { self.engine.stop() }
            @unknown default:
                break
            }
        }
    }

    @objc private func handleRestartNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Engine was never used (sound off) — leave the audio session alone.
            guard self.sessionConfigured, SettingsStore.shared.clickerSoundEnabled else { return }
            if !self.engine.isRunning { self.restart() }
        }
    }

    // MARK: - Synthesis

    /// ~5ms piezo tick: a sharp impulse into a few cycles of a strongly damped
    /// high-frequency resonance, plus a little noise.
    private static func makeTick(format: AVAudioFormat) -> AVAudioPCMBuffer {
        return synthesize(format: format,
                          duration: 0.005,
                          partials: [(freq: 4_100, amp: 0.55), (freq: 6_900, amp: 0.25)],
                          decay: 0.0008,
                          noiseAmount: 0.45,
                          noiseDecay: 0.0005,
                          peak: 0.55)
    }

    /// ~12ms button press: lower, slightly longer resonance with some body.
    private static func makeClunk(format: AVAudioFormat) -> AVAudioPCMBuffer {
        return synthesize(format: format,
                          duration: 0.012,
                          partials: [(freq: 1_700, amp: 0.6), (freq: 3_300, amp: 0.35), (freq: 420, amp: 0.4)],
                          decay: 0.0022,
                          noiseAmount: 0.35,
                          noiseDecay: 0.0009,
                          peak: 0.7)
    }

    private static func synthesize(format: AVAudioFormat,
                                   duration: Double,
                                   partials: [(freq: Double, amp: Double)],
                                   decay: Double,
                                   noiseAmount: Double,
                                   noiseDecay: Double,
                                   peak: Float) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(max(1, Int(duration * sampleRate)))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let out = buffer.floatChannelData![0]

        // Deterministic noise so the click sounds identical every launch.
        var seed: UInt32 = 0x1234_5678
        var prevNoise: Double = 0
        var maxAbs: Float = 0
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            var s: Double = 0
            for p in partials {
                s += p.amp * sin(2 * .pi * p.freq * t)
            }
            s *= exp(-t / decay)

            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Double(seed >> 8) / Double(1 << 24) * 2 - 1
            // First-difference high-pass keeps the noise bright and "dry".
            let bright = white - prevNoise * 0.6
            prevNoise = white
            s += noiseAmount * bright * exp(-t / noiseDecay)

            if i == 0 { s += 0.8 }         // the initial impulse
            if i == 1 { s -= 0.4 }

            // Short fade-out over the last ~0.5ms to avoid a tail click.
            let remaining = Double(Int(frames) - i) / sampleRate
            if remaining < 0.0005 { s *= remaining / 0.0005 }

            let v = Float(s)
            out[i] = v
            maxAbs = max(maxAbs, abs(v))
        }
        if maxAbs > 0 {
            let gain = peak / maxAbs
            for i in 0..<Int(frames) { out[i] *= gain }
        }
        return buffer
    }
}
