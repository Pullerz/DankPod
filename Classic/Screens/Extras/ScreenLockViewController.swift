//
//  ScreenLockViewController.swift
//  Classic
//

import UIKit

// MARK: - Store

/// Screen Lock persistence.
/// NOTE: the combination is kept in plain UserDefaults. That's fine for an iPod emulator —
/// it's a toy lock, not a security boundary — but don't copy this for anything real
/// (that would belong in the Keychain).
enum ScreenLockStore {
    private static let combinationKey = "classic.screenlock.combination"
    private static let lockedKey = "classic.screenlock.locked"

    /// Four digits, e.g. "0427"; nil until the user has set one.
    static var combination: String? {
        get {
            guard let c = UserDefaults.standard.string(forKey: combinationKey),
                  c.count == 4, c.allSatisfy({ $0.isNumber }) else { return nil }
            return c
        }
        set { UserDefaults.standard.set(newValue, forKey: combinationKey) }
    }

    /// Persisted so killing the app doesn't bypass the lock (see MainViewController.viewDidLoad).
    static var isLocked: Bool {
        get { UserDefaults.standard.bool(forKey: lockedKey) && combination != nil }
        set { UserDefaults.standard.set(newValue, forKey: lockedKey) }
    }
}

// MARK: - Screen

/// Extras ▸ Screen Lock. A "Lock" / "Set Combination" list; combinations are dialled with
/// the wheel one digit at a time (Center confirms and moves right, Previous steps back).
/// While locked, Menu is ignored and Play/Pause still controls music.
class ScreenLockViewController: UIViewController, ClickWheelProtocol {
    private enum Mode { case menu, setting, locked }

    private var mode: Mode = .menu
    /// True when pushed by MainViewController at launch because the app was killed while locked.
    private var launchedLocked = false
    private var hasAppeared = false
    /// Ignores input during the short "set"/"unlocked"/shake transitions.
    private var isBusy = false

    // Menu list
    private let tableView = UITableView()
    private let menuItems = ["Lock", "Set Combination"]
    private var counter = 0

    // Combination panel
    private let panel = UIView()
    private let padlock = ScreenLockPadlockView()
    private let promptLabel = UILabel()
    private let boxesRow = UIStackView()
    private var boxes: [CombinationDigitView] = []
    private let hintLabel = UILabel()
    private var digits = [0, 0, 0, 0]
    private var activeIndex = 0

    /// Use `ScreenLockViewController(locked: true)` to show the lock screen directly.
    convenience init(locked: Bool) {
        self.init(nibName: nil, bundle: nil)
        launchedLocked = locked
    }

