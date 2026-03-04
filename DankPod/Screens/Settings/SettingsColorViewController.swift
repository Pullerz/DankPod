//
//  SettingsColorViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class SettingsColorViewController: UIViewController, ClickWheelProtocol {

    let tableView = UITableView()
    var counter: Int = 0
    var hasSetupUI = false

    private let themes = ThemeManager.allThemes

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "iPod Color"
        // Set counter to current theme
        let currentName = SettingsStore.shared.ipodColor
        if let idx = themes.firstIndex(where: { $0.name == currentName }) {
            counter = idx
        }
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

    // MARK: - ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if rotationDirection == .CLOCKWISE {
            if counter + 1 <= themes.count - 1 {
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
            self.navigationController?.popViewController(animated: true)
        } else if pressure == .FORCE {
            self.navigationController?.popToRootViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            ThemeManager.shared.applyTheme(named: themes[counter].name)
            tableView.reloadData()
            tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
        }
    }
}

extension SettingsColorViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return themes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let theme = themes[indexPath.row]
        let cell = CustomSettingsTableViewCell()
        cell.label.text = theme.name
        cell.showChevron = false
        cell.selectionStyle = .none

        // Color swatch
        let swatch = UIView()
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.backgroundColor = theme.bodyColor
        swatch.layer.cornerRadius = 5
        swatch.layer.borderWidth = 0.5
        swatch.layer.borderColor = UIColor.lightGray.cgColor
        cell.contentView.addSubview(swatch)
        swatch.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor).isActive = true
        swatch.rightAnchor.constraint(equalTo: cell.valueLabel.leftAnchor, constant: -8).isActive = true
        swatch.widthAnchor.constraint(equalToConstant: 16).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: 16).isActive = true

        // Checkmark for current theme
        let currentName = SettingsStore.shared.ipodColor
        if theme.name == currentName {
            cell.valueLabel.text = "✓"
        } else {
            cell.valueLabel.text = ""
        }

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }
}
