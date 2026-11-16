//
//  VortexViewController.swift
//  Classic
//
//  iPod Vortex (iPod classic / nano 3G, 2007): Breakout bent into a circle. A
//  slowly rotating cluster of brick rings sits at the centre of a round arena and
//  the paddle is an arc that orbits the outer wall — the click wheel maps 1:1 onto
//  it, so the wheel *is* the arena. As in the original, the ball slows as it dives
//  toward the cluster and picks up speed on the way back out. Later levels add
//  rings (shrinking the gap to the wall), two-hit and steel bricks, a faster ball
//  and a faster spin. Marked bricks release power-up capsules that drift outward.
//

import UIKit

class VortexViewController: PodGameViewController {

    private enum Phase { case waitingToLaunch, playing, levelCleared, gameOver }
    private enum BrickKind { case normal, tough, steel }

    private enum PowerKind: CaseIterable {
        case wide, slow, life, multi

        var letter: String {
            switch self {
            case .wide: return "W"
            case .slow: return "S"
            case .life: return "+"
            case .multi: return "M"
            }
        }

        var name: String {
            switch self {
            case .wide: return "WIDE PADDLE"
            case .slow: return "SLOW BALL"
            case .life: return "EXTRA BALL"
            case .multi: return "MULTI-BALL"
            }
        }

        var color: UIColor {
            switch self {
            case .wide: return UIColor(red: 0.25, green: 0.75, blue: 0.30, alpha: 1)
            case .slow: return UIColor(red: 0.25, green: 0.50, blue: 0.95, alpha: 1)
            case .life: return UIColor(red: 0.90, green: 0.25, blue: 0.30, alpha: 1)
            case .multi: return UIColor(red: 0.95, green: 0.65, blue: 0.15, alpha: 1)
            }
        }
    }

    private final class Brick {
        let layer: CALayer            // container holding the pieces below
        let body: CAShapeLayer
        let crack: CAShapeLayer
        let ring: Int
        let r0: CGFloat, r1: CGFloat
        let midAngle: CGFloat         // in cluster space
        let halfSpan: CGFloat
        let kind: BrickKind
        let color: UIColor
        let power: PowerKind?
        var hitsLeft: Int
        var alive = true
        init(layer: CALayer, body: CAShapeLayer, crack: CAShapeLayer, ring: Int, r0: CGFloat, r1: CGFloat,
             midAngle: CGFloat, halfSpan: CGFloat, kind: BrickKind, color: UIColor, power: PowerKind?) {
            self.layer = layer; self.body = body; self.crack = crack; self.ring = ring
            self.r0 = r0; self.r1 = r1; self.midAngle = midAngle; self.halfSpan = halfSpan
            self.kind = kind; self.color = color; self.power = power
            hitsLeft = kind == .tough ? 2 : 1
        }
    }

    private final class Ball {
        let view: UIView
        let trail: [CALayer]
        var pos: CGPoint              // arena space: origin at the centre of the arena
        var vel = CGVector.zero
        var history: [CGPoint] = []
        init(view: UIView, trail: [CALayer], pos: CGPoint) { self.view = view; self.trail = trail; self.pos = pos }
    }

    private final class Capsule {
        let view: UIView
        var r: CGFloat
        let angle: CGFloat
        let kind: PowerKind
        init(view: UIView, r: CGFloat, angle: CGFloat, kind: PowerKind) {
            self.view = view; self.r = r; self.angle = angle; self.kind = kind
        }
    }

    private struct Particle {
        let layer: CALayer
        var pos: CGPoint = .zero
        var vel: CGVector = .zero
        var life: CGFloat = 0
        var maxLife: CGFloat = 1
    }

    override var gameTitle: String { "Vortex" }

    // Game state
    private var phase: Phase = .waitingToLaunch
    private var score = 0
    private var lives = 3
    private var level = 1
    private var rallyTime: CGFloat = 0
    private var levelTimer: CGFloat = 0
    private var wideTimer: CGFloat = 0
    private var slowTimer: CGFloat = 0
    private var powerLabelTimer: CGFloat = 0
    private var clock: CGFloat = 0

    // Entities
    private var bricks: [Brick] = []
    private var balls: [Ball] = []
    private var capsules: [Capsule] = []
    private var particles: [Particle] = []

    // Cluster & paddle
    private var clusterAngle: CGFloat = 0
    private var clusterOuterRadius: CGFloat = 0
    private var ringCount = 3
    private var paddleAngle: CGFloat = .pi / 2     // unwrapped; 0 = right, increases clockwise
    private var paddleTarget: CGFloat = .pi / 2
    private var paddleHalf: CGFloat = 0.22         // half the arc's angular width, as drawn
    private var drawnPaddleHalf: CGFloat = -1
    private var paddleGlow: CGFloat = 0

    // Views & layers
    private var background: CAGradientLayer?
    private let starsNear = CAShapeLayer()
    private let starsFar = CAShapeLayer()
    private let wallLayer = CAShapeLayer()
    private let trackLayer = CAShapeLayer()
    private let clusterLayer = CALayer()
    private let coreGlow = CAGradientLayer()
    private var coreView: UIView!
    private let paddleLayer = CALayer()
    private let paddleGlowArc = CAShapeLayer()
    private let paddleBody = CAShapeLayer()
    private let paddleEdge = CAShapeLayer()
    private let paddleShine = CAShapeLayer()
    private let fxLayer = CALayer()
    private let levelLabel = UILabel()
    private let hintLabel = UILabel()
    private let powerLabel = UILabel()

