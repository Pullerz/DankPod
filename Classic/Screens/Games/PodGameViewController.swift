//
//  PodGameViewController.swift
//  Classic
//
//  Shared plumbing for the Extras > Games screens: frame loop, pause handling,
//  click wheel routing, nav bar HUD, overlays and high scores.
//

import UIKit

// MARK: - Style

/// Visual vocabulary shared by every game so they feel like they shipped on the same iPod.
enum GameStyle {
    static func font(_ size: CGFloat) -> UIFont { UIFont(name: "Helvetica-Bold", size: size)! }
    static func lightFont(_ size: CGFloat) -> UIFont { UIFont(name: "Helvetica", size: size)! }

    /// The iPod selection blue, used for highlights and overlays.
    static let selectionTop = UIColor.gradientLightBlue
    static let selectionBottom = UIColor.gradientDarkBlue
    static let overlayColor = UIColor(red: 40/255, green: 80/255, blue: 140/255, alpha: 0.85)

    /// Sky gradient used by Brick, Parachute and friends.
    static let skyTop = UIColor(red: 175/255, green: 215/255, blue: 245/255, alpha: 1)
    static let skyBottom = UIColor(red: 140/255, green: 185/255, blue: 230/255, alpha: 1)

    /// A vertical gradient layer, light at the top.
    static func gradientLayer(_ top: UIColor, _ bottom: UIColor, frame: CGRect) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.frame = frame
        g.colors = [top.cgColor, bottom.cgColor]
        g.startPoint = CGPoint(x: 0.5, y: 0)
        g.endPoint = CGPoint(x: 0.5, y: 1)
        return g
    }

    /// Glossy "lozenge" fill: lighter tint on top, darker tint below, with a hard
    /// specular band across the upper half — the 2007 Apple look.
    static func glossyLayer(_ color: UIColor, frame: CGRect, cornerRadius: CGFloat = 0) -> CALayer {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let light = UIColor(hue: h, saturation: max(s - 0.2, 0), brightness: min(b + 0.25, 1), alpha: a)
        let dark = UIColor(hue: h, saturation: min(s + 0.1, 1), brightness: max(b - 0.2, 0), alpha: a)
        let base = CAGradientLayer()
        base.frame = frame
        base.cornerRadius = cornerRadius
        base.masksToBounds = cornerRadius > 0
        base.colors = [light.cgColor, color.cgColor, dark.cgColor]
        base.locations = [0, 0.5, 1]
        let shine = CAGradientLayer()
        shine.frame = CGRect(x: 0, y: 0, width: frame.width, height: frame.height * 0.5)
        shine.colors = [UIColor(white: 1, alpha: 0.55).cgColor, UIColor(white: 1, alpha: 0.12).cgColor]
        base.addSublayer(shine)
        return base
    }

    /// A small shaded sphere (balls, orbs, lives).
    static func sphereView(diameter: CGFloat, color: UIColor = UIColor(white: 0.15, alpha: 1)) -> UIView {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        v.layer.cornerRadius = diameter / 2
        v.clipsToBounds = true
        v.backgroundColor = color
        let g = CAGradientLayer()
        g.type = .radial
        g.frame = v.bounds
        g.colors = [UIColor(white: 1, alpha: 0.9).cgColor, UIColor(white: 1, alpha: 0).cgColor]
        g.startPoint = CGPoint(x: 0.32, y: 0.28)
        g.endPoint = CGPoint(x: 1.0, y: 1.0)
        v.layer.addSublayer(g)
        return v
    }
}

// MARK: - High scores

enum HighScores {
    private static func key(_ game: String) -> String { "classic.games.best.\(game)" }

    static func best(for game: String) -> Int {
        UserDefaults.standard.integer(forKey: key(game))
    }

    /// Records `score` and returns true if it beat the previous best.
    @discardableResult
    static func submit(_ score: Int, for game: String) -> Bool {
        guard score > best(for: game) else { return false }
        UserDefaults.standard.set(score, forKey: key(game))
        return true
    }
}

// MARK: - Base controller

/// Subclass and override the hooks in the "Subclass hooks" section.
///
/// Lifecycle: `setupGame()` runs once when the view first has a real size,
/// `layoutGame()` whenever that size changes, and `update(dt:)` every frame
/// while the game is running (never while paused). Menu always leaves the game;
/// Play/Pause toggles the pause overlay.
class PodGameViewController: UIViewController, ClickWheelProtocol {

    /// Shown in the nav bar.
    var gameTitle: String { "Game" }
    /// Key under which high scores are stored.
    var scoreKey: String { gameTitle }
    /// Return false for turn-based games that don't need a frame loop.
    var usesFrameLoop: Bool { true }
    /// Return false if Play/Pause shouldn't pause (e.g. turn-based games).
    var canPause: Bool { usesFrameLoop }