    // MARK: Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        if !hasAppeared {
            hasAppeared = true
            if ScreenLockStore.isLocked || (launchedLocked && ScreenLockStore.combination != nil) {
                enter(.locked)
            } else if ScreenLockStore.combination == nil {
                // First time: go straight to choosing a combination.
                enter(.setting)
            } else {
                enter(.menu)
            }
        } else {
            updateTitle()
        }
    }

    private func setupUI() {
        guard tableView.superview == nil else { return }
        view.backgroundColor = .white

        // List
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .white
        view.addSubview(tableView)

        // Panel
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = .white
        view.addSubview(panel)

        padlock.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(padlock)

        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        promptLabel.font = UIFont(name: "Helvetica-Bold", size: 15)
        promptLabel.textColor = .black
        promptLabel.textAlignment = .center
        panel.addSubview(promptLabel)

        boxesRow.translatesAutoresizingMaskIntoConstraints = false
        boxesRow.axis = .horizontal
        boxesRow.spacing = 10
        boxesRow.distribution = .fillEqually
        for _ in 0..<4 {
            let box = CombinationDigitView()
            box.translatesAutoresizingMaskIntoConstraints = false
            boxes.append(box)
            boxesRow.addArrangedSubview(box)
        }
        panel.addSubview(boxesRow)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = UIFont(name: "Helvetica-Bold", size: 11)
        hintLabel.textColor = UIColor(white: 0.5, alpha: 1)
        hintLabel.textAlignment = .center
        hintLabel.text = "Scroll to choose a number, press Center to enter"
        hintLabel.adjustsFontSizeToFitWidth = true
        hintLabel.minimumScaleFactor = 0.7
        panel.addSubview(hintLabel)

        let boxHeight = boxesRow.heightAnchor.constraint(equalTo: panel.heightAnchor, multiplier: 0.19)
        boxHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.leftAnchor.constraint(equalTo: view.leftAnchor),
            panel.rightAnchor.constraint(equalTo: view.rightAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            padlock.topAnchor.constraint(equalTo: panel.topAnchor, constant: 26),   // headroom for the lifted shackle
            padlock.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            padlock.heightAnchor.constraint(equalTo: panel.heightAnchor, multiplier: 0.34),
            padlock.widthAnchor.constraint(equalTo: padlock.heightAnchor, multiplier: 0.9),

            promptLabel.topAnchor.constraint(equalTo: padlock.bottomAnchor, constant: 8),
            promptLabel.leftAnchor.constraint(equalTo: panel.leftAnchor, constant: 10),
            promptLabel.rightAnchor.constraint(equalTo: panel.rightAnchor, constant: -10),

            boxesRow.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 8),
            boxesRow.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            boxHeight,
            boxesRow.heightAnchor.constraint(lessThanOrEqualToConstant: 56),
            boxes[0].widthAnchor.constraint(equalTo: boxes[0].heightAnchor, multiplier: 0.8),

            hintLabel.leftAnchor.constraint(equalTo: panel.leftAnchor, constant: 10),
            hintLabel.rightAnchor.constraint(equalTo: panel.rightAnchor, constant: -10),
            hintLabel.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -6),
            hintLabel.topAnchor.constraint(greaterThanOrEqualTo: boxesRow.bottomAnchor, constant: 4),
        ])
    }

    // MARK: Modes

    private func enter(_ newMode: Mode) {
        mode = newMode
        isBusy = false
        switch newMode {
        case .menu:
            tableView.isHidden = false
            panel.isHidden = true
            counter = max(0, min(counter, menuItems.count - 1))
            tableView.reloadData()
            tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
        case .setting:
            tableView.isHidden = true
            panel.isHidden = false
            padlock.setOpen(true, animated: false)
            promptLabel.text = "Enter New Combination"
            resetDigits()
        case .locked:
            ScreenLockStore.isLocked = true
            tableView.isHidden = true
            panel.isHidden = false
            padlock.setOpen(false, animated: false)
            promptLabel.text = "Enter Combination"
            resetDigits()
        }
        updateTitle()
    }

    private func updateTitle() {
        AppDelegate.baseVC.navBarTitle = mode == .locked ? "Locked" : "Screen Lock"
    }

    private func resetDigits() {
        digits = [0, 0, 0, 0]
        activeIndex = 0
        for (i, box) in boxes.enumerated() {
            box.setDigit(0, direction: 0)
            box.isActive = i == activeIndex
        }
    }

    private func moveActive(to index: Int) {
        activeIndex = index
        for (i, box) in boxes.enumerated() { box.isActive = i == activeIndex }
    }

    private func combinationComplete() {
        let code = digits.map(String.init).joined()
        isBusy = true
        for box in boxes { box.isActive = false }
        switch mode {
        case .setting:
            ScreenLockStore.combination = code
            promptLabel.text = "Combination Set"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self, self.mode == .setting else { return }
                self.counter = 0   // highlight "Lock"
                self.enter(.menu)
            }
        case .locked:
            if code == ScreenLockStore.combination {
                ScreenLockStore.isLocked = false
                promptLabel.text = "Unlocked"
                padlock.setOpen(true, animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                    guard let self = self, let nav = self.navigationController else { return }
                    // Back to where the user came from; to the root if we launched locked.
                    // Pop to the screen *below* this one rather than popping the top: an alarm
                    // card may have been pushed over the lock during the 0.55 s delay.
                    if self.launchedLocked {
                        nav.popToRootViewController(animated: true)
                    } else if let idx = nav.viewControllers.firstIndex(of: self), idx > 0 {
                        nav.popToViewController(nav.viewControllers[idx - 1], animated: true)
                    }
                }
            } else {
                wrongCombination()
            }
        case .menu:
            break
        }
    }

    private func wrongCombination() {
        if SettingsStore.shared.clickerEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        promptLabel.text = "Wrong Combination"
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -14, 12, -10, 8, -5, 3, 0]
        shake.duration = 0.45
        shake.timingFunction = CAMediaTimingFunction(name: .easeOut)
        boxesRow.layer.add(shake, forKey: "shake")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, self.mode == .locked else { return }
            self.isBusy = false
            self.promptLabel.text = "Enter Combination"
            self.resetDigits()
        }
    }

    // MARK: ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        switch mode {
        case .menu:
            if rotationDirection == .CLOCKWISE {
                guard counter < menuItems.count - 1 else { return }
                counter += 1
            } else {
                guard counter > 0 else { return }
                counter -= 1
            }
            tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
        case .setting, .locked:
            guard !isBusy else { return }
            let step = rotationDirection == .CLOCKWISE ? 1 : -1
            digits[activeIndex] = (digits[activeIndex] + step + 10) % 10
            boxes[activeIndex].setDigit(digits[activeIndex], direction: step)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        switch mode {
        case .menu:
            if counter == 0 {
                enter(ScreenLockStore.combination == nil ? .setting : .locked)
            } else {
                enter(.setting)
            }
        case .setting, .locked:
            guard !isBusy else { return }
            if activeIndex < 3 {
                moveActive(to: activeIndex + 1)
            } else {
                combinationComplete()
            }
        }
    }

    /// Previous steps back a digit while dialling.
    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, mode != .menu, !isBusy, activeIndex > 0 else { return }
        moveActive(to: activeIndex - 1)
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {}

    /// Music keeps working, even while locked (as on the iPod).
    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        }
    }

    func menuPressed(pressure: ClickWheelTouchPressure) {
        switch mode {
        case .locked:
            return   // Menu (and force-Menu) do nothing while locked.
        case .setting:
            guard pressure == .NORMAL || pressure == .FORCE else { return }
            if pressure == .NORMAL && ScreenLockStore.combination != nil {
                enter(.menu)   // cancel, back to the list
            } else if pressure == .FORCE {
                navigationController?.popToRootViewController(animated: true)
            } else {
                navigationController?.popViewController(animated: true)
            }
        case .menu:
            if pressure == .NORMAL {
                navigationController?.popViewController(animated: true)
            } else if pressure == .FORCE {
                navigationController?.popToRootViewController(animated: true)
            }
        }
    }
}