    // Geometry (set in layoutGame)
    private var center: CGPoint = .zero
    private var arenaRadius: CGFloat = 150
    private var paddleRadius: CGFloat = 143

    // Layout
    private let ballRadius: CGFloat = 4
    private let coreRadius: CGFloat = 10
    private let firstRingRadius: CGFloat = 15
    private let ringThickness: CGFloat = 9
    private let ringGap: CGFloat = 2.5
    private let brickGap: CGFloat = 2.2            // points between bricks in a ring
    private let paddleThickness: CGFloat = 7
    private let paddleInset: CGFloat = 7           // wall radius minus paddle radius
    private let minClusterGap: CGFloat = 40        // never let the cluster crowd the paddle closer than this
    private let trailLength = 5
    private let particlePoolSize = 120

    // Tuning
    private let baseSpeed: CGFloat = 170
    private let levelSpeedStep: CGFloat = 0.08
    private let maxLevelSpeedMultiplier: CGFloat = 1.8
    private let innerSpeedFactor: CGFloat = 0.55   // speed at the centre relative to speed at the wall
    private let rallyRampPerSecond: CGFloat = 0.005
    private let maxRallyMultiplier: CGFloat = 1.4
    private let maxDeflection: CGFloat = 1.0       // ~57° off the radial at the arc's tips
    private let capsuleSpeed: CGFloat = 48
    private let powerChance: CGFloat = 0.09
    private let wideFactor: CGFloat = 1.6
    private let wideDuration: CGFloat = 12
    private let slowDuration: CGFloat = 10
    private let slowFactor: CGFloat = 0.7
    private let maxLives = 6
    private let maxBalls = 5

    // Inner to outer.
    private let ringColors: [UIColor] = [
        UIColor(red: 0.92, green: 0.27, blue: 0.62, alpha: 1),
        UIColor(red: 0.93, green: 0.26, blue: 0.24, alpha: 1),
        UIColor(red: 0.98, green: 0.56, blue: 0.16, alpha: 1),
        UIColor(red: 0.97, green: 0.84, blue: 0.20, alpha: 1),
        UIColor(red: 0.32, green: 0.80, blue: 0.30, alpha: 1),
        UIColor(red: 0.20, green: 0.76, blue: 0.82, alpha: 1),
        UIColor(red: 0.27, green: 0.50, blue: 0.96, alpha: 1),
        UIColor(red: 0.60, green: 0.36, blue: 0.92, alpha: 1),
    ]
    private let toughColor = UIColor(red: 0.90, green: 0.74, blue: 0.30, alpha: 1)
    private let steelColor = UIColor(red: 0.62, green: 0.65, blue: 0.70, alpha: 1)
    private let paddleColor = UIColor(red: 0.30, green: 0.62, blue: 1.0, alpha: 1)
    private let glowColor = UIColor(red: 0.45, green: 0.80, blue: 1.0, alpha: 1)

    // MARK: - Setup

    override func setupGame() {
        // Geometry is needed up front: the number of rings that fit depends on it.
        arenaRadius = min(view.bounds.width, view.bounds.height) / 2 - 4
        paddleRadius = arenaRadius - paddleInset

        let bg = CAGradientLayer()
        bg.type = .radial
        bg.colors = [UIColor(red: 0.10, green: 0.14, blue: 0.32, alpha: 1).cgColor,
                     UIColor(red: 0.04, green: 0.05, blue: 0.14, alpha: 1).cgColor,
                     UIColor(red: 0.01, green: 0.01, blue: 0.04, alpha: 1).cgColor]
        bg.locations = [0, 0.55, 1]
        bg.startPoint = CGPoint(x: 0.5, y: 0.5)
        bg.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(bg, at: 0)
        background = bg

        starsFar.fillColor = UIColor(white: 1, alpha: 0.35).cgColor
        starsNear.fillColor = UIColor(white: 1, alpha: 0.75).cgColor
        view.layer.addSublayer(starsFar)
        view.layer.addSublayer(starsNear)

        trackLayer.fillColor = nil
        trackLayer.strokeColor = UIColor(white: 1, alpha: 0.05).cgColor
        trackLayer.lineWidth = paddleThickness
        view.layer.addSublayer(trackLayer)

        wallLayer.fillColor = nil
        wallLayer.strokeColor = glowColor.withAlphaComponent(0.55).cgColor
        wallLayer.lineWidth = 1.5
        wallLayer.shadowColor = glowColor.cgColor
        wallLayer.shadowOpacity = 0.9
        wallLayer.shadowRadius = 4
        wallLayer.shadowOffset = .zero
        view.layer.addSublayer(wallLayer)

        coreGlow.type = .radial
        coreGlow.colors = [glowColor.withAlphaComponent(0.55).cgColor, glowColor.withAlphaComponent(0).cgColor]
        coreGlow.startPoint = CGPoint(x: 0.5, y: 0.5)
        coreGlow.endPoint = CGPoint(x: 1, y: 1)
        coreGlow.bounds = CGRect(x: 0, y: 0, width: coreRadius * 6, height: coreRadius * 6)
        view.layer.addSublayer(coreGlow)

        // Zero-sized containers: their sublayers draw in arena space around the centre.
        view.layer.addSublayer(clusterLayer)

        coreView = GameStyle.sphereView(diameter: coreRadius * 2, color: UIColor(red: 0.25, green: 0.6, blue: 0.95, alpha: 1))
        view.addSubview(coreView)

        for arc in [paddleGlowArc, paddleEdge, paddleBody, paddleShine] {
            arc.fillColor = nil
            arc.lineCap = .round
            paddleLayer.addSublayer(arc)
        }
        paddleGlowArc.strokeColor = glowColor.withAlphaComponent(0.25).cgColor
        paddleGlowArc.lineWidth = paddleThickness + 6
        paddleEdge.strokeColor = UIColor(red: 0.10, green: 0.25, blue: 0.60, alpha: 1).cgColor
        paddleEdge.lineWidth = paddleThickness + 1.5
        paddleBody.strokeColor = paddleColor.cgColor
        paddleBody.lineWidth = paddleThickness - 1
        paddleShine.strokeColor = UIColor(white: 1, alpha: 0.6).cgColor
        paddleShine.lineWidth = 2
        view.layer.addSublayer(paddleLayer)

        view.layer.addSublayer(fxLayer)
        for _ in 0..<particlePoolSize {
            let l = CALayer()
            l.isHidden = true
            fxLayer.addSublayer(l)
            particles.append(Particle(layer: l))
        }

        for label in [levelLabel, hintLabel, powerLabel] {
            label.textColor = UIColor(white: 1, alpha: 0.75)
            label.font = GameStyle.font(11)
            view.addSubview(label)
        }
        hintLabel.text = "Center to launch"
        hintLabel.textAlignment = .right
        hintLabel.font = GameStyle.lightFont(10)
        powerLabel.textAlignment = .right
        powerLabel.alpha = 0

        buildLevel()
        resetForLaunch()
    }

