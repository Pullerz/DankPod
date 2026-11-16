//
//  ParachuteViewController.swift
//  Classic
//
//  iPod Parachute (5G iPod / nano), Apple's take on the Apple II classic Sabotage.
//  A gun at the bottom of the screen swings through a half circle to shoot down
//  helicopters and the paratroopers they drop. Shoot a trooper's chute and he
//  plummets — taking out anyone he lands on. Four troopers landing on either side
//  of the base (or one landing on top of it) storm the gun and end the game.
//  From wave 2 on, every helicopter wave is followed by a run of jet bombers whose
//  bombs have to be shot out of the sky before they reach the gun.
//

import UIKit

class ParachuteViewController: PodGameViewController {

    private enum Phase { case title, playing, storming, destroyed, gameOver }
    private enum Stage { case helicopters, bombers, intermission }
    private enum TrooperState { case dropping, gliding, falling, landed }

    private final class Helicopter {
        let layer: CALayer
        let rotor: CALayer
        var pos: CGPoint
        let vx: CGFloat
        var drops: [CGFloat]          // x positions still to drop a trooper at, in travel order
        var rotorPhase = CGFloat.random(in: 0...(.pi))
        init(layer: CALayer, rotor: CALayer, pos: CGPoint, vx: CGFloat, drops: [CGFloat]) {
            self.layer = layer; self.rotor = rotor; self.pos = pos; self.vx = vx; self.drops = drops
        }
        var frame: CGRect { CGRect(x: pos.x - 17, y: pos.y - 8, width: 34, height: 16) }
    }

    private final class Jet {
        let layer: CALayer
        var pos: CGPoint
        let vx: CGFloat
        let releaseX: CGFloat
        var hasDropped = false
        init(layer: CALayer, pos: CGPoint, vx: CGFloat, releaseX: CGFloat) {
            self.layer = layer; self.pos = pos; self.vx = vx; self.releaseX = releaseX
        }
        var frame: CGRect { CGRect(x: pos.x - 17, y: pos.y - 6, width: 34, height: 12) }
    }

    private final class Bomb {
        let layer: CALayer
        var pos: CGPoint
        var vel: CGVector
        init(layer: CALayer, pos: CGPoint, vel: CGVector) { self.layer = layer; self.pos = pos; self.vel = vel }
    }

    private final class Trooper {
        let layer: CALayer            // anchored at the trooper's feet
        let chute: CALayer
        var pos: CGPoint
        var vel: CGVector
        var state: TrooperState = .dropping
        var age: CGFloat = 0
        var dead = false
        let swaySeed = CGFloat.random(in: 0...(2 * .pi))
        init(layer: CALayer, chute: CALayer, pos: CGPoint, vel: CGVector) {
            self.layer = layer; self.chute = chute; self.pos = pos; self.vel = vel
        }
        var bodyFrame: CGRect { CGRect(x: pos.x - 5, y: pos.y - 12, width: 10, height: 12) }
        var chuteFrame: CGRect { CGRect(x: pos.x - 9, y: pos.y - 29, width: 18, height: 12) }
    }

    /// One trooper's part in the final assault: walk to a spot, wait for the
    /// troopers he climbs on to get into place, then climb.
    private final class Walker {
        let trooper: Trooper
        var approach: [CGPoint]
        var climb: [CGPoint]
        let waitFor: [Int]
        var delay: CGFloat
        var walkPhase: CGFloat = 0
        init(trooper: Trooper, approach: [CGPoint], climb: [CGPoint], waitFor: [Int], delay: CGFloat) {
            self.trooper = trooper; self.approach = approach; self.climb = climb
            self.waitFor = waitFor; self.delay = delay
        }
        var isDone: Bool { approach.isEmpty && climb.isEmpty }
    }

    private struct Shell {
        let layer: CALayer
        var pos: CGPoint = .zero
        var vel: CGVector = .zero
        var active = false
    }

    private struct Particle {
        let layer: CALayer
        var pos: CGPoint = .zero
        var vel: CGVector = .zero
        var life: CGFloat = 0
        var maxLife: CGFloat = 1
    }

    private struct Flash {
        let layer: CALayer
        var life: CGFloat = 0
        var maxLife: CGFloat = 1
        var radius: CGFloat = 0
    }

    override var gameTitle: String { "Parachute" }

    // Game state
    private var phase: Phase = .title
    private var score = 0
    private var wave = 1
    private var stage: Stage = .intermission
    private var stageTimer: CGFloat = 0
    private var helisToSpawn = 0
    private var jetsToSpawn = 0
    private var fireCooldown: CGFloat = 0
    private var endTimer: CGFloat = 0
    private var bannerTimer: CGFloat = 0

    // Entities
    private var helicopters: [Helicopter] = []
    private var jets: [Jet] = []
    private var bombs: [Bomb] = []
    private var troopers: [Trooper] = []
    private var walkers: [Walker] = []
    private var shells: [Shell] = []
    private var particles: [Particle] = []
    private var flashes: [Flash] = []

    // Turret
    private var barrelAngle: CGFloat = 0     // radians from vertical, + is clockwise (right)
    private var barrelTarget: CGFloat = 0
    private var recoil: CGFloat = 0

    // Layers
    private var background: CAGradientLayer?
    private let cloudLayer = CALayer()
    private var clouds: [CALayer] = []
    private let groundLayer = CAGradientLayer()
    private let groundEdge = CALayer()
    private let actorLayer = CALayer()
    private let turretLayer = CALayer()
    private let barrel = CAGradientLayer()
    private var dome: CALayer?
    private var baseBlock: CALayer?
    private let shellLayer = CALayer()
    private let fxLayer = CALayer()
    private let bannerLabel = UILabel()

    // Geometry (set in layoutGame)
    private var groundY: CGFloat = 0
    private var baseRect: CGRect = .zero
    private var pivot: CGPoint = .zero

    // Layout
    private let groundHeight: CGFloat = 12
    private let trooperHeight: CGFloat = 11
    private let baseWidth: CGFloat = 40
    private let domeRadius: CGFloat = 10
    private let barrelLength: CGFloat = 18
    private let barrelWidth: CGFloat = 5
    private let shellSize: CGFloat = 4
    private let particlePoolSize = 160