extension ScreenLockViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { menuItems.count }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 30 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = menuItems[indexPath.row]
        cell.selectionStyle = .none
        return cell
    }
}

// MARK: - Digit box

/// A glossy rounded box holding one combination digit; iPod blue when active.
private final class CombinationDigitView: UIView {
    var isActive = false { didSet { applyStyle() } }

    private let fill = CAGradientLayer()
    private let gloss = CAGradientLayer()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 1.5
        layer.shadowOffset = CGSize(width: 0, height: 1)
        fill.cornerRadius = 6
        fill.masksToBounds = true
        layer.addSublayer(fill)
        gloss.colors = [UIColor(white: 1, alpha: 0.6).cgColor, UIColor(white: 1, alpha: 0.12).cgColor]
        gloss.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        gloss.cornerRadius = 5
        layer.addSublayer(gloss)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.text = "0"
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
        ])
        clipsToBounds = false
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        gloss.frame = CGRect(x: 1, y: 1, width: bounds.width - 2, height: bounds.height * 0.48)
        CATransaction.commit()
        label.font = UIFont(name: "Helvetica-Bold", size: max(12, bounds.height * 0.62))
    }

    /// `direction` +1/-1 rolls the new digit in like a combination wheel; 0 sets it instantly.
    func setDigit(_ digit: Int, direction: Int) {
        if direction != 0 {
            let roll = CATransition()
            roll.type = .push
            roll.subtype = direction > 0 ? .fromTop : .fromBottom
            roll.duration = 0.09
            label.layer.add(roll, forKey: "roll")
        }
        label.text = "\(digit)"
    }

    private func applyStyle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isActive {
            fill.colors = [UIColor.gradientLightBlue.cgColor, UIColor.gradientDarkBlue.cgColor]
            layer.borderColor = UIColor(red: 40/255, green: 95/255, blue: 170/255, alpha: 1).cgColor
            label.textColor = .white
            label.shadowColor = UIColor(white: 0, alpha: 0.3)
            label.shadowOffset = CGSize(width: 0, height: -1)
        } else {
            fill.colors = [UIColor.white.cgColor, UIColor(white: 0.92, alpha: 1).cgColor, UIColor(white: 0.8, alpha: 1).cgColor]
            layer.borderColor = UIColor(white: 0.55, alpha: 1).cgColor
            label.textColor = .black
            label.shadowColor = UIColor(white: 1, alpha: 0.8)
            label.shadowOffset = CGSize(width: 0, height: 1)
        }
        CATransaction.commit()
    }
}

