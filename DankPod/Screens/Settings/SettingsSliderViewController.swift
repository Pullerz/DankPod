//
//  SettingsSliderViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class SettingsSliderViewController: UIViewController, ClickWheelProtocol {

    var sliderTitle: String = ""
    // Current value in the range 0.0 – 1.0
    var value: Float = 0.5
    var onValueChanged: ((Float) -> Void)?

    private let volumeBar = UIProgressView(progressViewStyle: .default)
    private let lowVolume = UIImageView(image: #imageLiteral(resourceName: "lowVolume"))
    private let highVolume = UIImageView(image: #imageLiteral(resourceName: "fullVolume"))

    var hasSetupUI = false

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = sliderTitle
        volumeBar.setProgress(value, animated: false)
    }

    func setupUI() {
        if !hasSetupUI {
            view.backgroundColor = .white

            volumeBar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(volumeBar)
            volumeBar.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            volumeBar.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 50).isActive = true
            volumeBar.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -50).isActive = true
            volumeBar.heightAnchor.constraint(equalToConstant: 30).isActive = true
            volumeBar.progressImage = #imageLiteral(resourceName: "progress").resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1), resizingMode: .tile)
            volumeBar.trackImage = #imageLiteral(resourceName: "track").resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1), resizingMode: .tile)
            volumeBar.layer.shadowColor = UIColor.black.cgColor
            volumeBar.layer.shadowOpacity = 0.25
            volumeBar.layer.shadowOffset = CGSize(width: 0, height: 2)

            lowVolume.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(lowVolume)
            lowVolume.rightAnchor.constraint(equalTo: volumeBar.leftAnchor, constant: -8).isActive = true
            lowVolume.centerYAnchor.constraint(equalTo: volumeBar.centerYAnchor).isActive = true
            lowVolume.widthAnchor.constraint(equalToConstant: 25).isActive = true
            lowVolume.heightAnchor.constraint(equalToConstant: 25).isActive = true

            highVolume.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(highVolume)
            highVolume.leftAnchor.constraint(equalTo: volumeBar.rightAnchor, constant: 8).isActive = true
            highVolume.centerYAnchor.constraint(equalTo: volumeBar.centerYAnchor).isActive = true
            highVolume.widthAnchor.constraint(equalToConstant: 25).isActive = true
            highVolume.heightAnchor.constraint(equalToConstant: 25).isActive = true

            hasSetupUI = true
        }
    }

    // MARK: - ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if rotationDirection == .CLOCKWISE {
            value = min(1.0, value + 0.05)
        } else {
            value = max(0.0, value - 0.05)
        }
        volumeBar.setProgress(value, animated: true)
        onValueChanged?(value)
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
            navigationController?.popViewController(animated: true)
        }
    }
}
