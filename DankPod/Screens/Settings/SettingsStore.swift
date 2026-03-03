//
//  SettingsStore.swift
//  DankPod
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import Foundation
import MediaPlayer
import UIKit

class SettingsStore {

    static let shared = SettingsStore()

    // MARK: - Keys

    private enum Keys {
        static let shuffle = "dankpod.settings.shuffle"
        static let repeatMode = "dankpod.settings.repeatMode"
        static let eq = "dankpod.settings.eq"
        static let soundCheck = "dankpod.settings.soundCheck"
        static let volumeLimit = "dankpod.settings.volumeLimit"
        static let audiobooksSpeed = "dankpod.settings.audiobooksSpeed"
        static let backlightTimerIndex = "dankpod.settings.backlightTimerIndex"
        static let brightness = "dankpod.settings.brightness"
        static let clickerEnabled = "dankpod.settings.clickerEnabled"
    }

    // MARK: - Init

    private init() {
        UserDefaults.standard.register(defaults: [
            Keys.shuffle: "off",
            Keys.repeatMode: "off",
            Keys.eq: "Off",
            Keys.soundCheck: false,
            Keys.volumeLimit: Float(1.0),
            Keys.audiobooksSpeed: "normal",
            Keys.backlightTimerIndex: 6,   // "Always On"
            Keys.brightness: Float(UIScreen.main.brightness),
            Keys.clickerEnabled: true
        ])
    }

    // MARK: - Shuffle

    // Values: "off", "songs", "albums"
    var shuffle: String {
        get { return UserDefaults.standard.string(forKey: Keys.shuffle) ?? "off" }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.shuffle)
            switch newValue {
            case "songs":
                MPMusicPlayerController.systemMusicPlayer.shuffleMode = .songs
            case "albums":
                MPMusicPlayerController.systemMusicPlayer.shuffleMode = .albums
            default:
                MPMusicPlayerController.systemMusicPlayer.shuffleMode = .off
            }
        }
    }

    var shuffleDisplayValue: String {
        switch shuffle {
        case "songs": return "Songs"
        case "albums": return "Albums"
        default: return "Off"
        }
    }

    // MARK: - Repeat

    // Values: "off", "one", "all"
    var repeatMode: String {
        get { return UserDefaults.standard.string(forKey: Keys.repeatMode) ?? "off" }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.repeatMode)
            switch newValue {
            case "one":
                MPMusicPlayerController.systemMusicPlayer.repeatMode = .one
            case "all":
                MPMusicPlayerController.systemMusicPlayer.repeatMode = .all
            default:
                MPMusicPlayerController.systemMusicPlayer.repeatMode = .none
            }
        }
    }

    var repeatDisplayValue: String {
        switch repeatMode {
        case "one": return "One"
        case "all": return "All"
        default: return "Off"
        }
    }

    // MARK: - EQ

    static let eqPresets: [String] = [
        "Off", "Acoustic", "Bass Booster", "Bass Reducer", "Classical", "Dance",
        "Deep", "Electronic", "Flat", "Hip-Hop", "Jazz", "Latin", "Loudness",
        "Lounge", "Piano", "Pop", "R&B", "Rock", "Small Speakers", "Spoken Word",
        "Treble Booster", "Treble Reducer", "Vocal Booster"
    ]

    var eq: String {
        get { return UserDefaults.standard.string(forKey: Keys.eq) ?? "Off" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.eq) }
    }

    var eqIndex: Int {
        return SettingsStore.eqPresets.firstIndex(of: eq) ?? 0
    }

    // MARK: - Sound Check

    var soundCheck: Bool {
        get { return UserDefaults.standard.bool(forKey: Keys.soundCheck) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.soundCheck) }
    }

    // MARK: - Volume Limit

    var volumeLimit: Float {
        get { return UserDefaults.standard.float(forKey: Keys.volumeLimit) }
        set {
            let clamped = max(0.0, min(1.0, newValue))
            UserDefaults.standard.set(clamped, forKey: Keys.volumeLimit)
            MPVolumeView.setVolume(clamped)
        }
    }

    // MARK: - Audiobooks Speed

    // Values: "slower", "normal", "faster"
    static let audiobooksOptions: [String] = ["Slower", "Normal", "Faster"]

    var audiobooksSpeed: String {
        get { return UserDefaults.standard.string(forKey: Keys.audiobooksSpeed) ?? "normal" }
        set { UserDefaults.standard.set(newValue.lowercased(), forKey: Keys.audiobooksSpeed) }
    }

    var audiobooksIndex: Int {
        switch audiobooksSpeed {
        case "slower": return 0
        case "faster": return 2
        default: return 1
        }
    }

    var audiobooksDisplayValue: String {
        switch audiobooksSpeed {
        case "slower": return "Slower"
        case "faster": return "Faster"
        default: return "Normal"
        }
    }

    // MARK: - Backlight Timer

    static let backlightOptions: [String] = ["Off", "2 Seconds", "5 Seconds", "10 Seconds", "20 Seconds", "30 Seconds", "Always On"]

    var backlightTimerIndex: Int {
        get { return UserDefaults.standard.integer(forKey: Keys.backlightTimerIndex) }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.backlightTimerIndex)
            applyBacklightTimer(index: newValue)
        }
    }

    var backlightDisplayValue: String {
        let idx = backlightTimerIndex
        guard idx < SettingsStore.backlightOptions.count else { return "Always On" }
        return SettingsStore.backlightOptions[idx]
    }

    private func applyBacklightTimer(index: Int) {
        // "Always On" (index 6) disables the idle timer so the screen never sleeps
        UIApplication.shared.isIdleTimerDisabled = (index == 6)
    }

    // MARK: - Brightness

    var brightness: Float {
        get { return UserDefaults.standard.float(forKey: Keys.brightness) }
        set {
            let clamped = max(0.0, min(1.0, newValue))
            UserDefaults.standard.set(clamped, forKey: Keys.brightness)
            UIScreen.main.brightness = CGFloat(clamped)
        }
    }

    // MARK: - Clicker (Haptics)

    var clickerEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: Keys.clickerEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.clickerEnabled) }
    }

    // MARK: - Reset

    func resetAll() {
        let keys = [
            Keys.shuffle, Keys.repeatMode, Keys.eq, Keys.soundCheck,
            Keys.volumeLimit, Keys.audiobooksSpeed, Keys.backlightTimerIndex,
            Keys.brightness, Keys.clickerEnabled
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // Re-apply defaults after reset
        MPMusicPlayerController.systemMusicPlayer.shuffleMode = .off
        MPMusicPlayerController.systemMusicPlayer.repeatMode = .none
        UIApplication.shared.isIdleTimerDisabled = true   // Always On is the default
        UserDefaults.standard.synchronize()
    }
}