// MARK: - Padlock

/// A shaded chrome padlock with a dark keyhole, built from layers so the shackle can lift.
private final class ScreenLockPadlockView: UIView {
    private let shackleContainer = CALayer()
    private let shackleOutline = CAShapeLayer()
    private let shackleChrome = CAGradientLayer()
    private let shackleMask = CAShapeLayer()
    private let bodyShadow = CALayer()
    private let body = CAGradientLayer()
    private let bodyShine = CAGradientLayer()
    private let keyhole = CAShapeLayer()
    private let keyholeLip = CAShapeLayer()
    private var isOpen = false
    private var shackleLift: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        shackleOutline.fillColor = nil
        shackleOutline.strokeColor = UIColor(white: 0.38, alpha: 1).cgColor
        shackleOutline.lineCap = .butt
        shackleContainer.addSublayer(shackleOutline)
        shackleChrome.colors = [UIColor(white: 0.55, alpha: 1), UIColor(white: 0.97, alpha: 1),
                                UIColor(white: 0.7, alpha: 1), UIColor(white: 0.92, alpha: 1),
                                UIColor(white: 0.5, alpha: 1)].map { $0.cgColor }
        shackleChrome.startPoint = CGPoint(x: 0, y: 0.5)
        shackleChrome.endPoint = CGPoint(x: 1, y: 0.5)
        shackleMask.fillColor = nil
        shackleMask.strokeColor = UIColor.black.cgColor
        shackleMask.lineCap = .butt
        shackleChrome.mask = shackleMask
        shackleContainer.addSublayer(shackleChrome)
        layer.addSublayer(shackleContainer)

        bodyShadow.shadowColor = UIColor.black.cgColor
        bodyShadow.shadowOpacity = 0.35
        bodyShadow.shadowRadius = 2.5
        bodyShadow.shadowOffset = CGSize(width: 0, height: 2)
        layer.addSublayer(bodyShadow)

        body.colors = [UIColor(white: 0.96, alpha: 1), UIColor(white: 0.78, alpha: 1),
                       UIColor(white: 0.66, alpha: 1), UIColor(white: 0.84, alpha: 1),
                       UIColor(white: 0.58, alpha: 1)].map { $0.cgColor }
        body.locations = [0, 0.45, 0.5, 0.8, 1]
        body.borderColor = UIColor(white: 0.4, alpha: 1).cgColor
        body.borderWidth = 1
        body.masksToBounds = true
        layer.addSublayer(body)
        bodyShine.colors = [UIColor(white: 1, alpha: 0.7).cgColor, UIColor(white: 1, alpha: 0.1).cgColor]
        body.addSublayer(bodyShine)

