//
//  PhotoSettingsViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class PhotoSettingsViewController: UIViewController, ClickWheelProtocol {
    let menuItems: [String] = ["Time Per Slide", "Repeat", "Shuffle Photos", "Transitions"]
    let tableView: UITableView = UITableView()
    
    let timeOptions: [String] = ["2s", "3s", "5s", "10s", "20s", "Manual"]
    let timeValues: [Double] = [2.0, 3.0, 5.0, 10.0, 20.0, -1.0]
    let transitionOptions: [String] = ["Cross Fade", "Fade to Black"]
    
    var counter: Int = 0
    var hasSetupUI = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Settings"
        tableView.reloadData()
        tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .top)
        updateValueLabelColors()
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
    
    func currentValueForItem(at index: Int) -> String {
        switch index {
        case 0: // Time Per Slide
            let timePerSlide = UserDefaults.standard.double(forKey: "slideshowTimePerSlide")
            if timePerSlide < 0 {
                return "Manual"
            }
            if timePerSlide == 0 {
                return "3s" // default when unset
            }
            if let idx = timeValues.firstIndex(of: timePerSlide), idx < timeOptions.count {
                return timeOptions[idx]
            }
            return "3s"
        case 1: // Repeat
            return UserDefaults.standard.bool(forKey: "slideshowRepeat") ? "On" : "Off"
        case 2: // Shuffle Photos
            return UserDefaults.standard.bool(forKey: "slideshowShuffle") ? "On" : "Off"
        case 3: // Transitions
            let transition = UserDefaults.standard.string(forKey: "slideshowTransition") ?? "Cross Fade"
            return transition
        default:
            return ""
        }
    }
    
    func updateValueLabelColors() {
        for cell in tableView.visibleCells {
            if let valueLabel = cell.contentView.viewWithTag(100) as? UILabel {
                valueLabel.textColor = cell.isSelected ? .white : .gray
            }
        }
    }
    
    func cycleValue(at index: Int) {
        switch index {
        case 0: // Time Per Slide
            let current = UserDefaults.standard.double(forKey: "slideshowTimePerSlide")
            var currentIdx = timeValues.firstIndex(of: current) ?? 1 // default to 3s (index 1)
            currentIdx = (currentIdx + 1) % timeOptions.count
            UserDefaults.standard.set(timeValues[currentIdx], forKey: "slideshowTimePerSlide")
        case 1: // Repeat
            let current = UserDefaults.standard.bool(forKey: "slideshowRepeat")
            UserDefaults.standard.set(!current, forKey: "slideshowRepeat")
        case 2: // Shuffle Photos
            let current = UserDefaults.standard.bool(forKey: "slideshowShuffle")
            UserDefaults.standard.set(!current, forKey: "slideshowShuffle")
        case 3: // Transitions
            let current = UserDefaults.standard.string(forKey: "slideshowTransition") ?? "Cross Fade"
            if let idx = transitionOptions.firstIndex(of: current) {
                let nextIdx = (idx + 1) % transitionOptions.count
                UserDefaults.standard.set(transitionOptions[nextIdx], forKey: "slideshowTransition")
            } else {
                UserDefaults.standard.set("Fade to Black", forKey: "slideshowTransition")
            }
        default:
            break
        }
        tableView.reloadData()
        tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
        updateValueLabelColors()
    }
    
    
    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if (rotationDirection == .CLOCKWISE) {
            if (counter + 1 <= self.menuItems.count - 1) {
                counter += 1
                let ip = IndexPath(row: counter, section: 0)
                tableView.selectRow(at: ip, animated: false, scrollPosition: .bottom)
                updateValueLabelColors()
            }
        } else {
            if (counter > 0) {
                counter -= 1
                let ip = IndexPath(row: counter, section: 0)
                tableView.selectRow(at: ip, animated: false, scrollPosition: .bottom)
                updateValueLabelColors()
            }
        }
    }
    
    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        }
    }
    
    func nextSongPressed(pressure: ClickWheelTouchPressure) {
        
    }
    
    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        
    }
    
    func menuPressed(pressure: ClickWheelTouchPressure) {
        if (pressure == .NORMAL) {
            self.navigationController?.popViewController(animated: true)
        } else if (pressure == .FORCE) {
            self.navigationController?.popToRootViewController(animated: true)
        }
    }
    
    func centerPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            cycleValue(at: counter)
        }
    }


}

extension PhotoSettingsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.menuItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = menuItems[indexPath.row]
        cell.selectionStyle = .none
        cell.accessoryType = .none
        
        let valueLabel = UILabel()
        valueLabel.tag = 100
        valueLabel.text = currentValueForItem(at: indexPath.row)
        valueLabel.font = UIFont(name: "Helvetica-Bold", size: 15)
        valueLabel.textColor = .gray
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(valueLabel)
        valueLabel.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor).isActive = true
        valueLabel.rightAnchor.constraint(equalTo: cell.contentView.rightAnchor, constant: -15).isActive = true
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let valueLabel = cell.contentView.viewWithTag(100) as? UILabel {
            valueLabel.textColor = cell.isSelected ? .white : .gray
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }


}
