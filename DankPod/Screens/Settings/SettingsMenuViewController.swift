//
//  SettingsMenuViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class SettingsMenuViewController: UIViewController, ClickWheelProtocol {

    let tableView = UITableView()
    var counter: Int = 0
    var hasSetupUI = false

    private let menuItems: [String] = [
        "About",
        "Shuffle",
        "Repeat",
        "EQ",
        "Sound Check",
        "Volume Limit",
        "Audiobooks",
        "Backlight",
        "Brightness",
        "General",
        "Sort By",
        "Language",
        "Legal",
        "Reset Settings"
    ]

    // Items that are not yet implemented — rendered greyed-out with no action
    private let stubItems: Set<String> = ["Sort By", "Language"]

    // Items that navigate to a sub-screen (show disclosure chevron)
    private let navigationItems: Set<String> = [
        "About", "EQ", "Volume Limit", "Audiobooks", "Backlight", "Brightness",
        "General", "Legal", "Reset Settings"
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Settings"
        tableView.reloadData()
        tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
    }

    func setupUI() {
        if !hasSetupUI {
            tableView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(tableView)
            tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            tableView.delegate = self
            tableView.dataSource = self
            tableView.separatorStyle = .none
            hasSetupUI = true
        }
    }

    // MARK: - Value display helpers

    private func valueForItem(_ item: String) -> String? {
        switch item {
        case "Shuffle":     return SettingsStore.shared.shuffleDisplayValue
        case "Repeat":      return SettingsStore.shared.repeatDisplayValue
        case "EQ":          return SettingsStore.shared.eq
        case "Sound Check": return SettingsStore.shared.soundCheck ? "On" : "Off"
        case "Audiobooks":  return SettingsStore.shared.audiobooksDisplayValue
        case "Backlight":   return SettingsStore.shared.backlightDisplayValue
        default:            return nil
        }
    }

    // MARK: - Navigation

    private func handleCenterPress(for item: String) {
        switch item {

        case "About":
            navigationController?.pushViewController(SettingsAboutViewController(), animated: true)

        case "Shuffle":
            let current = SettingsStore.shared.shuffle
            switch current {
            case "off":    SettingsStore.shared.shuffle = "songs"
            case "songs":  SettingsStore.shared.shuffle = "albums"
            default:       SettingsStore.shared.shuffle = "off"
            }
            tableView.reloadRows(at: [IndexPath(row: counter, section: 0)], with: .none)
            tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)

        case "Repeat":
            let current = SettingsStore.shared.repeatMode
            switch current {
            case "off":  SettingsStore.shared.repeatMode = "one"
            case "one":  SettingsStore.shared.repeatMode = "all"
            default:     SettingsStore.shared.repeatMode = "off"
            }
            tableView.reloadRows(at: [IndexPath(row: counter, section: 0)], with: .none)
            tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)

        case "EQ":
            let vc = SettingsPickerViewController()
            vc.pickerTitle = "EQ"
            vc.options = SettingsStore.eqPresets
            vc.selectedIndex = SettingsStore.shared.eqIndex
            vc.onSelect = { index in
                SettingsStore.shared.eq = SettingsStore.eqPresets[index]
            }
            navigationController?.pushViewController(vc, animated: true)

        case "Sound Check":
            SettingsStore.shared.soundCheck = !SettingsStore.shared.soundCheck
            tableView.reloadRows(at: [IndexPath(row: counter, section: 0)], with: .none)
            tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)

        case "Volume Limit":
            let vc = SettingsSliderViewController()
            vc.sliderTitle = "Volume Limit"
            vc.value = SettingsStore.shared.volumeLimit
            vc.onValueChanged = { value in
                SettingsStore.shared.volumeLimit = value
            }
            navigationController?.pushViewController(vc, animated: true)

        case "Audiobooks":
            let vc = SettingsPickerViewController()
            vc.pickerTitle = "Audiobooks"
            vc.options = SettingsStore.audiobooksOptions
            vc.selectedIndex = SettingsStore.shared.audiobooksIndex
            vc.onSelect = { index in
                SettingsStore.shared.audiobooksSpeed = SettingsStore.audiobooksOptions[index]
            }
            navigationController?.pushViewController(vc, animated: true)

        case "Backlight":
            let vc = SettingsPickerViewController()
            vc.pickerTitle = "Backlight"
            vc.options = SettingsStore.backlightOptions
            vc.selectedIndex = SettingsStore.shared.backlightTimerIndex
            vc.onSelect = { index in
                SettingsStore.shared.backlightTimerIndex = index
            }
            navigationController?.pushViewController(vc, animated: true)

        case "Brightness":
            let vc = SettingsSliderViewController()
            vc.sliderTitle = "Brightness"
            vc.value = SettingsStore.shared.brightness
            vc.onValueChanged = { value in
                SettingsStore.shared.brightness = value
            }
            navigationController?.pushViewController(vc, animated: true)

        case "General":
            navigationController?.pushViewController(SettingsGeneralViewController(), animated: true)

        case "Legal":
            navigationController?.pushViewController(SettingsLegalViewController(), animated: true)

        case "Reset Settings":
            navigationController?.pushViewController(SettingsResetViewController(), animated: true)

        default:
            // Stub items — no action
            break
        }
    }

    // MARK: - ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if rotationDirection == .CLOCKWISE {
            if counter + 1 <= menuItems.count - 1 {
                counter += 1
                tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .bottom)
            }
        } else {
            if counter > 0 {
                counter -= 1
                tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .bottom)
            }
        }
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {}

    func previousSongPressed(pressure: ClickWheelTouchPressure) {}

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            navigationController?.popViewController(animated: true)
        } else if pressure == .FORCE {
            navigationController?.popToRootViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            handleCenterPress(for: menuItems[counter])
        }
    }
}

extension SettingsMenuViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return menuItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = menuItems[indexPath.row]
        let isStub = stubItems.contains(item)
        let hasChevron = navigationItems.contains(item)

        let cell = CustomSettingsTableViewCell()
        cell.label.text = item
        cell.selectionStyle = .none
        cell.showChevron = hasChevron && !isStub
        cell.valueLabel.text = valueForItem(item)

        if isStub {
            cell.label.textColor = UIColor.lightGray
            cell.valueLabel.textColor = UIColor.lightGray
        }

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }
}