    // Tuning
    private let maxBarrelAngle: CGFloat = 85 * .pi / 180
    private let wheelGain: CGFloat = 1.0            // barrel radians per wheel radian
    private let shellSpeed: CGFloat = 360
    private let maxShells = 4
    private let fireInterval: CGFloat = 0.16
    private let dropGravity: CGFloat = 260           // before the chute opens
    private let fallGravity: CGFloat = 340           // chute shot away
    private let chuteOpenDelay: CGFloat = 0.35
    private let bombGravity: CGFloat = 110
    private let walkSpeed: CGFloat = 55
    private let troopersToStorm = 4

    // Scoring
    private let helicopterPoints = 10
    private let trooperPoints = 5
    private let chutePoints = 5
    private let crushPoints = 5
    private let jetPoints = 25
    private let bombPoints = 30

    // Palette
    private let hullColor = UIColor(red: 0.22, green: 0.26, blue: 0.31, alpha: 1)
    private let jetColor = UIColor(red: 0.34, green: 0.39, blue: 0.47, alpha: 1)
    private let glassColor = UIColor(red: 0.62, green: 0.84, blue: 0.98, alpha: 1)
    private let olive = UIColor(red: 0.30, green: 0.36, blue: 0.17, alpha: 1)
    private let chuteRed = UIColor(red: 0.86, green: 0.20, blue: 0.18, alpha: 1)
    private let turretColor = UIColor(red: 0.40, green: 0.47, blue: 0.57, alpha: 1)
    private let fireColors: [UIColor] = [
        UIColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1),
        UIColor(red: 1.0, green: 0.55, blue: 0.10, alpha: 1),
        UIColor(red: 0.90, green: 0.25, blue: 0.10, alpha: 1),
        UIColor(white: 0.25, alpha: 1),
    ]

    // MARK: - Setup

    override func setupGame() {
        background = GameStyle.gradientLayer(GameStyle.skyTop, GameStyle.skyBottom, frame: view.bounds)
        view.layer.insertSublayer(background!, at: 0)

        view.layer.addSublayer(cloudLayer)
        for i in 0..<3 {
            let cloud = makeCloudLayer(scale: [1.0, 0.75, 0.6][i])
            cloud.opacity = [0.85, 0.7, 0.6][i]
            cloudLayer.addSublayer(cloud)
            clouds.append(cloud)
        }

        groundLayer.colors = [UIColor(red: 0.42, green: 0.66, blue: 0.28, alpha: 1).cgColor,
                              UIColor(red: 0.26, green: 0.46, blue: 0.16, alpha: 1).cgColor]
        view.layer.addSublayer(groundLayer)
        groundEdge.backgroundColor = UIColor(red: 0.62, green: 0.82, blue: 0.42, alpha: 1).cgColor
        view.layer.addSublayer(groundEdge)

        // Barrel: a horizontal gradient reads as a cylinder.
        barrel.colors = [turretColor.pcDarker(0.25).cgColor, turretColor.pcLighter(0.3).cgColor,
                         turretColor.pcDarker(0.3).cgColor]
        barrel.startPoint = CGPoint(x: 0, y: 0.5)
        barrel.endPoint = CGPoint(x: 1, y: 0.5)
        barrel.bounds = CGRect(x: 0, y: 0, width: barrelWidth, height: barrelLength)
        barrel.anchorPoint = CGPoint(x: 0.5, y: 1)
        barrel.cornerRadius = 1
        turretLayer.addSublayer(barrel)
        view.layer.addSublayer(turretLayer)

        view.layer.addSublayer(actorLayer)
        view.layer.addSublayer(shellLayer)
        view.layer.addSublayer(fxLayer)

        for _ in 0..<maxShells {
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: shellSize, height: shellSize)
            l.cornerRadius = shellSize / 2
            l.backgroundColor = UIColor(white: 0.12, alpha: 1).cgColor
            l.isHidden = true
            shellLayer.addSublayer(l)
            shells.append(Shell(layer: l))
        }
        for _ in 0..<particlePoolSize {
            let l = CALayer()
            l.isHidden = true
            fxLayer.addSublayer(l)
            particles.append(Particle(layer: l))
        }
        for _ in 0..<5 {
            let l = CALayer()
            l.isHidden = true
            l.backgroundColor = UIColor(red: 1, green: 0.92, blue: 0.6, alpha: 1).cgColor
            fxLayer.insertSublayer(l, at: 0)
            flashes.append(Flash(layer: l))
        }

        bannerLabel.font = GameStyle.font(16)
        bannerLabel.textColor = .white
        bannerLabel.textAlignment = .center
        bannerLabel.layer.shadowColor = UIColor(red: 0.1, green: 0.2, blue: 0.4, alpha: 1).cgColor
        bannerLabel.layer.shadowOpacity = 0.7
        bannerLabel.layer.shadowRadius = 2
        bannerLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        bannerLabel.alpha = 0
        view.addSubview(bannerLabel)

        showMessage("PARACHUTE", lines: [
            "Shoot down the helicopters",
            "Don't let 4 troopers land on one side",
            "Turn the wheel to aim, center to fire"
        ])
    }

    override func layoutGame() {
        let b = view.bounds
        background?.frame = b
        cloudLayer.frame = b
        groundY = b.height - groundHeight
        groundLayer.frame = CGRect(x: 0, y: groundY, width: b.width, height: groundHeight)
        groundEdge.frame = CGRect(x: 0, y: groundY, width: b.width, height: 1.5)
        actorLayer.frame = b
        turretLayer.frame = b
        shellLayer.frame = b
        fxLayer.frame = b
        bannerLabel.frame = CGRect(x: 0, y: b.height * 0.42, width: b.width, height: 24)

        baseRect = CGRect(x: b.midX - baseWidth / 2, y: groundY - trooperHeight * 2,
                          width: baseWidth, height: trooperHeight * 2)
        pivot = CGPoint(x: b.midX, y: baseRect.minY)

        // The dome is a glossy disc whose lower half hides behind the base block.
        dome?.removeFromSuperlayer()
        baseBlock?.removeFromSuperlayer()
        let d = GameStyle.glossyLayer(turretColor, frame: CGRect(x: pivot.x - domeRadius, y: pivot.y - domeRadius,
                                                                 width: domeRadius * 2, height: domeRadius * 2),
                                      cornerRadius: domeRadius)
        turretLayer.addSublayer(d)
        dome = d
        let block = GameStyle.glossyLayer(turretColor.pcDarker(0.05), frame: baseRect, cornerRadius: 3)
        block.borderColor = turretColor.pcDarker(0.35).cgColor
        block.borderWidth = 1
        // A dark gun slot detail on the base front.
        let slot = CALayer()
        slot.frame = CGRect(x: baseRect.width / 2 - 8, y: baseRect.height * 0.55, width: 16, height: 3)
        slot.cornerRadius = 1.5
        slot.backgroundColor = turretColor.pcDarker(0.45).cgColor
        block.addSublayer(slot)
        turretLayer.addSublayer(block)
        baseBlock = block
        if barrel.isHidden {
            d.isHidden = true
            block.opacity = 0.45
        }

        for (i, cloud) in clouds.enumerated() where cloud.position == .zero {
            cloud.position = CGPoint(x: b.width * [0.2, 0.62, 0.9][i], y: b.height * [0.16, 0.3, 0.09][i])
        }
        placeBarrel()
    }

    override func refreshHUD() {
        hudScore = phase == .title ? nil : score
        hudLives = nil
    }

    // MARK: - Shapes

    private func shapeLayer(_ path: UIBezierPath, fill: UIColor?, stroke: UIColor? = nil,
                            lineWidth: CGFloat = 0) -> CAShapeLayer {
        let s = CAShapeLayer()
        s.path = path.cgPath
        s.fillColor = fill?.cgColor
        s.strokeColor = stroke?.cgColor
        s.lineWidth = lineWidth
        s.lineJoin = .round
        s.lineCap = .round
        return s
    }

    private func makeCloudLayer(scale: CGFloat) -> CALayer {
        let path = UIBezierPath()
        for (x, y, r) in [(14.0, 14.0, 9.0), (26.0, 9.0, 11.0), (40.0, 13.0, 9.0), (30.0, 17.0, 8.0)] {
            path.append(UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)))
        }
        path.append(UIBezierPath(roundedRect: CGRect(x: 6, y: 13, width: 42, height: 10), cornerRadius: 5))
        let s = shapeLayer(path, fill: UIColor(white: 1, alpha: 0.9))
        s.bounds = CGRect(x: 0, y: 0, width: 54, height: 26)
        s.setAffineTransform(CGAffineTransform(scaleX: scale * 1.3, y: scale * 1.3))
        return s
    }

    /// Faces right in local space; flipped for left-moving choppers.
    private func makeHelicopterLayer() -> (CALayer, CALayer) {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: 36, height: 20)
        let hull = UIBezierPath()
        hull.append(UIBezierPath(rect: CGRect(x: 3, y: 8, width: 15, height: 3)))                      // tail boom
        hull.append(UIBezierPath(roundedRect: CGRect(x: 0.5, y: 3.5, width: 4.5, height: 8), cornerRadius: 1.5))
        hull.append(UIBezierPath(roundedRect: CGRect(x: 14, y: 5, width: 20, height: 11), cornerRadius: 5.5))
        hull.append(UIBezierPath(rect: CGRect(x: 22, y: 2.5, width: 2, height: 3)))                    // mast
        hull.append(UIBezierPath(rect: CGRect(x: 18, y: 15.5, width: 1.5, height: 2.5)))
        hull.append(UIBezierPath(rect: CGRect(x: 28.5, y: 15.5, width: 1.5, height: 2.5)))
        hull.append(UIBezierPath(roundedRect: CGRect(x: 15, y: 17.5, width: 19, height: 1.8), cornerRadius: 0.9))
        container.addSublayer(shapeLayer(hull, fill: hullColor))
        container.addSublayer(shapeLayer(UIBezierPath(roundedRect: CGRect(x: 17, y: 6, width: 12, height: 2.5),
                                                      cornerRadius: 1.2), fill: UIColor(white: 1, alpha: 0.18)))
        container.addSublayer(shapeLayer(UIBezierPath(ovalIn: CGRect(x: 25.5, y: 6.5, width: 7, height: 5.5)),
                                         fill: glassColor))
        container.addSublayer(shapeLayer(UIBezierPath(ovalIn: CGRect(x: 27, y: 7.2, width: 3.5, height: 1.8)),
                                         fill: UIColor(white: 1, alpha: 0.8)))
        let rotor = CALayer()
        rotor.bounds = CGRect(x: 0, y: 0, width: 32, height: 1.8)
        rotor.position = CGPoint(x: 23, y: 2)
        rotor.cornerRadius = 0.9
        rotor.backgroundColor = hullColor.pcDarker(0.2).cgColor
        container.addSublayer(rotor)
        actorLayer.addSublayer(container)
        return (container, rotor)
    }

    private func makeJetLayer() -> CALayer {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: 36, height: 14)
        let body = UIBezierPath()
        body.move(to: CGPoint(x: 2, y: 6))
        body.addLine(to: CGPoint(x: 28, y: 5))
        body.addQuadCurve(to: CGPoint(x: 35.5, y: 7.6), controlPoint: CGPoint(x: 34, y: 5.4))
        body.addQuadCurve(to: CGPoint(x: 28, y: 10), controlPoint: CGPoint(x: 34, y: 9.8))
        body.addLine(to: CGPoint(x: 3, y: 10))
        body.close()
        body.move(to: CGPoint(x: 0, y: 0.5))                 // tail fin
        body.addLine(to: CGPoint(x: 4, y: 0.5))
        body.addLine(to: CGPoint(x: 10, y: 6))
        body.addLine(to: CGPoint(x: 2, y: 6))
        body.close()
        body.move(to: CGPoint(x: 13, y: 8))                  // swept wing
        body.addLine(to: CGPoint(x: 21, y: 8))
        body.addLine(to: CGPoint(x: 14, y: 13.5))
        body.addLine(to: CGPoint(x: 10, y: 13.5))
        body.close()
        container.addSublayer(shapeLayer(body, fill: jetColor))
        container.addSublayer(shapeLayer(UIBezierPath(roundedRect: CGRect(x: 8, y: 6, width: 18, height: 1.4),
                                                      cornerRadius: 0.7), fill: UIColor(white: 1, alpha: 0.25)))
        container.addSublayer(shapeLayer(UIBezierPath(ovalIn: CGRect(x: 23, y: 4.4, width: 6.5, height: 3.2)),
                                         fill: glassColor))
        actorLayer.addSublayer(container)
        return container
    }

    private func makeBombLayer() -> CALayer {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: 7, height: 11)
        let fins = UIBezierPath(rect: CGRect(x: 1, y: 0, width: 5, height: 2.5))
        container.addSublayer(shapeLayer(fins, fill: UIColor(white: 0.3, alpha: 1)))
        container.addSublayer(shapeLayer(UIBezierPath(ovalIn: CGRect(x: 0.5, y: 1.5, width: 6, height: 9.5)),
                                         fill: UIColor(white: 0.1, alpha: 1)))
        container.addSublayer(shapeLayer(UIBezierPath(ovalIn: CGRect(x: 1.8, y: 3, width: 1.6, height: 4)),
                                         fill: UIColor(white: 1, alpha: 0.45)))
        actorLayer.addSublayer(container)
        return container
    }

    /// 16×28, anchored at the feet. The chute sits above the trooper and sways about his shoulders.
    private func makeTrooperLayer() -> (CALayer, CALayer) {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: 16, height: 28)
        container.anchorPoint = CGPoint(x: 0.5, y: 1)

        let chute = CALayer()
        chute.bounds = CGRect(x: 0, y: 0, width: 16, height: 18)
        chute.anchorPoint = CGPoint(x: 0.5, y: 1)
        chute.position = CGPoint(x: 8, y: 18)
        let lines = UIBezierPath()
        for (from, to) in [(0.6, 6.5), (15.4, 9.5), (8.0, 8.0)] {
            lines.move(to: CGPoint(x: from, y: 9))
            lines.addLine(to: CGPoint(x: to, y: 18))
        }
        chute.addSublayer(shapeLayer(lines, fill: nil, stroke: UIColor(white: 0.3, alpha: 0.8), lineWidth: 0.6))
        let center = CGPoint(x: 8, y: 9)
        for i in 0..<4 {
            let a0 = CGFloat.pi + CGFloat(i) * .pi / 4
            let gore = UIBezierPath()
            gore.move(to: center)
            gore.addArc(withCenter: center, radius: 8, startAngle: a0, endAngle: a0 + .pi / 4, clockwise: true)
            gore.close()
            chute.addSublayer(shapeLayer(gore, fill: i % 2 == 0 ? UIColor(white: 0.97, alpha: 1) : chuteRed))
        }
        let rim = UIBezierPath(arcCenter: center, radius: 8, startAngle: .pi, endAngle: 2 * .pi, clockwise: true)
        rim.close()
        chute.addSublayer(shapeLayer(rim, fill: nil, stroke: UIColor(white: 0.35, alpha: 1), lineWidth: 0.7))
        container.addSublayer(chute)

        let body = UIBezierPath(ovalIn: CGRect(x: 5.8, y: 17, width: 4.4, height: 4.4))
        body.append(UIBezierPath(roundedRect: CGRect(x: 5, y: 20.6, width: 6, height: 4.8), cornerRadius: 1.2))
        body.append(UIBezierPath(rect: CGRect(x: 5.3, y: 25, width: 2.1, height: 3)))
        body.append(UIBezierPath(rect: CGRect(x: 8.6, y: 25, width: 2.1, height: 3)))
        container.addSublayer(shapeLayer(body, fill: olive))
        container.addSublayer(shapeLayer(UIBezierPath(ovalIn: CGRect(x: 6.6, y: 17.6, width: 2, height: 1.4)),
                                         fill: UIColor(white: 1, alpha: 0.35)))
        actorLayer.addSublayer(container)
        return (container, chute)
    }

    // MARK: - Game flow

    private func restart() {
        hideMessage()
        helicopters.forEach { $0.layer.removeFromSuperlayer() }
        jets.forEach { $0.layer.removeFromSuperlayer() }
        bombs.forEach { $0.layer.removeFromSuperlayer() }
        troopers.forEach { $0.layer.removeFromSuperlayer() }
        helicopters.removeAll()
        jets.removeAll()
        bombs.removeAll()
        troopers.removeAll()
        walkers.removeAll()
        for i in shells.indices { shells[i].active = false; shells[i].layer.isHidden = true }
        for i in particles.indices { particles[i].life = 0; particles[i].layer.isHidden = true }
        for i in flashes.indices { flashes[i].life = 0; flashes[i].layer.isHidden = true }

        score = 0
        wave = 1
        fireCooldown = 0
        barrelAngle = 0
        barrelTarget = 0
        recoil = 0
        barrel.isHidden = false
        dome?.isHidden = false
        baseBlock?.opacity = 1
        phase = .playing
        refreshHUD()
        startWave()
    }

    private func startWave() {
        stage = .helicopters
        helisToSpawn = min(6 + wave * 2, 24)
        stageTimer = 1.2
        showBanner("WAVE \(wave)")
    }

    private func showBanner(_ text: String) {
        bannerLabel.text = text
        bannerTimer = 1.6
    }

    private var helicopterInterval: CGFloat { max(0.55, 1.7 - 0.12 * CGFloat(wave - 1)) }

    private func updateWaves(_ dt: CGFloat) {
        stageTimer -= dt
        switch stage {
        case .helicopters:
            if helisToSpawn > 0 {
                guard stageTimer <= 0 else { return }
                spawnHelicopter()
                helisToSpawn -= 1
                // Later waves send choppers in pairs now and then.
                if helisToSpawn > 0, CGFloat.random(in: 0...1) < min(0.1 + 0.05 * CGFloat(wave), 0.5) {
                    spawnHelicopter()
                    helisToSpawn -= 1
                }
                stageTimer = helicopterInterval * CGFloat.random(in: 0.7...1.3)
            } else if helicopters.isEmpty, !troopers.contains(where: { !$0.dead && $0.state != .landed }) {
                if wave >= 2 {
                    stage = .bombers
                    jetsToSpawn = min(wave - 1, 6)
                    stageTimer = 1.6
                    showBanner("BOMBERS!")
                } else {
                    stage = .intermission
                    stageTimer = 1.5
                }
            }
        case .bombers:
            if jetsToSpawn > 0 {
                guard stageTimer <= 0 else { return }
                spawnJet()
                jetsToSpawn -= 1
                stageTimer = max(0.9, 2.0 - 0.1 * CGFloat(wave)) * CGFloat.random(in: 0.8...1.2)
            } else if jets.isEmpty, bombs.isEmpty {
                stage = .intermission
                stageTimer = 1.5
            }
        case .intermission:
            if stageTimer <= 0 {
                wave += 1
                startWave()
            }
        }
    }

    private func spawnHelicopter() {
        let w = view.bounds.width
        let dir: CGFloat = Bool.random() ? 1 : -1
        let y = CGFloat.random(in: 18...max(19, view.bounds.height * 0.38))
        let speed = min(52 + 7 * CGFloat(wave - 1), 130) * CGFloat.random(in: 0.85...1.15)

        // How many troopers this chopper drops, and where (never right over the gun).
        var count = CGFloat.random(in: 0...1) < min(0.55 + 0.07 * CGFloat(wave), 0.95) ? 1 : 0
        if wave >= 3, CGFloat.random(in: 0...1) < min(0.12 * CGFloat(wave - 2), 0.55) { count += 1 }
        var drops: [CGFloat] = []
        for _ in 0..<count {
            var x: CGFloat
            repeat { x = CGFloat.random(in: 14...(w - 14)) } while abs(x - w / 2) < baseWidth / 2 + 8
            drops.append(x)
        }
        drops.sort { dir > 0 ? $0 < $1 : $0 > $1 }

        let (layer, rotor) = makeHelicopterLayer()
        layer.setAffineTransform(CGAffineTransform(scaleX: dir, y: 1))
        let heli = Helicopter(layer: layer, rotor: rotor, pos: CGPoint(x: dir > 0 ? -22 : w + 22, y: y),
                              vx: dir * speed, drops: drops)
        layer.position = heli.pos
        helicopters.append(heli)
    }

    private func spawnJet() {
        let w = view.bounds.width
        let dir: CGFloat = Bool.random() ? 1 : -1
        let speed = min(150 + 9 * CGFloat(wave), 240)
        let release = w / 2 - dir * CGFloat.random(in: 70...max(71, min(160, w / 2 - 16)))
        let layer = makeJetLayer()
        layer.setAffineTransform(CGAffineTransform(scaleX: dir, y: 1))
        let jet = Jet(layer: layer, pos: CGPoint(x: dir > 0 ? -24 : w + 24, y: CGFloat.random(in: 14...30)),
                      vx: dir * speed, releaseX: release)
        layer.position = jet.pos
        jets.append(jet)
    }

    // MARK: - Frame loop

    override func update(dt: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateClouds(dt)
        updateBanner(dt)
        updateTurret(dt)
        updateShells(dt)
        switch phase {
        case .playing:
            updateWaves(dt)
            updateAircraft(dt, canDrop: true)
            updateBombs(dt)
            updateTroopers(dt)
            checkStorm()
        case .storming:
            updateAircraft(dt, canDrop: false)
            updateTroopers(dt)
            updateWalkers(dt)
        case .destroyed:
            updateAircraft(dt, canDrop: false)
            updateTroopers(dt)
            endTimer -= dt
            if endTimer <= 0 {
                phase = .gameOver
                showGameOver(score: score)
            }
        case .title, .gameOver:
            updateAircraft(dt, canDrop: false)
            updateTroopers(dt)
        }
        updateParticles(dt)
        CATransaction.commit()
    }

    private func updateClouds(_ dt: CGFloat) {
        let w = view.bounds.width
        for (i, cloud) in clouds.enumerated() {
            cloud.position.x += CGFloat(4 + i * 2) * dt
            if cloud.position.x > w + 50 { cloud.position.x = -50 }
        }
    }

    private func updateBanner(_ dt: CGFloat) {
        guard bannerTimer > 0 else { return }
        bannerTimer -= dt
        bannerLabel.alpha = min(1, bannerTimer / 0.4)
    }

    private func updateTurret(_ dt: CGFloat) {
        fireCooldown = max(0, fireCooldown - dt)
        // Ease toward the wheel target so aiming stays smooth at any wheel speed.
        barrelAngle += (barrelTarget - barrelAngle) * min(1, dt * 35)
        recoil = max(0, recoil - dt * 30)
        placeBarrel()
    }

    private func placeBarrel() {
        let dir = CGPoint(x: sin(barrelAngle), y: -cos(barrelAngle))
        barrel.position = CGPoint(x: pivot.x - dir.x * recoil, y: pivot.y - dir.y * recoil)
        barrel.setAffineTransform(CGAffineTransform(rotationAngle: barrelAngle))
    }

    // MARK: - Shooting

    private func fire() {
        guard fireCooldown <= 0, let i = shells.firstIndex(where: { !$0.active }) else { return }
        // Fired from the wheel handler, outside update()'s transaction: without this the
        // pooled shell layer animates in from wherever it last disappeared.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        fireCooldown = fireInterval
        let dir = CGVector(dx: sin(barrelAngle), dy: -cos(barrelAngle))
        let muzzle = CGPoint(x: pivot.x + dir.dx * barrelLength, y: pivot.y + dir.dy * barrelLength)
        shells[i].pos = muzzle
        shells[i].vel = CGVector(dx: dir.dx * shellSpeed, dy: dir.dy * shellSpeed)
        shells[i].active = true
        shells[i].layer.isHidden = false
        shells[i].layer.position = muzzle
        recoil = 3
        emit(at: muzzle, count: 3, speed: 40, colors: Array(fireColors.prefix(2)), size: 2, life: 0.15)
        tick(.light, intensity: 0.3)
    }

    private func updateShells(_ dt: CGFloat) {
        let b = view.bounds
        for i in shells.indices where shells[i].active {
            // Sub-step so a shell never skips over a trooper.
            let steps = max(1, Int(ceil(shellSpeed * dt / 3)))
            let stepDt = dt / CGFloat(steps)
            for _ in 0..<steps {
                shells[i].pos.x += shells[i].vel.dx * stepDt
                shells[i].pos.y += shells[i].vel.dy * stepDt
                if resolveHit(at: shells[i].pos) { shells[i].active = false; break }
            }
            let p = shells[i].pos
            if p.x < -10 || p.x > b.width + 10 || p.y < -10 || p.y > b.height { shells[i].active = false }
            shells[i].layer.isHidden = !shells[i].active
            shells[i].layer.position = p
        }
    }

    /// Checks a shell position against everything shootable; handles the hit and returns true if it struck.
    private func resolveHit(at p: CGPoint) -> Bool {
        let r = shellSize / 2
        for (i, bomb) in bombs.enumerated() where hypot(bomb.pos.x - p.x, bomb.pos.y - p.y) < 7 + r {
            bomb.layer.removeFromSuperlayer()
            bombs.remove(at: i)
            explode(at: bomb.pos, size: 0.8)
            award(bombPoints)
            return true
        }
        for (i, jet) in jets.enumerated() where jet.frame.insetBy(dx: -r, dy: -r).contains(p) {
            jet.layer.removeFromSuperlayer()
            jets.remove(at: i)
            explode(at: jet.pos, size: 1.2)
            award(jetPoints)
            return true
        }
        for (i, heli) in helicopters.enumerated() where heli.frame.insetBy(dx: -r, dy: -r).contains(p) {
            heli.layer.removeFromSuperlayer()
            helicopters.remove(at: i)
            explode(at: heli.pos, size: 1.1)
            award(helicopterPoints)
            return true
        }
        for t in troopers where !t.dead && t.state != .landed {
            if t.bodyFrame.insetBy(dx: -r, dy: -r).contains(p) {
                kill(t)
                award(trooperPoints)
                return true
            }
            if t.state == .gliding, t.chuteFrame.insetBy(dx: -r, dy: -r).contains(p) {
                // Chute shot away: he drops like a stone.
                t.state = .falling
                t.chute.isHidden = true
                emit(at: CGPoint(x: t.pos.x, y: t.pos.y - 23), count: 8, speed: 50,
                     colors: [UIColor(white: 0.97, alpha: 1), chuteRed], size: 2.5, life: 0.5)
                award(chutePoints)
                tick(.light, intensity: 0.4)
                return true
            }
        }
        return false
    }

    private func award(_ points: Int) {
        score += points
        hudScore = score
    }

    // MARK: - Aircraft

    private func updateAircraft(_ dt: CGFloat, canDrop: Bool) {
        let w = view.bounds.width
        for heli in helicopters {
            heli.pos.x += heli.vx * dt
            heli.rotorPhase += dt * 22
            heli.rotor.setAffineTransform(CGAffineTransform(scaleX: max(0.12, abs(cos(heli.rotorPhase))), y: 1))
            // Gentle bob so they feel airborne.
            heli.layer.position = CGPoint(x: heli.pos.x, y: heli.pos.y + sin(heli.rotorPhase * 0.08) * 1.2)
            if canDrop, let next = heli.drops.first, (heli.pos.x - next) * heli.vx >= 0 {
                heli.drops.removeFirst()
                dropTrooper(from: heli)
            }
        }
        helicopters.removeAll { heli in
            let gone = heli.vx > 0 ? heli.pos.x > w + 30 : heli.pos.x < -30
            if gone { heli.layer.removeFromSuperlayer() }
            return gone
        }

        for jet in jets {
            jet.pos.x += jet.vx * dt
            jet.layer.position = jet.pos
            if canDrop, !jet.hasDropped, (jet.pos.x - jet.releaseX) * jet.vx >= 0 {
                jet.hasDropped = true
                releaseBomb(from: jet)
            }
        }
        jets.removeAll { jet in
            let gone = jet.vx > 0 ? jet.pos.x > w + 30 : jet.pos.x < -30
            if gone { jet.layer.removeFromSuperlayer() }
            return gone
        }
    }

    private func dropTrooper(from heli: Helicopter) {
        let (layer, chute) = makeTrooperLayer()
        chute.isHidden = true
        let t = Trooper(layer: layer, chute: chute, pos: CGPoint(x: heli.pos.x, y: heli.pos.y + 18),
                        vel: CGVector(dx: CGFloat.random(in: -5...5), dy: 30))
        layer.position = t.pos
        troopers.append(t)
    }

    /// Bombs are aimed: their horizontal speed is solved so they land squarely on the gun.
    private func releaseBomb(from jet: Jet) {
        let drop = max(20, pivot.y - jet.pos.y)
        let t = sqrt(2 * drop / bombGravity)
        let bomb = Bomb(layer: makeBombLayer(), pos: CGPoint(x: jet.pos.x, y: jet.pos.y + 5),
                        vel: CGVector(dx: (pivot.x - jet.pos.x) / t, dy: 0))
        bomb.layer.position = bomb.pos
        bombs.append(bomb)
    }

    private func updateBombs(_ dt: CGFloat) {
        for (i, bomb) in bombs.enumerated().reversed() {
            bomb.vel.dy += bombGravity * dt
            bomb.pos.x += bomb.vel.dx * dt
            bomb.pos.y += bomb.vel.dy * dt
            bomb.layer.position = bomb.pos
            bomb.layer.setAffineTransform(CGAffineTransform(rotationAngle: atan2(bomb.vel.dy, bomb.vel.dx) - .pi / 2))
            let hitGun = hypot(bomb.pos.x - pivot.x, bomb.pos.y - pivot.y) < domeRadius + 4
                || baseRect.insetBy(dx: -2, dy: -2).contains(bomb.pos)
            if hitGun || bomb.pos.y >= groundY {
                bomb.layer.removeFromSuperlayer()
                bombs.remove(at: i)
                explode(at: bomb.pos, size: 1)
                if hitGun { destroyTurret(); return }
            }
        }
    }

    // MARK: - Troopers

    private func updateTroopers(_ dt: CGFloat) {
        let w = view.bounds.width
        for t in troopers where !t.dead && t.state != .landed {
            t.age += dt
            switch t.state {
            case .dropping:
                t.vel.dy += dropGravity * dt
                if t.age >= chuteOpenDelay {
                    t.state = .gliding
                    t.chute.isHidden = false
                    let pop = CABasicAnimation(keyPath: "transform.scale")
                    pop.fromValue = 0.2
                    pop.toValue = 1
                    pop.duration = 0.22
                    pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    t.chute.add(pop, forKey: "pop")
                }
            case .gliding:
                // Chute brakes quickly to a gentle descent that gets faster each wave.
                t.vel.dy += (glideSpeed - t.vel.dy) * min(1, dt * 4)
                t.pos.x = min(max(t.pos.x + t.vel.dx * dt, 8), w - 8)
                t.chute.setAffineTransform(CGAffineTransform(rotationAngle: sin(t.age * 2.2 + t.swaySeed) * 0.12))
            case .falling:
                t.vel.dy += fallGravity * dt
            case .landed:
                break
            }
            let prevY = t.pos.y
            t.pos.y += t.vel.dy * dt

            // Drifting into the side of the base below its top: slide off it rather than teleporting up.
            // (A fast faller that crossed the top this frame lands on the base instead of being shoved aside.)
            let zone = baseWidth / 2 + 3
            if abs(t.pos.x - pivot.x) < zone, t.pos.y > baseRect.minY + 6, prevY > baseRect.minY {
                t.pos.x = pivot.x + (t.pos.x < pivot.x ? -zone : zone)
            }

            let support = supportBelow(t)
            if t.pos.y >= support.y {
                t.pos.y = support.y
                land(t, onto: support.under, onBase: support.onBase)
            }
            t.layer.position = t.pos
        }
        troopers.removeAll { $0.dead }
    }

    private var glideSpeed: CGFloat { min(26 + 2.5 * CGFloat(wave - 1), 50) }

    /// The surface under a trooper: the gun's base, another landed trooper's head, or the ground.
    private func supportBelow(_ t: Trooper) -> (y: CGFloat, under: Trooper?, onBase: Bool) {
        if abs(t.pos.x - pivot.x) < baseWidth / 2 + 3 { return (baseRect.minY, nil, true) }
        var best = groundY
        var under: Trooper?
        for o in troopers where o !== t && !o.dead && o.state == .landed && abs(o.pos.x - t.pos.x) < 7 {
            let top = o.pos.y - trooperHeight
            if top < best { best = top; under = o }
        }
        return (best, under, false)
    }

    private func land(_ t: Trooper, onto under: Trooper?, onBase: Bool) {
        if t.state == .falling {
            // Free-fallers die on impact — and squash whoever they land on.
            if let u = under {
                kill(u)
                award(crushPoints)
            }
            kill(t)
            return
        }
        t.state = .landed
        t.vel = .zero
        t.chute.isHidden = true
        emit(at: t.pos, count: 4, speed: 25, colors: [UIColor(white: 0.97, alpha: 1), chuteRed], size: 2, life: 0.3)
        if onBase && phase == .playing {
            startStorm(onBase: t)
        }
    }

    private func kill(_ t: Trooper) {
        guard !t.dead else { return }
        t.dead = true
        t.layer.removeFromSuperlayer()
        emit(at: CGPoint(x: t.pos.x, y: t.pos.y - 6), count: 9, speed: 60,
             colors: [olive, olive.pcDarker(0.3), UIColor(red: 0.75, green: 0.15, blue: 0.1, alpha: 1)],
             size: 2.5, life: 0.5)
        tick(.light, intensity: 0.4)
        // Anyone stacked on his head drops down a level.
        if t.state == .landed {
            for o in troopers where !o.dead && o.state == .landed && abs(o.pos.x - t.pos.x) < 7 && o.pos.y < t.pos.y {
                o.pos.y += trooperHeight
                o.layer.position = o.pos
            }
        }
    }

    // MARK: - Storming the base

    private func checkStorm() {
        guard phase == .playing else { return }
        let landed = troopers.filter { !$0.dead && $0.state == .landed }
        if landed.filter({ $0.pos.x < pivot.x }).count >= troopersToStorm {
            startStorm(side: -1)
        } else if landed.filter({ $0.pos.x > pivot.x }).count >= troopersToStorm {
            startStorm(side: 1)
        }
    }

    /// Four troopers form a human staircase: two at the foot of the base, one on
    /// their shoulders, and the last climbs over them onto the gun.
    private func startStorm(side s: CGFloat) {
        beginStorm()
        let squad = troopers
            .filter { !$0.dead && $0.state == .landed && ($0.pos.x - pivot.x) * s > 0 }
            .sorted { abs($0.pos.x - pivot.x) < abs($1.pos.x - pivot.x) }
            .prefix(troopersToStorm)
        let h = trooperHeight
        let xA = pivot.x + s * (baseWidth / 2 + 4.5)
        let xB = xA + s * 9
        let xWait = xB + s * 9
        let top = baseRect.minY

        func ground(_ t: Trooper) -> [CGPoint] { t.pos.y < groundY ? [CGPoint(x: t.pos.x, y: groundY)] : [] }
        for (i, t) in squad.enumerated() {
            let w: Walker
            switch i {
            case 0:
                w = Walker(trooper: t, approach: ground(t) + [CGPoint(x: xA, y: groundY)], climb: [],
                           waitFor: [], delay: 0)
            case 1:
                w = Walker(trooper: t, approach: ground(t) + [CGPoint(x: xB, y: groundY)], climb: [],
                           waitFor: [], delay: 0.15)
            case 2:
                w = Walker(trooper: t, approach: ground(t) + [CGPoint(x: xWait, y: groundY)],
                           climb: [CGPoint(x: xB, y: groundY - h), CGPoint(x: xA, y: groundY - h)],
                           waitFor: [0, 1], delay: 0.3)
            default:
                w = Walker(trooper: t, approach: ground(t) + [CGPoint(x: xWait, y: groundY)],
                           climb: [CGPoint(x: xB, y: groundY - h), CGPoint(x: xA, y: groundY - 2 * h),
                                   CGPoint(x: pivot.x + s * 3, y: top)],
                           waitFor: [2], delay: 0.45)
            }
            walkers.append(w)
        }
        if walkers.isEmpty { destroyTurret() }
    }

    private func startStorm(onBase t: Trooper) {
        beginStorm()
        let side: CGFloat = t.pos.x < pivot.x ? -1 : 1
        walkers = [Walker(trooper: t, approach: [], climb: [CGPoint(x: pivot.x + side * 3, y: baseRect.minY)],
                          waitFor: [], delay: 0.3)]
    }

    private func beginStorm() {
        phase = .storming
        walkers.removeAll()
        bombs.forEach { b in
            b.layer.removeFromSuperlayer()
            explode(at: b.pos, size: 0.6)
        }
        bombs.removeAll()
        showBanner("THE BASE IS OVERRUN!")
        tick(.medium, intensity: 0.7)
    }

    private func updateWalkers(_ dt: CGFloat) {
        for w in walkers where !w.isDone {
            if w.delay > 0 { w.delay -= dt; continue }
            var moving = false
            if !w.approach.isEmpty {
                w.approach = advance(w.trooper, along: w.approach, dt: dt)
                moving = true
            } else if w.waitFor.allSatisfy({ $0 < walkers.count && walkers[$0].isDone }) {
                w.climb = advance(w.trooper, along: w.climb, dt: dt)
                moving = true
            }
            // A little bounce in their step.
            w.walkPhase += moving ? dt * 18 : 0
            let hop = moving && !w.isDone ? abs(sin(w.walkPhase)) * 1.5 : 0
            w.trooper.layer.position = CGPoint(x: w.trooper.pos.x, y: w.trooper.pos.y - hop)
        }
        if walkers.allSatisfy({ $0.isDone }) {
            destroyTurret()
        }
    }

    /// Moves a trooper toward the first waypoint; returns the path still to walk.
    private func advance(_ t: Trooper, along path: [CGPoint], dt: CGFloat) -> [CGPoint] {
        guard let target = path.first else { return path }
        let dx = target.x - t.pos.x, dy = target.y - t.pos.y
        let dist = hypot(dx, dy)
        let stepLen = walkSpeed * dt
        if dist <= stepLen {
            t.pos = target
            return Array(path.dropFirst())
        }
        t.pos.x += dx / dist * stepLen
        t.pos.y += dy / dist * stepLen
        return path
    }

    private func destroyTurret() {
        guard phase == .playing || phase == .storming else { return }
        phase = .destroyed
        endTimer = 1.6
        explode(at: pivot, size: 2.2)
        explode(at: CGPoint(x: pivot.x - 10, y: pivot.y + 8), size: 1.2)
        explode(at: CGPoint(x: pivot.x + 10, y: pivot.y + 8), size: 1.2)
        barrel.isHidden = true
        dome?.isHidden = true
        baseBlock?.opacity = 0.45
        bombs.forEach { $0.layer.removeFromSuperlayer() }
        bombs.removeAll()
        for i in shells.indices { shells[i].active = false; shells[i].layer.isHidden = true }
        tick(.heavy, intensity: 1)
    }

    // MARK: - Effects

    private func explode(at p: CGPoint, size: CGFloat) {
        emit(at: p, count: Int(14 * size), speed: 90 * size, colors: fireColors, size: 3, life: 0.6)
        flash(at: p, radius: 14 * size)
        tick(.medium, intensity: min(1, 0.4 * size))
    }

    private func emit(at p: CGPoint, count: Int, speed: CGFloat, colors: [UIColor], size: CGFloat, life: CGFloat) {
        var remaining = count
        for i in particles.indices where particles[i].life <= 0 {
            guard remaining > 0 else { break }
            remaining -= 1
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let v = speed * CGFloat.random(in: 0.3...1)
            let s = size * CGFloat.random(in: 0.7...1.3)
            particles[i].pos = p
            particles[i].vel = CGVector(dx: cos(angle) * v, dy: sin(angle) * v - speed * 0.3)
            particles[i].maxLife = life * CGFloat.random(in: 0.7...1.2)
            particles[i].life = particles[i].maxLife
            let l = particles[i].layer
            l.bounds = CGRect(x: 0, y: 0, width: s, height: s)
            l.cornerRadius = s / 3
            l.backgroundColor = colors.randomElement()?.cgColor
            l.position = p
            l.opacity = 1
            l.isHidden = false
        }
    }

    private func flash(at p: CGPoint, radius: CGFloat) {
        guard let i = flashes.firstIndex(where: { $0.life <= 0 }) else { return }
        flashes[i].life = 0.25
        flashes[i].maxLife = 0.25
        flashes[i].radius = radius
        flashes[i].layer.position = p
        flashes[i].layer.isHidden = false
    }

    private func updateParticles(_ dt: CGFloat) {
        for i in particles.indices where particles[i].life > 0 {
            particles[i].life -= dt
            if particles[i].life <= 0 { particles[i].layer.isHidden = true; continue }
            particles[i].vel.dy += 160 * dt
            particles[i].vel.dx *= 1 - min(1, dt * 1.5)
            particles[i].pos.x += particles[i].vel.dx * dt
            particles[i].pos.y += particles[i].vel.dy * dt
            particles[i].layer.position = particles[i].pos
            particles[i].layer.opacity = Float(min(1, particles[i].life / particles[i].maxLife * 1.6))
        }
        for i in flashes.indices where flashes[i].life > 0 {
            flashes[i].life -= dt
            if flashes[i].life <= 0 { flashes[i].layer.isHidden = true; continue }
            let p = 1 - flashes[i].life / flashes[i].maxLife
            let r = flashes[i].radius * (0.4 + 0.6 * p)
            flashes[i].layer.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
            flashes[i].layer.cornerRadius = r
            flashes[i].layer.opacity = Float(0.85 * (1 - p))
        }
    }

    private func tick(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        guard SettingsStore.shared.clickerEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
    }

    // MARK: - Input

    // Analog wheel: the barrel follows the wheel 1:1, so a half turn sweeps the full arc.
    override var prefersContinuousWheelInput: Bool { true }

    override func clickWheelDidRotateContinuously(event: ClickWheelRotationEvent) {
        guard !isGamePaused, event.state == .changed, phase == .playing || phase == .title else { return }
        barrelTarget = min(max(barrelTarget + event.deltaRadians * wheelGain, -maxBarrelAngle), maxBarrelAngle)
    }

    override func selectPressed() {
        switch phase {
        case .title, .gameOver: restart()
        case .playing: fire()
        case .storming, .destroyed: break
        }
    }

    override func gameWillExit() {
        bannerTimer = 0
    }
}

private extension UIColor {
    func pcLighter(_ amount: CGFloat) -> UIColor { pcAdjusted(amount) }
    func pcDarker(_ amount: CGFloat) -> UIColor { pcAdjusted(-amount) }

    func pcAdjusted(_ amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: min(max(b + amount, 0), 1), alpha: a)
    }
}
