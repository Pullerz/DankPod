//
//  SettingsGeneralViewController.swift
//  Classic
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class SettingsGeneralViewController: UIViewController, ClickWheelProtocol {

    let tableView = UITableView()
    var counter: Int = 0
    var hasSetupUI = false

    private let menuItems = ["Clicker", "Split Screen Menus"]

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "General"
        tableView.reloadData()
        tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .top)
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
            guard counter < menuItems.count - 1 else { return }
            counter += 1
        } else {
            guard counter > 0 else { return }
            counter -= 1
        }
        tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
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
            let store = SettingsStore.shared
            switch menuItems[counter] {
            case "Clicker":
                // Cycle through the options in place, like Shuffle and Repeat.
                let options = SettingsStore.clickerOptions
                let next = ((options.firstIndex(of: store.clickerMode) ?? 0) + 1) % options.count
                store.clickerMode = options[next]
            default:
                store.splitScreenMenus.toggle()
            }
            tableView.reloadData()
            tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .top)
        }
    }
}

extension SettingsGeneralViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return menuItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomSettingsTableViewCell()
        cell.label.text = menuItems[indexPath.row]
        cell.showChevron = false
        cell.selectionStyle = .none
        switch menuItems[indexPath.row] {
        case "Clicker": cell.valueLabel.text = SettingsStore.shared.clickerMode
        default:        cell.valueLabel.text = SettingsStore.shared.splitScreenMenus ? "On" : "Off"
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }
}