    private(set) var isGamePaused = false
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var hasSetupGame = false
    private var lastLayoutSize: CGSize = .zero
    private var pauseLabel: UILabel?
    private var messageOverlay: UIView?

    /// Nav bar HUD passthroughs.
    var hudScore: Int? {
        get { AppDelegate.baseVC.navBarScore }
        set { AppDelegate.baseVC.navBarScore = newValue }
    }
    var hudLives: Int? {
        get { AppDelegate.baseVC.navBarBalls }
        set { AppDelegate.baseVC.navBarBalls = newValue }
    }

    // MARK: Subclass hooks

    func setupGame() {}
    func layoutGame() {}
    func update(dt: CGFloat) {}
    func wheelRotated(_ direction: RotationDirection) {}
    func selectPressed() {}
    func nextPressed() {}
    func previousPressed() {}
    /// Called when the HUD should be restored (on appear).
    func refreshHUD() {}
    /// Called when the player leaves via Menu.
    func gameWillExit() {}

    // Continuous wheel input — subclasses override both to opt in.
    var prefersContinuousWheelInput: Bool { false }
    func clickWheelDidRotateContinuously(event: ClickWheelRotationEvent) {}

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        view.backgroundColor = .black
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = gameTitle
        refreshHUD()
        if usesFrameLoop { startLoop() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopLoop()
        AppDelegate.baseVC.navBarScore = nil
        AppDelegate.baseVC.navBarBalls = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, size != lastLayoutSize else { return }
        lastLayoutSize = size
        if !hasSetupGame {
            hasSetupGame = true
            setupGame()
        }
        layoutGame()
        pauseLabel?.center = CGPoint(x: size.width / 2, y: size.height / 2)
        messageOverlay?.frame = view.bounds
    }

    deinit {
        displayLink?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Frame loop

    private func startLoop() {
        guard displayLink == nil else { return }
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard lastTimestamp > 0, !isGamePaused, hasSetupGame else { return }
        // Clamp so a hitch never tunnels objects through walls.
        let dt = CGFloat(min(link.timestamp - lastTimestamp, 1.0 / 30.0))
        update(dt: dt)
    }

    // MARK: Pause

    func setPaused(_ paused: Bool) {
        guard canPause, paused != isGamePaused else { return }
        isGamePaused = paused
        if paused {
            let label = UILabel()
            label.text = "PAUSED"
            label.textColor = .white
            label.font = GameStyle.font(18)
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.6
            label.layer.shadowRadius = 2
            label.layer.shadowOffset = CGSize(width: 0, height: 1)
            label.sizeToFit()
            label.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            view.addSubview(label)
            pauseLabel = label
        } else {
            pauseLabel?.removeFromSuperview()
            pauseLabel = nil
        }
    }

    @objc private func appWillResignActive() {
        if viewIfLoaded?.window != nil, hasSetupGame, messageOverlay == nil { setPaused(true) }
    }

    // MARK: Overlays

    var isShowingMessage: Bool { messageOverlay != nil }

    /// Full-screen translucent card in the iPod-blue style ("GAME OVER", "LEVEL 2", …).
    func showMessage(_ title: String, lines: [String] = [], color: UIColor = GameStyle.overlayColor) {
        hideMessage()
        let overlay = UIView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = color

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)
        stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor).isActive = true
        stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor).isActive = true
        stack.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, constant: -24).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = GameStyle.font(20)
        titleLabel.textColor = .white
        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(10, after: titleLabel)

        for (i, line) in lines.enumerated() {
            let l = UILabel()
            l.text = line
            l.numberOfLines = 0
            l.textAlignment = .center
            l.textColor = .white
            l.font = i == lines.count - 1 && lines.count > 1 ? GameStyle.lightFont(12) : GameStyle.font(14)
            stack.addArrangedSubview(l)
        }
        view.addSubview(overlay)
        messageOverlay = overlay
    }

    func hideMessage() {
        messageOverlay?.removeFromSuperview()
        messageOverlay = nil
    }

    /// Standard game-over card; records the high score.
    func showGameOver(score: Int, title: String = "GAME OVER") {
        let isBest = HighScores.submit(score, for: scoreKey)
        let best = HighScores.best(for: scoreKey)
        showMessage(title, lines: [
            "Score: \(score)",
            isBest && score > 0 ? "New High Score!" : "High Score: \(best)",
            "Press center to play again"
        ])
    }

    // MARK: ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        guard !isGamePaused else { return }
        wheelRotated(rotationDirection)
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        if isGamePaused { setPaused(false); return }
        selectPressed()
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        if canPause, messageOverlay == nil {
            setPaused(!isGamePaused)
        }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, !isGamePaused else { return }
        nextPressed()
    }

    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, !isGamePaused else { return }
        previousPressed()
    }

    func menuPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL || pressure == .FORCE else { return }
        stopLoop()
        gameWillExit()
        if pressure == .FORCE {
            navigationController?.popToRootViewController(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}
