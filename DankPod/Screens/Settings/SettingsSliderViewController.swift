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

    private let containerBar = UIView()
    private let fillView = UIView()
    private let leftLabel = UILabel()
    private let rightLabel = UILabel()
    private let percentLabel = UILabel()
    private var fillWidthConstraint: NSLayoutConstraint!

    var hasSetupUI = false

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = sliderTitle
        updateFill(animated: false)
    }

    func setupUI() {
        if !hasSetupUI {
            view.backgroundColor = .white

            // Left dim label
            leftLabel.translatesAutoresizingMaskIntoConstraints = false
            leftLabel.text = "◁"
            leftLabel.font = UIFont(name: "Helvetica-Bold", size: 18)
            leftLabel.textColor = .black
            view.addSubview(leftLabel)

            // Right bright label
            rightLabel.translatesAutoresizingMaskIntoConstraints = false
            rightLabel.text = "▷"
            rightLabel.font = UIFont(name: "Helvetica-Bold", size: 18)
            rightLabel.textColor = .black
            view.addSubview(rightLabel)

            // Grey container bar
            containerBar.translatesAutoresizingMaskIntoConstraints = false
            containerBar.backgroundColor = UIColor(white: 0.85, alpha: 1)
            containerBar.layer.cornerRadius = 4
            containerBar.clipsToBounds = true
            view.addSubview(containerBar)

            // Blue fill view (inside container)
            fillView.translatesAutoresizingMaskIntoConstraints = false
            containerBar.addSubview(fillView)

            // Percent label below bar
            percentLabel.translatesAutoresizingMaskIntoConstraints = false
            percentLabel.font = UIFont(name: "Helvetica-Bold", size: 14)
            percentLabel.textColor = .black
            percentLabel.textAlignment = .center
            view.addSubview(percentLabel)

            // Layout
            let margin: CGFloat = 15
            let barHeight: CGFloat = 8

            leftLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            leftLabel.leftAnchor.constraint(equalTo: view.leftAnchor, constant: margin).isActive = true

            rightLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            rightLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -margin).isActive = true

            containerBar.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            containerBar.leftAnchor.constraint(equalTo: leftLabel.rightAnchor, constant: 8).isActive = true
            containerBar.rightAnchor.constraint(equalTo: rightLabel.leftAnchor, constant: -8).isActive = true
            containerBar.heightAnchor.constraint(equalToConstant: barHeight).isActive = true

            fillView.topAnchor.constraint(equalTo: containerBar.topAnchor).isActive = true
            fillView.bottomAnchor.constraint(equalTo: containerBar.bottomAnchor).isActive = true
            fillView.leftAnchor.constraint(equalTo: containerBar.leftAnchor).isActive = true
            fillWidthConstraint = fillView.widthAnchor.constraint(equalTo: containerBar.widthAnchor, multiplier: CGFloat(value))
            fillWidthConstraint.isActive = true

            percentLabel.topAnchor.constraint(equalTo: containerBar.bottomAnchor, constant: 10).isActive = true
            percentLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true

            // Apply gradient to fill view after layout
            DispatchQueue.main.async {
                self.fillView.applyGradient(colours: [UIColor.gradientLightBlue, UIColor.gradientDarkBlue],
                                            startPoint: CGPoint(x: 0, y: 0),
                                            endPoint: CGPoint(x: 1, y: 0))
            }

            hasSetupUI = true
        }
    }

    private func updateFill(animated: Bool) {
        let clampedValue = max(0.0, min(1.0, value))
        let multiplier = CGFloat(clampedValue)

        // Reconstruct the width constraint (multiplier is immutable on existing constraints)
        fillWidthConstraint?.isActive = false
        fillWidthConstraint = fillView.widthAnchor.constraint(equalTo: containerBar.widthAnchor, multiplier: max(multiplier, 0.001))
        fillWidthConstraint.isActive = true

        percentLabel.text = "\(Int(clampedValue * 100))%"

        if animated {
            UIView.animate(withDuration: 0.05) {
                self.view.layoutIfNeeded()
            }
        } else {
            view.layoutIfNeeded()
        }

        onValueChanged?(clampedValue)
    }

    // MARK: - ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if rotationDirection == .CLOCKWISE {
            value = min(1.0, value + 0.05)
        } else {
            value = max(0.0, value - 0.05)
        }
        updateFill(animated: true)
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {}

    func previousSongPressed(pressure: ClickWheelTouchPressure) {}

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL || pressure == .FORCE {
            navigationController?.popViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            navigationController?.popViewController(animated: true)
        }
    }
}