        keyholeLip.fillColor = nil
        keyholeLip.strokeColor = UIColor(white: 1, alpha: 0.7).cgColor
        body.addSublayer(keyholeLip)
        keyhole.fillColor = UIColor(white: 0.12, alpha: 1).cgColor
        keyhole.strokeColor = UIColor(white: 0.3, alpha: 1).cgColor
        keyhole.lineWidth = 0.5
        body.addSublayer(keyhole)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Body occupies the lower ~55%; the shackle arcs above it.
        var bh = h * 0.56
        var bw = bh * 1.3
        if bw > w { bw = w; bh = bw / 1.3 }
        let bodyRect = CGRect(x: (w - bw) / 2, y: h - bh, width: bw, height: bh)
        body.frame = bodyRect
        body.cornerRadius = bw * 0.1
        bodyShadow.frame = bodyRect
        bodyShadow.shadowPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: bodyRect.size), cornerRadius: bw * 0.1).cgPath
        bodyShine.frame = CGRect(x: 0, y: 0, width: bw, height: bh * 0.42)

        // Shackle: a U of thickness t, legs sunk into the body.
        let t = bw * 0.13
        let r = bw * 0.29
        let top = t / 2 + 1
        let legBottom = bodyRect.minY + bh * 0.12
        shackleContainer.frame = bounds
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w / 2 - r, y: legBottom))
        path.addLine(to: CGPoint(x: w / 2 - r, y: top + r))
        path.addArc(withCenter: CGPoint(x: w / 2, y: top + r), radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: w / 2 + r, y: legBottom))
        shackleOutline.path = path.cgPath
        shackleOutline.lineWidth = t + 1.5
        shackleMask.path = path.cgPath
        shackleMask.lineWidth = t
        shackleChrome.frame = bounds
        shackleMask.frame = shackleChrome.bounds
        // The horizontal chrome gradient should read across each leg; stretch it over the shackle width.
        let left = (w / 2 - r - t / 2) / w, right = (w / 2 + r + t / 2) / w
        shackleChrome.startPoint = CGPoint(x: left, y: 0.5)
        shackleChrome.endPoint = CGPoint(x: right, y: 0.5)
        shackleChrome.locations = [0, 0.06, 0.1, 0.9, 1].map { NSNumber(value: $0) }
        shackleLift = r * 0.6
        shackleContainer.setAffineTransform(isOpen ? CGAffineTransform(translationX: 0, y: -shackleLift) : .identity)

        // Keyhole: circle over a tapered slot, with a light lip under it for depth.
        let kr = bw * 0.085
        let kc = CGPoint(x: bw / 2, y: bh * 0.42)
        let hole = UIBezierPath(ovalIn: CGRect(x: kc.x - kr, y: kc.y - kr, width: kr * 2, height: kr * 2))
        let slot = UIBezierPath()
        slot.move(to: CGPoint(x: kc.x - kr * 0.45, y: kc.y + kr * 0.3))
        slot.addLine(to: CGPoint(x: kc.x - kr * 0.8, y: kc.y + kr * 2.6))
        slot.addLine(to: CGPoint(x: kc.x + kr * 0.8, y: kc.y + kr * 2.6))
        slot.addLine(to: CGPoint(x: kc.x + kr * 0.45, y: kc.y + kr * 0.3))
        slot.close()
        hole.append(slot)
        hole.usesEvenOddFillRule = false
        keyhole.path = hole.cgPath
        keyholeLip.path = hole.cgPath
        keyholeLip.lineWidth = 1
        keyholeLip.setAffineTransform(CGAffineTransform(translationX: 0, y: 1))

        CATransaction.commit()
    }

    func setOpen(_ open: Bool, animated: Bool) {
        isOpen = open
        let transform = open ? CGAffineTransform(translationX: 0, y: -shackleLift) : .identity
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        shackleContainer.setAffineTransform(transform)
        CATransaction.commit()
    }
}