    override func layoutGame() {
        let b = view.bounds
        background?.frame = b
        fxLayer.frame = b
        center = CGPoint(x: b.midX, y: b.midY)
        arenaRadius = min(b.width, b.height) / 2 - 4
        paddleRadius = arenaRadius - paddleInset

        wallLayer.path = UIBezierPath(arcCenter: center, radius: arenaRadius, startAngle: 0,
                                      endAngle: 2 * .pi, clockwise: true).cgPath
        trackLayer.path = UIBezierPath(arcCenter: center, radius: paddleRadius, startAngle: 0,
                                       endAngle: 2 * .pi, clockwise: true).cgPath
        clusterLayer.position = center
        paddleLayer.position = center
        coreGlow.position = center
        coreView.center = center
        drawnPaddleHalf = -1
        updatePaddleShape()
        layoutStars()

        levelLabel.frame = CGRect(x: 8, y: 6, width: 90, height: 14)
        hintLabel.frame = CGRect(x: b.width - 108, y: b.height - 18, width: 100, height: 14)
        powerLabel.frame = CGRect(x: b.width - 128, y: 6, width: 120, height: 14)
        if phase == .waitingToLaunch { placeBallsOnPaddle() }
        render()
    }

    override func refreshHUD() {
        hudScore = score
        hudLives = lives
    }

    /// Deterministic star field so it doesn't reshuffle on relayout.
    private func layoutStars() {
        var seed: UInt32 = 0x2007
        func rand() -> CGFloat {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return CGFloat(seed >> 8) / CGFloat(1 << 24)
        }
        let b = view.bounds
        let far = UIBezierPath(), near = UIBezierPath()
        for i in 0..<90 {
            let p = CGPoint(x: rand() * b.width, y: rand() * b.height)
            let s: CGFloat = i % 3 == 0 ? 1.4 : 0.9
            (i % 3 == 0 ? near : far).append(UIBezierPath(ovalIn: CGRect(x: p.x, y: p.y, width: s, height: s)))
        }
        starsFar.path = far.cgPath
        starsNear.path = near.cgPath
    }

    // MARK: - Levels

    private var maxRings: Int {
        let room = paddleRadius - paddleThickness / 2 - minClusterGap - firstRingRadius + ringGap
        return max(2, Int(room / (ringThickness + ringGap)))
    }

    private var levelSpeed: CGFloat {
        baseSpeed * min(1 + levelSpeedStep * CGFloat(level - 1), maxLevelSpeedMultiplier)
    }

    private var clusterSpin: CGFloat {
        let speed = min(0.2 + 0.06 * CGFloat(level - 1), 0.75)
        return level % 2 == 0 ? -speed : speed
    }

    private var basePaddleHalf: CGFloat { max(0.15, 0.22 - 0.007 * CGFloat(level - 1)) }

    /// Later levels cut patterns into the rings so they play differently, not just faster.
    private func brickExists(ring k: Int, index i: Int, segments: Int) -> Bool {
        switch (level - 1) % 4 {
        case 1: return (i + k) % 4 != 0                                   // spiral
        case 2: return k == 0 || (i * 6 / segments) % 2 == 0              // pinwheel
        case 3: return i % 3 != 1 || k % 2 == 0                           // lattice
        default: return true                                              // solid
        }
    }

