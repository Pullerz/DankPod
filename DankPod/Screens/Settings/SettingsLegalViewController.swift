//
//  SettingsLegalViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class SettingsLegalViewController: UIViewController, ClickWheelProtocol {

    private let textView = UITextView()
    var hasSetupUI = false

    private static let legalText: String = """
DankPod
Copyright © 2020–2026 Apullen Developments Ltd.
All rights reserved. Some rights imagined.

TERMS AND CONDITIONS OF USE

By scrolling past this point you have entered into a binding spiritual agreement with Apullen Developments Ltd. ("we", "us", "the lads"). There is no way to undo this. We're sorry.

1. DEFINITIONS

"The Software" refers to this application, which is, for all intents and purposes, a small rectangle that pretends to be a larger rectangle from 2005.

"The User" refers to you, the person who has voluntarily chosen to relive an era in which 1,000 songs was considered an almost unreasonable quantity of music.

"The Click Wheel" refers to the circular input mechanism that you are now operating with a touchscreen, which rather defeats the point but here we are.

2. GRANT OF LICENCE

We grant you a non-exclusive, non-transferable, entirely sentimental licence to use this Software for the purpose of feeling a bit nostalgic. This licence does not entitle you to claim you "always preferred the iPod Classic, actually" at dinner parties, though we recognise we cannot stop you.

3. INTELLECTUAL PROPERTY

This application is not an iPod. It has never been an iPod. If you hold it up to the light at the right angle it still won't be an iPod. iPod, iPod classic, and the general concept of having a dedicated music player instead of just using your phone are trademarks of Apple Inc.

We have no affiliation with Apple Inc. We once walked past an Apple Store, but felt that was insufficient grounds for a partnership.

4. WARRANTY DISCLAIMER

THE SOFTWARE IS PROVIDED "AS IS", WHICH IS TO SAY, IN ROUGHLY THE CONDITION YOU'D EXPECT FROM SOMETHING BUILT FOR A LAUGH.

We make no warranty, express or implied, that this application will:

(a) play music in a manner distinguishable from your normal Music app;
(b) successfully recreate the experience of having your earphone cable caught on a door handle;
(c) function at all on Tuesdays.

5. LIMITATION OF LIABILITY

Under no circumstances shall the developers be liable for any damages arising from:

(a) the realisation that your music taste hasn't changed since 2007;
(b) the faint sadness of navigating to "Extras" and finding nothing there;
(c) explaining to a younger person what a click wheel was;
(d) any existential crisis triggered by the phrase "1 of 1,247".

Our total liability in all cases shall not exceed the amount you paid for this Software, which, if memory serves, was nothing.

6. DATA COLLECTION

We collect absolutely no data. We don't know who you are. We don't know what you're listening to. Frankly, we'd rather not.

7. GOVERNING LAW

This agreement shall be governed by the laws of England and Wales, primarily because it sounds more authoritative than saying "we haven't actually thought about this".

Any disputes shall be resolved by means of a strongly worded letter, followed by an awkward silence, followed by everyone agreeing to just leave it.

8. SEVERABILITY

If any provision of this agreement is found to be unenforceable, it shall be replaced with something equally pointless.

9. ENTIRE AGREEMENT

This constitutes the entire agreement between you and us. There is no other agreement. If someone told you there was another agreement, they were mistaken, or possibly having you on.

10. ACKNOWLEDGEMENTS

This application uses the Apple MediaPlayer framework.
Copyright © Apple Inc. All rights reserved.

Special thanks to the iPod Classic (2001–2014), which did nothing wrong and was taken from us too soon.

Last updated: ages ago, probably.
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
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.isEditable = false
            textView.isSelectable = false
            textView.isScrollEnabled = true
            textView.font = UIFont.systemFont(ofSize: 12)
            textView.textColor = .black
            textView.backgroundColor = .white
            textView.text = SettingsLegalViewController.legalText
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
            view.addSubview(textView)

            textView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            textView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            textView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

            hasSetupUI = true
        }
    }

    // MARK: - ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        let offset: CGFloat = rotationDirection == .CLOCKWISE ? 20 : -20
        let currentY = textView.contentOffset.y
        let maxY = textView.contentSize.height - textView.frame.height
        let newY = max(0, min(maxY, currentY + offset))
        textView.setContentOffset(CGPoint(x: 0, y: newY), animated: false)
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
