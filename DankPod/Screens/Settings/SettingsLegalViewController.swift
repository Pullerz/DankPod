//
//  SettingsLegalViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class SettingsLegalViewController: UIViewController, ClickWheelProtocol {

    private let scrollView = UIScrollView()
    private let textView = UITextView()
    var hasSetupUI = false

    private static let legalText: String = """
DankPod
Copyright © 2020–2026 Apullen Developments Ltd.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

This application uses the Apple MediaPlayer framework.

MediaPlayer Framework
Copyright © Apple Inc. All rights reserved.

Use of the MediaPlayer framework is subject to the Apple Developer Program License Agreement and applicable Apple platform terms.

---

iPod and iPod classic are trademarks of Apple Inc., registered in the U.S. and other countries. DankPod is an independent fan project and is not affiliated with, endorsed by, or connected to Apple Inc. in any way.
"""

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Legal"
    }

    func setupUI() {
        if !hasSetupUI {
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scrollView)
            scrollView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            scrollView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            scrollView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.isEditable = false
            textView.isSelectable = false
            textView.font = UIFont.systemFont(ofSize: 12)
            textView.textColor = .black
            textView.backgroundColor = .white
            textView.text = SettingsLegalViewController.legalText
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
            scrollView.addSubview(textView)

            textView.topAnchor.constraint(equalTo: scrollView.topAnchor).isActive = true
            textView.leftAnchor.constraint(equalTo: scrollView.leftAnchor).isActive = true
            textView.rightAnchor.constraint(equalTo: scrollView.rightAnchor).isActive = true
            textView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor).isActive = true
            textView.widthAnchor.constraint(equalTo: scrollView.widthAnchor).isActive = true

            hasSetupUI = true
        }
    }

    // MARK: - ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        let offset: CGFloat = rotationDirection == .CLOCKWISE ? 20 : -20
        let currentY = scrollView.contentOffset.y
        let maxY = scrollView.contentSize.height - scrollView.frame.height
        let newY = max(0, min(maxY, currentY + offset))
        scrollView.setContentOffset(CGPoint(x: 0, y: newY), animated: false)
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

    func centerPressed(pressure: ClickWheelTouchPressure) {}
}