    private func kind(ring k: Int, index i: Int) -> BrickKind {
        let outer = ringCount - 1
        if level >= 3, k == 1, i % 3 == 0 { return .steel }
        if level >= 5, k == outer - 1, k > 1, i % 4 == 2 { return .steel }
        if level >= 2, level % 2 == 0, k == outer { return .tough }
        if level >= 3, level % 2 == 1, k == 0 { return .tough }
        if level >= 6, k == outer { return .tough }
        return .normal
    }

    private func buildLevel() {
        bricks.forEach { $0.layer.removeFromSuperlayer() }
        bricks.removeAll()
        ringCount = min(2 + level, maxRings)
        clusterAngle = 0
        for k in 0..<ringCount {
            let r0 = firstRingRadius + CGFloat(k) * (ringThickness + ringGap)
            let r1 = r0 + ringThickness
            let mid = (r0 + r1) / 2
            let segments = max(6, Int(2 * .pi * mid / 24))
            let span = 2 * .pi / CGFloat(segments)
            let half = span / 2 - brickGap / mid / 2
            let offset = k % 2 == 1 ? span / 2 : 0      // stagger alternate rings like brickwork
            for i in 0..<segments where brickExists(ring: k, index: i, segments: segments) {
                let kind = kind(ring: k, index: i)
                let color: UIColor
                switch kind {
                case .normal: color = ringColors[k % ringColors.count]
                case .tough: color = toughColor
                case .steel: color = steelColor
                }
                let power = kind != .steel && CGFloat.random(in: 0...1) < powerChance
                    ? weightedPower() : nil
                bricks.append(makeBrick(ring: k, r0: r0, r1: r1, mid: CGFloat(i) * span + offset, half: half,
                                        kind: kind, color: color, power: power))
            }
        }
        clusterOuterRadius = firstRingRadius + CGFloat(ringCount) * (ringThickness + ringGap)
        levelLabel.text = "LEVEL \(level)"
    }

    private func weightedPower() -> PowerKind {
        let roll = CGFloat.random(in: 0...1)
        if roll < 0.35 { return .wide }
        if roll < 0.65 { return .slow }
        if roll < 0.85 { return .multi }
        return .life
    }

    private func sector(r0: CGFloat, r1: CGFloat, a0: CGFloat, a1: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        p.addArc(withCenter: .zero, radius: r1, startAngle: a0, endAngle: a1, clockwise: true)
        p.addArc(withCenter: .zero, radius: r0, startAngle: a1, endAngle: a0, clockwise: false)
        p.close()
        return p
    }

