//
//  SettingsStore.swift
//  Classic
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import Foundation
import MediaPlayer
import UIKit

extension Notification.Name {
    static let splitScreenMenusDidChange = Notification.Name("splitScreenMenusDidChange")
}

class SettingsStore {

    static let shared = SettingsStore()

    // MARK: - Keys

    private enum Keys {
        static let shuffle = "classic.settings.shuffle"
        static let repeatMode = "classic.settings.repeatMode"
        static let eq = "classic.settings.eq"
        static let soundCheck = "classic.settings.soundCheck"
        static let volumeLimit = "classic.settings.volumeLimit"
        static let audiobooksSpeed = "classic.settings.audiobooksSpeed"
        static let backlightTimerIndex = "classic.settings.backlightTimerIndex"
        static let brightness = "classic.settings.brightness"
        static let clickerEnabled = "classic.settings.clickerEnabled"
        static let ipodColor = "classic.settings.ipodColor"
        static let timeMachineYear = "classic.settings.timeMachineYear"
        static let clickerMode = "classic.settings.clickerMode"
        static let splitScreenMenus = "classic.settings.splitScreenMenus"
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
            Keys.clickerEnabled: true,
            Keys.ipodColor: "Silver",
            Keys.timeMachineYear: 0,
            Keys.splitScreenMenus: true
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

    // Returns the backlight timeout in seconds, or nil for "Always On" / "Off"
    var backlightTimerDuration: TimeInterval? {
        switch backlightTimerIndex {
        case 0:  return 0     // Off — backlight always off (screen stays dim)
        case 1:  return 2
        case 2:  return 5
        case 3:  return 10
        case 4:  return 20
        case 5:  return 30
        default: return nil   // Always On — never dims
        }
    }

    private func applyBacklightTimer(index: Int) {
        // "Always On" (index 6) disables the idle timer so the screen never sleeps
        UIApplication.shared.isIdleTimerDisabled = (index == 6)
        AppDelegate.baseVC.resetBacklightTimer()
    }

    // MARK: - Brightness

    var brightness: Float {
        get { return UserDefaults.standard.float(forKey: Keys.brightness) }
        set {
            let clamped = max(0.0, min(1.0, newValue))
            UserDefaults.standard.set(clamped, forKey: Keys.brightness)
            AppDelegate.baseVC.setScreenBrightness(clamped)
        }
    }

    // MARK: - Clicker

    /// Like the iPod classic's Clicker setting, but haptic instead of headphones.
    static let clickerOptions: [String] = ["Off", "Haptic", "Sound", "Both"]

    /// "Off", "Haptic", "Sound" or "Both". Older installs only had the haptics
    /// on/off flag, so fall back to that when no mode has been chosen yet.
    var clickerMode: String {
        get {
            if let mode = UserDefaults.standard.string(forKey: Keys.clickerMode) { return mode }
            return UserDefaults.standard.bool(forKey: Keys.clickerEnabled) ? "Haptic" : "Off"
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.clickerMode) }
    }

    /// Haptic clicks on wheel and button input.
    var clickerEnabled: Bool {
        get { return clickerMode == "Haptic" || clickerMode == "Both" }
        set { clickerMode = newValue ? "Haptic" : "Off" }
    }

    /// Audible clicks from the speaker, like the iPod's piezo clicker.
    var clickerSoundEnabled: Bool {
        return clickerMode == "Sound" || clickerMode == "Both"
    }

    // MARK: - Split Screen Menus

    /// iPod classic-style menus with a preview pane on the right. The nano
    /// and earlier iPods used full-width menus, so it can be turned off.
    var splitScreenMenus: Bool {
        get { return UserDefaults.standard.bool(forKey: Keys.splitScreenMenus) }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.splitScreenMenus)
            NotificationCenter.default.post(name: .splitScreenMenusDidChange, object: nil)
        }
    }

    // MARK: - iPod Color

    var ipodColor: String {
        get { return UserDefaults.standard.string(forKey: Keys.ipodColor) ?? "Silver" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.ipodColor) }
    }

    // MARK: - Time Machine

    // Value: 0 means "Off" (no filter), otherwise a year (e.g. 1995)
    static var timeMachineOptions: [String] {
        let currentYear = Calendar.current.component(.year, from: Date())
        var options = ["Off"]
        for year in stride(from: currentYear, through: 1960, by: -1) {
            options.append("\(year)")
        }
        return options
    }

    var timeMachineYear: Int {
        get { return UserDefaults.standard.integer(forKey: Keys.timeMachineYear) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.timeMachineYear) }
    }

    var timeMachineDisplayValue: String {
        let year = timeMachineYear
        return year == 0 ? "Off" : "\(year)"
    }

    var timeMachineIndex: Int {
        let year = timeMachineYear
        if year == 0 { return 0 }
        let currentYear = Calendar.current.component(.year, from: Date())
        return max(0, currentYear - year + 1)
    }

    // MARK: - Apply All (called on app launch)

    func applyAllSettings() {
        // Shuffle
        switch shuffle {
        case "songs":  MPMusicPlayerController.systemMusicPlayer.shuffleMode = .songs
        case "albums": MPMusicPlayerController.systemMusicPlayer.shuffleMode = .albums
        default:       MPMusicPlayerController.systemMusicPlayer.shuffleMode = .off
        }

        // Repeat
        switch repeatMode {
        case "one": MPMusicPlayerController.systemMusicPlayer.repeatMode = .one
        case "all": MPMusicPlayerController.systemMusicPlayer.repeatMode = .all
        default:    MPMusicPlayerController.systemMusicPlayer.repeatMode = .none
        }

        // Backlight
        applyBacklightTimer(index: backlightTimerIndex)

        // Brightness overlay
        AppDelegate.baseVC.setScreenBrightness(brightness)
    }

    // MARK: - Reset

    func resetAll() {
        let keys = [
            Keys.shuffle, Keys.repeatMode, Keys.eq, Keys.soundCheck,
            Keys.volumeLimit, Keys.audiobooksSpeed, Keys.backlightTimerIndex,
            Keys.brightness, Keys.clickerEnabled, Keys.ipodColor,
            Keys.timeMachineYear, Keys.clickerMode, Keys.splitScreenMenus
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // Re-apply defaults after reset
        MPMusicPlayerController.systemMusicPlayer.shuffleMode = .off
        MPMusicPlayerController.systemMusicPlayer.repeatMode = .none
        UIApplication.shared.isIdleTimerDisabled = true   // Always On is the default
        AppDelegate.baseVC.setScreenBrightness(1.0)
        AppDelegate.baseVC.resetBacklightTimer()
        UserDefaults.standard.synchronize()
        ThemeManager.shared.applyTheme(named: "Silver")
    }
}
