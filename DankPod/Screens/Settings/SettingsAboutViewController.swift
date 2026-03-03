//
//  SettingsAboutViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import MediaPlayer

class SettingsAboutViewController: UIViewController, ClickWheelProtocol {

    let tableView = UITableView()
    var hasSetupUI = false

    // Pages cycle on Center press, matching the real iPod behaviour
    private var pageIndex: Int = 0
    private let pageCount = 2

    // MARK: - Pages

    // Returns the rows for the currently visible page
    private var currentRows: [(label: String, value: String)] {
        switch pageIndex {
        case 0:
            return [
                ("Name", "DankPod"),
                ("Capacity", capacityString()),
                ("Available", availableString()),
                ("Songs", songCountString())
            ]
        case 1:
            return [
                ("Version", appVersionString()),
                ("Model", UIDevice.current.model),
                ("Format", "iOS")
            ]
        default:
            return []
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "About"
        tableView.reloadData()
        tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .top)
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

    // MARK: - Data helpers

    private func capacityString() -> String {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let total = attrs[.systemSize] as? Int64 {
            return formatBytes(total)
        }
        return "N/A"
    }

    private func availableString() -> String {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let free = attrs[.systemFreeSize] as? Int64 {
            return formatBytes(free)
        }
        return "N/A"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }

    private func songCountString() -> String {
        let count = MPMediaQuery.songs().items?.count ?? 0
        return "\(count)"
    }

    private func appVersionString() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {}

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
            pageIndex = (pageIndex + 1) % pageCount
            tableView.reloadData()
        }
    }
}

extension SettingsAboutViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return currentRows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = currentRows[indexPath.row]
        let cell = CustomSettingsTableViewCell()
        cell.label.text = row.label
        cell.valueLabel.text = row.value
        cell.showChevron = false
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }
}