    private func polar(_ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: cos(a) * r, y: sin(a) * r) }

    private func makeBrick(ring: Int, r0: CGFloat, r1: CGFloat, mid: CGFloat, half: CGFloat,
                           kind: BrickKind, color: UIColor, power: PowerKind?) -> Brick {
        let container = CALayer()
        let body = CAShapeLayer()
        body.path = sector(r0: r0, r1: r1, a0: mid - half, a1: mid + half).cgPath
        body.fillColor = color.cgColor
        body.strokeColor = color.vxShade(-0.35).cgColor
        body.lineWidth = 0.75
        container.addSublayer(body)

        // Glossy band across the outer half, and a soft shadow along the inner edge.
        let inset = 0.9 / r1
        let shine = CAShapeLayer()
        shine.path = sector(r0: r0 + (r1 - r0) * 0.5, r1: r1 - 1, a0: mid - half + inset, a1: mid + half - inset).cgPath
        shine.fillColor = UIColor(white: 1, alpha: kind == .steel ? 0.5 : 0.38).cgColor
        container.addSublayer(shine)
        let shade = CAShapeLayer()
        shade.path = sector(r0: r0 + 0.5, r1: r0 + 2.2, a0: mid - half + inset, a1: mid + half - inset).cgPath
        shade.fillColor = UIColor(white: 0, alpha: 0.2).cgColor
        container.addSublayer(shade)

        let rm = (r0 + r1) / 2
        if kind == .steel {
            // Rivets.
            let rivets = UIBezierPath()
            for a in [mid - half * 0.55, mid + half * 0.55] {
                let p = polar(rm, a)
                rivets.append(UIBezierPath(ovalIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)))
            }
            let rivetLayer = CAShapeLayer()
            rivetLayer.path = rivets.cgPath
            rivetLayer.fillColor = UIColor(white: 0.3, alpha: 1).cgColor
            container.addSublayer(rivetLayer)
        }

        let crackPath = UIBezierPath()
        crackPath.move(to: polar(r0 + 0.8, mid - half * 0.35))
        crackPath.addLine(to: polar(rm - 0.8, mid + half * 0.15))
        crackPath.addLine(to: polar(rm + 1.2, mid - half * 0.2))
        crackPath.addLine(to: polar(r1 - 0.8, mid + half * 0.4))
        crackPath.move(to: polar(rm - 0.8, mid + half * 0.15))
        crackPath.addLine(to: polar(rm + 0.5, mid + half * 0.6))
        let crack = CAShapeLayer()
        crack.path = crackPath.cgPath
        crack.fillColor = nil
        crack.strokeColor = UIColor(white: 0.1, alpha: 0.75).cgColor
        crack.lineWidth = 0.9
        crack.lineJoin = .round
        crack.isHidden = true
        container.addSublayer(crack)

        if power != nil {
            let p = polar(rm, mid)
            let marker = CAShapeLayer()
            marker.path = UIBezierPath(ovalIn: CGRect(x: p.x - 2.2, y: p.y - 2.2, width: 4.4, height: 4.4)).cgPath
            marker.fillColor = UIColor.white.cgColor
            marker.shadowColor = UIColor.white.cgColor
            marker.shadowOpacity = 1
            marker.shadowRadius = 2.5
            marker.shadowOffset = .zero
            container.addSublayer(marker)
        }

        clusterLayer.addSublayer(container)
        return Brick(layer: container, body: body, crack: crack, ring: ring, r0: r0, r1: r1, midAngle: mid,
                     halfSpan: half, kind: kind, color: color, power: power)
    }

    // MARK: - Balls

    private func makeBall(at pos: CGPoint) -> Ball {
        let v = GameStyle.sphereView(diameter: ballRadius * 2, color: UIColor(red: 0.82, green: 0.88, blue: 1, alpha: 1))
        view.insertSubview(v, aboveSubview: coreView)
        var trail: [CALayer] = []
        for i in 0..<trailLength {
            let l = CALayer()
            let d = ballRadius * 2 * (1 - CGFloat(i + 1) * 0.13)
            l.bounds = CGRect(x: 0, y: 0, width: d, height: d)
            l.cornerRadius = d / 2
            l.backgroundColor = glowColor.cgColor
            l.opacity = Float(0.35 * (1 - CGFloat(i) / CGFloat(trailLength)))
            l.isHidden = true
            view.layer.insertSublayer(l, below: coreView.layer)
            trail.append(l)
        }
        return Ball(view: v, trail: trail, pos: pos)
    }

    private func removeBall(_ ball: Ball) {
        ball.view.removeFromSuperview()
        ball.trail.forEach { $0.removeFromSuperlayer() }
    }

    private func clearCapsules() {
        capsules.forEach { $0.view.removeFromSuperview() }
        capsules.removeAll()
    }

    /// One ball resting on the paddle, power-ups and rally ramp reset.
    private func resetForLaunch() {
        balls.forEach(removeBall)
        balls = [makeBall(at: .zero)]
        clearCapsules()
        wideTimer = 0
        slowTimer = 0
        rallyTime = 0
        phase = .waitingToLaunch
        hintLabel.isHidden = false
        placeBallsOnPaddle()
    }

    private func placeBallsOnPaddle() {
        let r = paddleRadius - paddleThickness / 2 - ballRadius - 1
        for ball in balls {
            ball.pos = polar(r, paddleAngle)
            ball.history.removeAll()
        }
    }

    /// The original's signature feel: slow near the core, quick out by the wall.
    private func speed(at r: CGFloat) -> CGFloat {
        let radial = innerSpeedFactor + (1 - innerSpeedFactor) * min(r / paddleRadius, 1.05)
        let rally = min(1 + rallyRampPerSecond * rallyTime, maxRallyMultiplier)
        return levelSpeed * rally * (slowTimer > 0 ? slowFactor : 1) * radial
    }

    private func launch() {
        guard let ball = balls.first else { return }
        let a = paddleAngle + .pi + CGFloat.random(in: -0.15...0.15)
        let s = speed(at: paddleRadius)
        ball.vel = CGVector(dx: cos(a) * s, dy: sin(a) * s)
        phase = .playing
        hintLabel.isHidden = true
    }

    // MARK: - Frame loop

    override func update(dt: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clock += dt
        clusterAngle += clusterSpin * dt

        // Ease the drawn paddle onto the wheel's angle so it glides rather than jitters.
        paddleAngle += (paddleTarget - paddleAngle) * min(1, dt * 30)
        let targetHalf = basePaddleHalf * (wideTimer > 0 ? wideFactor : 1)
        paddleHalf += (targetHalf - paddleHalf) * min(1, dt * 8)
        paddleGlow = max(0, paddleGlow - dt * 3)
        updatePaddleShape()

        switch phase {
        case .waitingToLaunch:
            placeBallsOnPaddle()
        case .playing:
            rallyTime += dt
            wideTimer = max(0, wideTimer - dt)
            slowTimer = max(0, slowTimer - dt)
            updateBalls(dt)
            if phase == .playing { updateCapsules(dt) }
        case .levelCleared:
            levelTimer -= dt
            if levelTimer <= 0 { startNextLevel() }
        case .gameOver:
            break
        }
        updatePowerLabel(dt)
        updateParticles(dt)
        render()
        CATransaction.commit()
    }

    private func updateBalls(_ dt: CGFloat) {
        for ball in balls {
            // Sub-step so the ball never tunnels through a 9pt ring.
            let distance = hypot(ball.vel.dx, ball.vel.dy) * dt
            let steps = max(1, Int(ceil(distance / (ballRadius * 0.5))))
            let stepDt = dt / CGFloat(steps)
            for _ in 0..<steps {
                step(ball, dt: stepDt)
                if phase != .playing { return }
            }
        }

        // Lost balls: anything that slipped out past the wall.
        let lost = balls.filter { hypot($0.pos.x, $0.pos.y) > arenaRadius + ballRadius * 2 }
        guard !lost.isEmpty else { return }
        lost.forEach(removeBall)
        balls.removeAll { b in lost.contains { $0 === b } }
        if balls.isEmpty { loseLife() }
    }

    private func step(_ ball: Ball, dt: CGFloat) {
        var r = hypot(ball.pos.x, ball.pos.y)
        let s = speed(at: r)
        let current = hypot(ball.vel.dx, ball.vel.dy)
        if current > 0 {
            ball.vel.dx *= s / current
            ball.vel.dy *= s / current
        }
        ball.pos.x += ball.vel.dx * dt
        ball.pos.y += ball.vel.dy * dt
        r = hypot(ball.pos.x, ball.pos.y)
        guard r > 0.001 else { return }
        var n = CGVector(dx: ball.pos.x / r, dy: ball.pos.y / r)

        // Core: a solid sphere at the very centre.
        if r < coreRadius + ballRadius {
            reflect(ball, normal: n)
            ball.pos = CGPoint(x: n.dx * (coreRadius + ballRadius + 0.1), y: n.dy * (coreRadius + ballRadius + 0.1))
            jitter(ball, by: 0.06)
            return
        }

        // Bricks.
        if r - ballRadius < clusterOuterRadius {
            collideBricks(ball)
            r = hypot(ball.pos.x, ball.pos.y)
            n = CGVector(dx: ball.pos.x / r, dy: ball.pos.y / r)
        }

        // Paddle: only an outward-moving ball overlapping the arc's band can be returned.
        let inner = paddleRadius - paddleThickness / 2
        let outward = ball.vel.dx * n.dx + ball.vel.dy * n.dy
        if outward > 0, r + ballRadius >= inner, r - ballRadius <= paddleRadius + paddleThickness / 2 {
            let d = normalize(atan2(n.dy, n.dx) - paddleAngle)
            let reach = paddleHalf + (ballRadius + paddleThickness / 2) / paddleRadius
            if abs(d) <= reach {
                // Where it lands on the arc sets the angle — the tips send it wide.
                let offset = min(max(d / paddleHalf, -1), 1)
                let a = atan2(-n.dy, -n.dx) - offset * maxDeflection
                let speed = hypot(ball.vel.dx, ball.vel.dy)
                ball.vel = CGVector(dx: cos(a) * speed, dy: sin(a) * speed)
                let back = inner - ballRadius - 0.1
                ball.pos = CGPoint(x: n.dx * back, y: n.dy * back)
                paddleGlow = 1
                tick(.light, intensity: 0.5)
            }
        }
    }

    private func reflect(_ ball: Ball, normal n: CGVector) {
        let vn = ball.vel.dx * n.dx + ball.vel.dy * n.dy
        guard vn < 0 else { return }
        ball.vel.dx -= 2 * vn * n.dx
        ball.vel.dy -= 2 * vn * n.dy
    }

    /// A touch of randomness so the ball can't lock into a perfectly radial loop.
    private func jitter(_ ball: Ball, by amount: CGFloat) {
        let a = CGFloat.random(in: -amount...amount)
        let c = cos(a), s = sin(a)
        ball.vel = CGVector(dx: ball.vel.dx * c - ball.vel.dy * s, dy: ball.vel.dx * s + ball.vel.dy * c)
    }

    private func normalize(_ a: CGFloat) -> CGFloat {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x > .pi { x -= 2 * .pi }
        if x < -.pi { x += 2 * .pi }
        return x
    }

    /// Circle vs annular sector, in arena space. The contact normal is radial off a
    /// ring face, tangential off a brick's end, or toward the ball at a corner.
    private func collideBricks(_ ball: Ball) {
        let p = ball.pos
        let r = hypot(p.x, p.y)
        let theta = atan2(p.y, p.x)
        let rn = CGVector(dx: p.x / r, dy: p.y / r)
        for b in bricks where b.alive {
            guard r + ballRadius > b.r0, r - ballRadius < b.r1 else { continue }
            let mid = b.midAngle + clusterAngle
            let d = normalize(theta - mid)
            guard abs(d) <= b.halfSpan + ballRadius / r + 0.02 else { continue }

            // Closest point on the sector to the ball centre.
            let cp: CGPoint
            if abs(d) <= b.halfSpan {
                let cr = min(max(r, b.r0), b.r1)
                cp = CGPoint(x: rn.dx * cr, y: rn.dy * cr)
            } else {
                let ea = mid + (d > 0 ? b.halfSpan : -b.halfSpan)
                let e = CGVector(dx: cos(ea), dy: sin(ea))
                let along = min(max(p.x * e.dx + p.y * e.dy, b.r0), b.r1)
                cp = CGPoint(x: e.dx * along, y: e.dy * along)
            }
            let dx = p.x - cp.x, dy = p.y - cp.y
            let dist = hypot(dx, dy)

            let normal: CGVector
            if dist > 0.0001 {
                guard dist < ballRadius else { continue }
                normal = CGVector(dx: dx / dist, dy: dy / dist)
                ball.pos = CGPoint(x: cp.x + normal.dx * (ballRadius + 0.05), y: cp.y + normal.dy * (ballRadius + 0.05))
            } else {
                // Centre ended up inside the brick: leave by the shallowest face.
                let radialDepth = min(r - b.r0, b.r1 - r)
                let tangentialDepth = (b.halfSpan - abs(d)) * r
                if radialDepth <= tangentialDepth {
                    let outwardFace = b.r1 - r < r - b.r0
                    normal = outwardFace ? rn : CGVector(dx: -rn.dx, dy: -rn.dy)
                    let target = outwardFace ? b.r1 + ballRadius + 0.05 : b.r0 - ballRadius - 0.05
                    ball.pos = CGPoint(x: rn.dx * target, y: rn.dy * target)
                } else {
                    let t = CGVector(dx: -rn.dy, dy: rn.dx)   // direction of increasing angle
                    normal = d > 0 ? t : CGVector(dx: -t.dx, dy: -t.dy)
                    ball.pos.x += normal.dx * (tangentialDepth + ballRadius)
                    ball.pos.y += normal.dy * (tangentialDepth + ballRadius)
                }
            }
            reflect(ball, normal: normal)
            jitter(ball, by: 0.02)
            hit(b, contact: cp)
            return
        }
    }

    private func hit(_ b: Brick, contact: CGPoint) {
        if b.kind == .steel {
            emit(at: contact, count: 4, speed: 60, colors: [.white, steelColor], size: 1.6, life: 0.25)
            tick(.light, intensity: 0.3)
            return
        }
        b.hitsLeft -= 1
        if b.hitsLeft > 0 {
            b.crack.isHidden = false
            b.body.fillColor = b.color.vxShade(-0.18).cgColor
            emit(at: contact, count: 5, speed: 50, colors: [b.color, .white], size: 1.8, life: 0.3)
            award(5)
            tick(.light, intensity: 0.4)
            return
        }

        b.alive = false
        b.layer.isHidden = true
        let mid = b.midAngle + clusterAngle
        let rm = (b.r0 + b.r1) / 2
        let centerPoint = polar(rm, mid)
        emit(at: centerPoint, count: 10, speed: 70, colors: [b.color, b.color.vxShade(0.25), .white],
             size: 2.4, life: 0.5)
        award((b.kind == .tough ? 20 : 0) + 10 * (ringCount - b.ring))
        tick(.light, intensity: 0.5)
        if let power = b.power { spawnCapsule(power, r: rm, angle: mid) }

        if !bricks.contains(where: { $0.alive && $0.kind != .steel }) {
            levelCleared()
        }
    }

    private func award(_ points: Int) {
        score += points
        hudScore = score
    }

    // MARK: - Power-ups

    private func spawnCapsule(_ kind: PowerKind, r: CGFloat, angle: CGFloat) {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 11))
        v.layer.addSublayer(GameStyle.glossyLayer(kind.color, frame: v.bounds, cornerRadius: 5.5))
        v.layer.cornerRadius = 5.5
        v.layer.borderColor = UIColor(white: 1, alpha: 0.7).cgColor
        v.layer.borderWidth = 0.75
        let label = UILabel(frame: v.bounds)
        label.text = kind.letter
        label.font = GameStyle.font(9)
        label.textColor = .white
        label.textAlignment = .center
        v.addSubview(label)
        view.insertSubview(v, aboveSubview: coreView)
        let capsule = Capsule(view: v, r: r, angle: angle, kind: kind)
        capsules.append(capsule)
        v.center = toView(polar(r, angle))
    }

    private func updateCapsules(_ dt: CGFloat) {
        let inner = paddleRadius - paddleThickness / 2
        for c in capsules {
            c.r += capsuleSpeed * dt
            c.view.center = toView(polar(c.r, c.angle))
        }
        let caught = capsules.filter { c in
            c.r + 5 >= inner && c.r - 5 <= paddleRadius + paddleThickness / 2
                && abs(normalize(c.angle - paddleAngle)) <= paddleHalf + 0.08
        }
        for c in caught { apply(c.kind, at: c.view.center) }
        capsules.removeAll { c in
            let gone = caught.contains { $0 === c } || c.r > arenaRadius + 14
            if gone { c.view.removeFromSuperview() }
            return gone
        }
    }

    private func apply(_ kind: PowerKind, at point: CGPoint) {
        award(50)
        tick(.medium, intensity: 0.6)
        emit(at: CGPoint(x: point.x - center.x, y: point.y - center.y), count: 8, speed: 60,
             colors: [kind.color, .white], size: 2, life: 0.4)
        powerLabel.text = kind.name
        powerLabelTimer = 1.8
        switch kind {
        case .wide:
            wideTimer = wideDuration
        case .slow:
            slowTimer = slowDuration
        case .life:
            lives = min(lives + 1, maxLives)
            hudLives = lives
        case .multi:
            guard let source = balls.first else { return }
            for spread in [-0.45, 0.45] where balls.count < maxBalls {
                let extra = makeBall(at: source.pos)
                let c = cos(CGFloat(spread)), s = sin(CGFloat(spread))
                extra.vel = CGVector(dx: source.vel.dx * c - source.vel.dy * s,
                                     dy: source.vel.dx * s + source.vel.dy * c)
                balls.append(extra)
            }
        }
    }

    private func updatePowerLabel(_ dt: CGFloat) {
        guard powerLabelTimer > 0 else { return }
        powerLabelTimer -= dt
        powerLabel.alpha = min(1, powerLabelTimer / 0.4)
    }

    // MARK: - Flow

    private func loseLife() {
        lives -= 1
        hudLives = lives
        tick(.heavy, intensity: 0.8)
        if lives > 0 {
            resetForLaunch()
        } else {
            phase = .gameOver
            clearCapsules()
            hintLabel.isHidden = true
            showGameOver(score: score)
        }
    }

    private func levelCleared() {
        phase = .levelCleared
        let bonus = 100 * level
        award(bonus)
        balls.forEach(removeBall)
        balls.removeAll()
        clearCapsules()
        levelTimer = 1.6
        tick(.medium, intensity: 0.8)
        showMessage("LEVEL \(level + 1)", lines: ["Cluster cleared!", "Bonus +\(bonus)"])
    }

    private func startNextLevel() {
        hideMessage()
        level += 1
        buildLevel()
        resetForLaunch()
    }

    private func restart() {
        hideMessage()
        score = 0
        lives = 3
        level = 1
        refreshHUD()
        paddleTarget = paddleAngle
        buildLevel()
        resetForLaunch()
    }

    // MARK: - Rendering

    private func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: center.x + p.x, y: center.y + p.y) }

    private func render() {
        clusterLayer.setAffineTransform(CGAffineTransform(rotationAngle: clusterAngle))
        paddleLayer.setAffineTransform(CGAffineTransform(rotationAngle: paddleAngle))
        paddleGlowArc.opacity = Float(0.6 + 0.4 * paddleGlow)
        paddleGlowArc.lineWidth = paddleThickness + 6 + 4 * paddleGlow

        let pulse = 1 + 0.08 * sin(clock * 2.4)
        coreGlow.setAffineTransform(CGAffineTransform(scaleX: pulse, y: pulse))
        starsNear.opacity = Float(0.8 + 0.2 * sin(clock * 0.9))
        starsFar.opacity = Float(0.8 + 0.2 * sin(clock * 0.6 + 1.5))

        for ball in balls {
            ball.view.center = toView(ball.pos)
            ball.history.insert(ball.pos, at: 0)
            if ball.history.count > trailLength * 2 + 1 { ball.history.removeLast() }
            let moving = phase == .playing
            for (i, layer) in ball.trail.enumerated() {
                let idx = (i + 1) * 2
                layer.isHidden = !moving || idx >= ball.history.count
                if !layer.isHidden { layer.position = toView(ball.history[idx]) }
            }
        }
    }

    private func updatePaddleShape() {
        guard abs(paddleHalf - drawnPaddleHalf) > 0.0005 else { return }
        drawnPaddleHalf = paddleHalf
        func arc(_ radius: CGFloat) -> CGPath {
            UIBezierPath(arcCenter: .zero, radius: radius, startAngle: -paddleHalf, endAngle: paddleHalf,
                         clockwise: true).cgPath
        }
        paddleGlowArc.path = arc(paddleRadius)
        paddleEdge.path = arc(paddleRadius)
        paddleBody.path = arc(paddleRadius)
        paddleShine.path = arc(paddleRadius - paddleThickness * 0.18)
    }

    // MARK: - Effects

    /// `p` is in arena space.
    private func emit(at p: CGPoint, count: Int, speed: CGFloat, colors: [UIColor], size: CGFloat, life: CGFloat) {
        var remaining = count
        let origin = toView(p)
        for i in particles.indices where particles[i].life <= 0 {
            guard remaining > 0 else { break }
            remaining -= 1
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let v = speed * CGFloat.random(in: 0.3...1)
            let s = size * CGFloat.random(in: 0.7...1.3)
            particles[i].pos = origin
            particles[i].vel = CGVector(dx: cos(angle) * v, dy: sin(angle) * v)
            particles[i].maxLife = life * CGFloat.random(in: 0.7...1.2)
            particles[i].life = particles[i].maxLife
            let l = particles[i].layer
            l.bounds = CGRect(x: 0, y: 0, width: s, height: s)
            l.cornerRadius = s / 3
            l.backgroundColor = colors.randomElement()?.cgColor
            l.position = origin
            l.opacity = 1
            l.isHidden = false
        }
    }

    private func updateParticles(_ dt: CGFloat) {
        for i in particles.indices where particles[i].life > 0 {
            particles[i].life -= dt
            if particles[i].life <= 0 { particles[i].layer.isHidden = true; continue }
            let drag = 1 - min(1, dt * 2.5)
            particles[i].vel.dx *= drag
            particles[i].vel.dy *= drag
            particles[i].pos.x += particles[i].vel.dx * dt
            particles[i].pos.y += particles[i].vel.dy * dt
            particles[i].layer.position = particles[i].pos
            particles[i].layer.opacity = Float(min(1, particles[i].life / particles[i].maxLife * 1.5))
        }
    }

    private func tick(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        guard SettingsStore.shared.clickerEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
    }

    // MARK: - Input

    // The wheel is the arena: one degree of wheel moves the paddle one degree round the wall.
    override var prefersContinuousWheelInput: Bool { true }

    override func clickWheelDidRotateContinuously(event: ClickWheelRotationEvent) {
        guard !isGamePaused, event.state == .changed, phase != .gameOver else { return }
        paddleTarget += event.deltaRadians
    }

    override func selectPressed() {
        switch phase {
        case .waitingToLaunch: launch()
        case .gameOver: restart()
        case .playing, .levelCleared: break
        }
    }
}

private extension UIColor {
    /// Brightness nudged up (positive) or down (negative).
    func vxShade(_ amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: min(max(b + amount, 0), 1), alpha: a)
    }
}
