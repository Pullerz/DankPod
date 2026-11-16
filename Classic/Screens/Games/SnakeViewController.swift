//
//  SnakeViewController.swift
//  Classic
//
//  Snake as Apple might have shipped it on the 2006 iPod: a glossy green
//  snake glides over a light, softly gridded playfield eating shiny apples.
//  Steering is relative — a clockwise wheel click (or ⏭) turns right, an
//  anticlockwise click (or ⏮) turns left — so the wheel never needs aiming.
//  The snake speeds up with every apple; every fifth apple a golden apple
//  appears for a few seconds. Walls and your own tail are fatal.
//

import UIKit

class SnakeViewController: PodGameViewController {

    private enum Phase { case ready, playing, dying, gameOver }

    private enum Turn { case left, right }

    private struct Cell: Equatable {
        var x: Int
        var y: Int
    }

    /// Unit step in grid coordinates (y grows downward).
    private struct Direction: Equatable {
        var dx: Int
        var dy: Int
        func turned(_ turn: Turn) -> Direction {
            turn == .right ? Direction(dx: -dy, dy: dx) : Direction(dx: dy, dy: -dx)
        }
        var angle: CGFloat { atan2(CGFloat(dy), CGFloat(dx)) }
    }

    override var gameTitle: String { "Snake" }

    // Game state
    private var phase: Phase = .ready
    private var score = 0
    private var applesEaten = 0
    private var body: [Cell] = []          // head first
    private var previousBody: [Cell] = []  // where each segment was one step ago (for interpolation)
    private var direction = Direction(dx: 1, dy: 0)
    private var pendingGrowth = 0
    private var stepClock: CGFloat = 0
    private var food = Cell(x: 0, y: 0)
    private var bonus: Cell?
    private var bonusTimeLeft: CGFloat = 0
    private var dyingClock: CGFloat = 0

    // Input
    private var turnQueue: [Turn] = []
    private var wheelTurnedThisStep = false
    private var lastWheelTurnTime: CFTimeInterval = 0

    // Grid geometry
    private var cols = 0
    private var rows = 0
    private var cell: CGFloat = 16
    private var fieldOrigin: CGPoint = .zero
    private var builtSize: CGSize = .zero

    // Views (layers are pooled; the snake only ever adds layers when it grows)
    private let background = UIImageView()
    private let snakeLayer = CALayer()
    private var segmentLayers: [CALayer] = []
    private let headLayer = CALayer()
    /// Continuous body drawn beneath the segments so they read as one snake.
    private let spineLayer = CAShapeLayer()
    private let foodLayer = CALayer()
    private let bonusLayer = CALayer()
    private let bonusRing = CAShapeLayer()

    // Artwork, re-rendered when the cell size changes
    private var segmentImages: [CGImage] = []
    private var headImage: CGImage?
    private var deadHeadImage: CGImage?

    // Layout
    private let targetCellSize: CGFloat = 16
    private let startLength = 4

    // Tuning
    private let firstStepInterval: CGFloat = 0.16    // seconds per cell at the start
    private let speedUpPerApple: CGFloat = 0.968     // interval multiplier per apple
    private let minStepInterval: CGFloat = 0.06
    private let growthPerApple = 1
    private let bonusEvery = 5                       // golden apple after every Nth apple
    private let bonusLifetime: CGFloat = 6
    private let maxQueuedTurns = 2
    private let wheelDebounce: CFTimeInterval = 0.11
    private let dyingDuration: CGFloat = 0.9

    // Palette
    private let fieldTop = UIColor(red: 0.99, green: 0.99, blue: 1.0, alpha: 1)
    private let fieldBottom = UIColor(red: 0.83, green: 0.87, blue: 0.93, alpha: 1)
    private let gridColor = UIColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 0.08)
    private let snakeLight = UIColor(red: 0.62, green: 0.90, blue: 0.38, alpha: 1)
    private let snakeMid = UIColor(red: 0.22, green: 0.66, blue: 0.16, alpha: 1)
    private let snakeDark = UIColor(red: 0.07, green: 0.40, blue: 0.08, alpha: 1)

    private var stepInterval: CGFloat {
        max(minStepInterval, firstStepInterval * pow(speedUpPerApple, CGFloat(applesEaten)))
    }

    /// Apples are worth more as the snake gets faster.
    private var applePoints: Int { 10 * (1 + applesEaten / 8) }

    // MARK: - Setup

    override func setupGame() {
        view.backgroundColor = fieldBottom
        view.addSubview(background)

        view.layer.addSublayer(foodLayer)
        bonusRing.fillColor = UIColor.clear.cgColor
        bonusRing.strokeColor = UIColor(red: 0.85, green: 0.6, blue: 0.05, alpha: 0.9).cgColor
        bonusRing.lineWidth = 2
        bonusRing.lineCap = .round
        bonusLayer.addSublayer(bonusRing)
        bonusLayer.isHidden = true
        view.layer.addSublayer(bonusLayer)
        view.layer.addSublayer(snakeLayer)
        snakeLayer.addSublayer(headLayer)
        spineLayer.fillColor = nil
        spineLayer.strokeColor = snakeMid.cgColor
        spineLayer.lineCap = .round
        spineLayer.lineJoin = .round
        spineLayer.shadowColor = UIColor.black.cgColor
        spineLayer.shadowOpacity = 0.3
        spineLayer.shadowRadius = 1.5
        spineLayer.shadowOffset = CGSize(width: 0, height: 1.5)
        spineLayer.zPosition = -10_000
        snakeLayer.insertSublayer(spineLayer, at: 0)

        addBob(to: foodLayer)
        addBob(to: bonusLayer)
        buildField()
        resetGame()
    }

    override func layoutGame() {
        guard view.bounds.size != builtSize else { return }
        // The grid changed shape: start over on the new board.
        buildField()
        resetGame()
    }

    override func refreshHUD() {
        hudScore = score
        hudLives = nil
    }

    override func gameWillExit() {
        // Leaving during the death blink must still record the score.
        if phase == .dying { HighScores.submit(score, for: scoreKey) }
        phase = .gameOver
    }

    private func buildField() {
        let size = view.bounds.size
        builtSize = size
        cols = max(8, Int(size.width / targetCellSize))
        rows = max(6, Int(size.height / targetCellSize))
        cell = floor(min(size.width / CGFloat(cols), size.height / CGFloat(rows)) * 2) / 2
        fieldOrigin = CGPoint(x: ((size.width - cell * CGFloat(cols)) / 2).rounded(),
                              y: ((size.height - cell * CGFloat(rows)) / 2).rounded())
        renderBackground()
        renderSprites()
    }

    private func resetGame() {
        hideMessage()
        phase = .ready
        score = 0
        applesEaten = 0
        pendingGrowth = 0
        stepClock = 0
        turnQueue.removeAll()
        direction = Direction(dx: 1, dy: 0)
        let start = Cell(x: max(startLength, cols / 4), y: rows / 2)
        body = (0..<startLength).map { Cell(x: start.x - $0, y: start.y) }
        previousBody = body
        bonus = nil
        bonusLayer.isHidden = true
        snakeLayer.opacity = 1
        headLayer.contents = headImage
        spawnFood()
        refreshHUD()
        render(progress: 1)
        showMessage("SNAKE", lines: [
            "Turn with the wheel or ⏮ ⏭",
            "Press center to start"
        ])
    }

    // MARK: - Artwork

    private func renderBackground() {
        let size = view.bounds.size
        let field = CGRect(x: fieldOrigin.x, y: fieldOrigin.y, width: cell * CGFloat(cols), height: cell * CGFloat(rows))
        background.frame = view.bounds
        background.image = UIGraphicsImageRenderer(size: size).image { rc in
            let ctx = rc.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            if let g = CGGradient(colorsSpace: space, colors: [fieldTop.cgColor, fieldBottom.cgColor] as CFArray,
                                  locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            // Subtle grid
            ctx.setStrokeColor(gridColor.cgColor)
            ctx.setLineWidth(1)
            for i in 1..<cols {
                let x = field.minX + CGFloat(i) * cell + 0.5
                ctx.move(to: CGPoint(x: x, y: field.minY))
                ctx.addLine(to: CGPoint(x: x, y: field.maxY))
            }
            for j in 1..<rows {
                let y = field.minY + CGFloat(j) * cell + 0.5
                ctx.move(to: CGPoint(x: field.minX, y: y))
                ctx.addLine(to: CGPoint(x: field.maxX, y: y))
            }
            ctx.strokePath()
            // Soft inner shadow around the edge so the walls read as walls.
            ctx.saveGState()
            ctx.clip(to: field)
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 5, color: UIColor(white: 0, alpha: 0.35).cgColor)
            ctx.setStrokeColor(UIColor(white: 0.3, alpha: 1).cgColor)
            ctx.setLineWidth(4)
            ctx.stroke(field.insetBy(dx: -2, dy: -2))
            ctx.restoreGState()
            ctx.setStrokeColor(UIColor(red: 0.45, green: 0.52, blue: 0.62, alpha: 0.8).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(field.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    private func renderSprites() {
        segmentImages = [segmentImage(tint: 0), segmentImage(tint: 1)].compactMap { $0 }
        headImage = headSprite(dead: false)
        deadHeadImage = headSprite(dead: true)
        let scale = UIScreen.main.scale
        let foodSize = cell * 1.25 + 6
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in segmentLayers + [headLayer, foodLayer, bonusLayer] { layer.contentsScale = scale }
        segmentLayers.forEach {
            $0.bounds = CGRect(x: 0, y: 0, width: cell + 6, height: cell + 6)
        }
        headLayer.bounds = CGRect(x: 0, y: 0, width: cell * 1.15 + 6, height: cell * 1.15 + 6)
        headLayer.contents = headImage
        foodLayer.bounds = CGRect(x: 0, y: 0, width: foodSize, height: foodSize)
        foodLayer.contents = appleSprite(golden: false)
        bonusLayer.bounds = foodLayer.bounds
        bonusLayer.contents = appleSprite(golden: true)
        let ringRect = bonusLayer.bounds.insetBy(dx: 1, dy: 1)
        bonusRing.frame = bonusLayer.bounds
        // Starts at 12 o'clock and runs clockwise.
        bonusRing.path = UIBezierPath(arcCenter: CGPoint(x: ringRect.midX, y: ringRect.midY), radius: ringRect.width / 2,
                                      startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
        CATransaction.commit()
    }

    /// A glossy rounded segment with its own soft drop shadow baked in.
    private func segmentImage(tint: Int) -> CGImage? {
        let pad: CGFloat = 3
        let s = cell
        let lift: CGFloat = tint == 0 ? 0.0 : -0.05
        return UIGraphicsImageRenderer(size: CGSize(width: s + pad * 2, height: s + pad * 2)).image { rc in
            let ctx = rc.cgContext
            let rect = CGRect(x: pad + 0.75, y: pad + 0.75, width: s - 1.5, height: s - 1.5)
            drawGlossyBlob(ctx, rect: rect, radius: s * 0.38, lift: lift)
        }.cgImage
    }

    private func drawGlossyBlob(_ ctx: CGContext, rect: CGRect, radius: CGFloat, lift: CGFloat) {
        let space = CGColorSpaceCreateDeviceRGB()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 2, color: UIColor(white: 0, alpha: 0.35).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(snakeDark.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let colors = [adjust(snakeLight, lift), adjust(snakeMid, lift), adjust(snakeDark, lift)].map { $0.cgColor }
        if let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 0.55, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        }
        // Specular band across the top half.
        let shine = CGRect(x: rect.minX + rect.width * 0.12, y: rect.minY + 1, width: rect.width * 0.76, height: rect.height * 0.45)
        ctx.addPath(UIBezierPath(roundedRect: shine, cornerRadius: shine.height / 2).cgPath)
        ctx.clip()
        let shineColors = [UIColor(white: 1, alpha: 0.7).cgColor, UIColor(white: 1, alpha: 0.1).cgColor]
        if let g = CGGradient(colorsSpace: space, colors: shineColors as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: shine.minY), end: CGPoint(x: 0, y: shine.maxY), options: [])
        }
        ctx.restoreGState()

        ctx.addPath(path)
        ctx.setStrokeColor(adjust(snakeDark, -0.08).withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(0.8)
        ctx.strokePath()
    }

    private func adjust(_ color: UIColor, _ amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: min(max(b + amount, 0), 1), alpha: a)
    }

    /// Head drawn facing right (+x); the layer is rotated to the travel direction.
    private func headSprite(dead: Bool) -> CGImage? {
        let pad: CGFloat = 3
        let s = cell * 1.15
        return UIGraphicsImageRenderer(size: CGSize(width: s + pad * 2, height: s + pad * 2)).image { rc in
            let ctx = rc.cgContext
            let rect = CGRect(x: pad + 0.5, y: pad + 0.5, width: s - 1, height: s - 1)
            drawGlossyBlob(ctx, rect: rect, radius: s * 0.46, lift: 0.04)

            let eyeR = s * 0.15
            for ey in [rect.minY + s * 0.28, rect.maxY - s * 0.28] {
                let c = CGPoint(x: rect.minX + s * 0.64, y: ey)
                if dead {
                    ctx.setStrokeColor(UIColor(white: 0.1, alpha: 1).cgColor)
                    ctx.setLineWidth(1.4)
                    ctx.setLineCap(.round)
                    let k = eyeR * 0.75
                    ctx.move(to: CGPoint(x: c.x - k, y: c.y - k)); ctx.addLine(to: CGPoint(x: c.x + k, y: c.y + k))
                    ctx.move(to: CGPoint(x: c.x - k, y: c.y + k)); ctx.addLine(to: CGPoint(x: c.x + k, y: c.y - k))
                    ctx.strokePath()
                } else {
                    ctx.setFillColor(UIColor.white.cgColor)
                    ctx.fillEllipse(in: CGRect(x: c.x - eyeR, y: c.y - eyeR, width: eyeR * 2, height: eyeR * 2))
                    ctx.setStrokeColor(snakeDark.withAlphaComponent(0.6).cgColor)
                    ctx.setLineWidth(0.6)
                    ctx.strokeEllipse(in: CGRect(x: c.x - eyeR, y: c.y - eyeR, width: eyeR * 2, height: eyeR * 2))
                    let p = eyeR * 0.55
                    ctx.setFillColor(UIColor(white: 0.05, alpha: 1).cgColor)
                    ctx.fillEllipse(in: CGRect(x: c.x + eyeR * 0.35 - p, y: c.y - p, width: p * 2, height: p * 2))
                    ctx.setFillColor(UIColor.white.cgColor)
                    ctx.fillEllipse(in: CGRect(x: c.x + eyeR * 0.2, y: c.y - p * 0.8, width: p * 0.6, height: p * 0.6))
                }
            }
            // Nostrils
            ctx.setFillColor(snakeDark.withAlphaComponent(0.7).cgColor)
            for ny in [rect.midY - s * 0.09, rect.midY + s * 0.09] {
                ctx.fillEllipse(in: CGRect(x: rect.maxX - s * 0.12, y: ny - 0.7, width: 1.4, height: 1.4))
            }
        }.cgImage
    }

    /// Shiny apple: lobed body, highlight, stem and leaf. Golden for the bonus.
    private func appleSprite(golden: Bool) -> CGImage? {
        let size = cell * 1.25 + 6
        let d = cell * 1.0
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { rc in
            let ctx = rc.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let c = CGPoint(x: size / 2, y: size / 2 + d * 0.06)
            let w = d * 0.92, h = d * 0.86
            // Two overlapping lobes and a dimple on top.
            let body = UIBezierPath()
            body.move(to: CGPoint(x: c.x, y: c.y - h * 0.36))
            body.addCurve(to: CGPoint(x: c.x + w / 2, y: c.y - h * 0.05),
                          controlPoint1: CGPoint(x: c.x + w * 0.22, y: c.y - h * 0.62),
                          controlPoint2: CGPoint(x: c.x + w / 2, y: c.y - h * 0.45))
            body.addCurve(to: CGPoint(x: c.x, y: c.y + h / 2),
                          controlPoint1: CGPoint(x: c.x + w / 2, y: c.y + h * 0.35),
                          controlPoint2: CGPoint(x: c.x + w * 0.2, y: c.y + h * 0.55))
            body.addCurve(to: CGPoint(x: c.x - w / 2, y: c.y - h * 0.05),
                          controlPoint1: CGPoint(x: c.x - w * 0.2, y: c.y + h * 0.55),
                          controlPoint2: CGPoint(x: c.x - w / 2, y: c.y + h * 0.35))
            body.addCurve(to: CGPoint(x: c.x, y: c.y - h * 0.36),
                          controlPoint1: CGPoint(x: c.x - w / 2, y: c.y - h * 0.45),
                          controlPoint2: CGPoint(x: c.x - w * 0.22, y: c.y - h * 0.62))
            body.close()

            let light = golden ? UIColor(red: 1, green: 0.93, blue: 0.55, alpha: 1) : UIColor(red: 1, green: 0.5, blue: 0.45, alpha: 1)
            let mid = golden ? UIColor(red: 0.95, green: 0.72, blue: 0.1, alpha: 1) : UIColor(red: 0.86, green: 0.08, blue: 0.08, alpha: 1)
            let dark = golden ? UIColor(red: 0.6, green: 0.38, blue: 0.02, alpha: 1) : UIColor(red: 0.48, green: 0.0, blue: 0.02, alpha: 1)

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 2.5, color: UIColor(white: 0, alpha: 0.4).cgColor)
            ctx.addPath(body.cgPath)
            ctx.setFillColor(dark.cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(body.cgPath)
            ctx.clip()
            if let g = CGGradient(colorsSpace: space, colors: [light.cgColor, mid.cgColor, dark.cgColor] as CFArray,
                                  locations: [0, 0.5, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - w * 0.18, y: c.y - h * 0.15), startRadius: 0,
                                       endCenter: c, endRadius: w * 0.62, options: [.drawsAfterEndLocation])
            }
            ctx.restoreGState()

            // Highlight
            ctx.setFillColor(UIColor(white: 1, alpha: 0.75).cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - w * 0.32, y: c.y - h * 0.26, width: w * 0.22, height: h * 0.16))

            // Stem and leaf
            ctx.setStrokeColor(UIColor(red: 0.4, green: 0.25, blue: 0.1, alpha: 1).cgColor)
            ctx.setLineWidth(max(1.2, d * 0.08))
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: c.x, y: c.y - h * 0.32))
            ctx.addQuadCurve(to: CGPoint(x: c.x + w * 0.08, y: c.y - h * 0.62), control: CGPoint(x: c.x - w * 0.02, y: c.y - h * 0.5))
            ctx.strokePath()
            let leaf = UIBezierPath()
            let base = CGPoint(x: c.x + w * 0.06, y: c.y - h * 0.5)
            let tip = CGPoint(x: c.x + w * 0.42, y: c.y - h * 0.66)
            leaf.move(to: base)
            leaf.addQuadCurve(to: tip, controlPoint: CGPoint(x: c.x + w * 0.2, y: c.y - h * 0.8))
            leaf.addQuadCurve(to: base, controlPoint: CGPoint(x: c.x + w * 0.3, y: c.y - h * 0.44))
            leaf.close()
            ctx.addPath(leaf.cgPath)
            ctx.setFillColor(UIColor(red: 0.3, green: 0.7, blue: 0.2, alpha: 1).cgColor)
            ctx.fillPath()
        }.cgImage
    }

    private func addBob(to layer: CALayer) {
        let bob = CABasicAnimation(keyPath: "transform.scale")
        bob.fromValue = 0.9
        bob.toValue = 1.06
        bob.duration = 0.6
        bob.autoreverses = true
        bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bob.isRemovedOnCompletion = false
        layer.add(bob, forKey: "bob")
    }

    // MARK: - Rendering

    private func point(_ c: Cell) -> CGPoint {
        CGPoint(x: fieldOrigin.x + (CGFloat(c.x) + 0.5) * cell, y: fieldOrigin.y + (CGFloat(c.y) + 0.5) * cell)
    }

    private func interpolated(_ i: Int, _ t: CGFloat) -> CGPoint {
        let to = point(body[i])
        guard i < previousBody.count else { return to }
        let from = point(previousBody[i])
        return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
    }

    /// Positions every segment `t` of the way through the current step.
    private func render(progress t: CGFloat) {
        let t = min(max(t, 0), 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Grow the layer pool as needed (never per frame once the snake is long).
        let segments = body.count - 1
        while segmentLayers.count < segments {
            let layer = CALayer()
            layer.contentsScale = UIScreen.main.scale
            layer.bounds = CGRect(x: 0, y: 0, width: cell + 6, height: cell + 6)
            snakeLayer.insertSublayer(layer, below: headLayer)
            segmentLayers.append(layer)
        }
        for (i, layer) in segmentLayers.enumerated() {
            let index = i + 1
            guard index < body.count else { layer.isHidden = true; continue }
            layer.isHidden = false
            layer.position = interpolated(index, t)
            // A segment keeps its index for life, so alternate bands travel with the body.
            let image = segmentImages.isEmpty ? nil : segmentImages[index % segmentImages.count]
            if (layer.contents as AnyObject?) !== image { layer.contents = image }
            // The last few segments taper toward the tail.
            let fromTail = body.count - 1 - index
            let scale: CGFloat = fromTail >= 3 ? 1 : 0.72 + 0.09 * CGFloat(fromTail)
            layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            // Later segments sit beneath earlier ones.
            layer.zPosition = -CGFloat(index)
        }
        headLayer.position = interpolated(0, t)

        // Spine: segment i always slides into the cell its leader just left (body[i]),
        // so routing through that cell's centre bends the body around corners.
        let spine = UIBezierPath()
        spine.move(to: headLayer.position)
        for i in 1..<body.count {
            spine.addLine(to: point(body[i]))
            spine.addLine(to: interpolated(i, t))
        }
        spineLayer.lineWidth = cell * 0.62
        spineLayer.path = spine.cgPath
        headLayer.setAffineTransform(CGAffineTransform(rotationAngle: direction.angle))
        headLayer.zPosition = 1

        foodLayer.position = point(food)
        if let bonus {
            bonusLayer.isHidden = false
            bonusLayer.position = point(bonus)
            bonusRing.strokeEnd = max(0, bonusTimeLeft / bonusLifetime)
            // Blink for the last second and a half.
            bonusLayer.opacity = bonusTimeLeft > 1.5 ? 1 : (Int(bonusTimeLeft * 8) % 2 == 0 ? 1 : 0.35)
        } else {
            bonusLayer.isHidden = true
        }
        CATransaction.commit()
    }

    // MARK: - Frame loop

    override func update(dt: CGFloat) {
        switch phase {
        case .playing:
            if bonus != nil {
                bonusTimeLeft -= dt
                if bonusTimeLeft <= 0 { bonus = nil }
            }
            stepClock += dt
            while phase == .playing, stepClock >= stepInterval {
                stepClock -= stepInterval
                step()
            }
            if phase == .playing { render(progress: stepClock / stepInterval) }
        case .dying:
            dyingClock += dt
            snakeLayer.opacity = Int(dyingClock * 10) % 2 == 0 ? 1 : 0.3
            if dyingClock >= dyingDuration {
                snakeLayer.opacity = 1
                phase = .gameOver
                showGameOver(score: score)
            }
        default:
            break
        }
    }

    private func step() {
        if !turnQueue.isEmpty { direction = direction.turned(turnQueue.removeFirst()) }
        wheelTurnedThisStep = false

        let head = body[0]
        let next = Cell(x: head.x + direction.dx, y: head.y + direction.dy)
        let growing = pendingGrowth > 0 || next == food

        // Walls, then self (the tail cell is free unless we're about to grow).
        let blocking = growing ? body[...] : body.dropLast()
        if next.x < 0 || next.y < 0 || next.x >= cols || next.y >= rows || blocking.contains(next) {
            die()
            return
        }

        let old = body
        body.insert(next, at: 0)
        if pendingGrowth > 0 || next == food {
            if pendingGrowth > 0 { pendingGrowth -= 1 }
        } else {
            body.removeLast()
        }
        // Each segment slides from where it was; a freshly grown tail starts still.
        previousBody = body.indices.map { $0 < old.count ? old[$0] : old[old.count - 1] }

        if next == food { eatApple() }
        if let b = bonus, next == b { eatBonus() }
    }

    private func eatApple() {
        score += applePoints
        applesEaten += 1
        // The apple's own growth is applied by the step that ate it; anything extra is deferred.
        pendingGrowth += growthPerApple - 1
        hudScore = score
        haptic(.light, 0.6)
        if applesEaten % bonusEvery == 0 { spawnBonus() }
        if !spawnFood() { win() }
    }

    private func eatBonus() {
        let points = 50 + Int(bonusTimeLeft * 15)
        score += points
        hudScore = score
        bonus = nil
        haptic(.medium, 0.8)
    }

    private func freeCells(excluding extra: [Cell]) -> [Cell] {
        var occupied = Set<Int>()
        for c in body + extra { occupied.insert(c.y * cols + c.x) }
        var result: [Cell] = []
        for y in 0..<rows {
            for x in 0..<cols where !occupied.contains(y * cols + x) { result.append(Cell(x: x, y: y)) }
        }
        return result
    }

    /// Returns false if there's nowhere left to put food (the board is full).
    @discardableResult
    private func spawnFood() -> Bool {
        let extra = bonus.map { [$0] } ?? []
        guard let cell = freeCells(excluding: extra).randomElement() else { return false }
        food = cell
        return true
    }

    private func spawnBonus() {
        // Keep it off the apple and not right under the snake's nose.
        let head = body[0]
        let options = freeCells(excluding: [food]).filter { abs($0.x - head.x) + abs($0.y - head.y) > 3 }
        guard let cell = options.randomElement() else { return }
        bonus = cell
        bonusTimeLeft = bonusLifetime
    }

    private func die() {
        phase = .dying
        dyingClock = 0
        turnQueue.removeAll()
        headLayer.contents = deadHeadImage
        render(progress: 1)
        haptic(.heavy, 1)
    }

    private func win() {
        phase = .gameOver
        render(progress: 1)
        showGameOver(score: score, title: "YOU WIN!")
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle, _ intensity: CGFloat) {
        guard SettingsStore.shared.clickerEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
    }

    // MARK: - Input

    private func queueTurn(_ turn: Turn) {
        guard phase == .playing, turnQueue.count < maxQueuedTurns else { return }
        turnQueue.append(turn)
    }

    /// One wheel click = one turn, but a fast flick only counts once per step
    /// so it can't fold the snake back on itself.
    override func wheelRotated(_ direction: RotationDirection) {
        guard phase == .playing, !wheelTurnedThisStep else { return }
        let now = CACurrentMediaTime()
        guard now - lastWheelTurnTime >= wheelDebounce else { return }
        lastWheelTurnTime = now
        wheelTurnedThisStep = true
        queueTurn(direction == .CLOCKWISE ? .right : .left)
    }

    override func nextPressed() { queueTurn(.right) }
    override func previousPressed() { queueTurn(.left) }

    override func selectPressed() {
        switch phase {
        case .ready:
            hideMessage()
            stepClock = 0
            phase = .playing
        case .gameOver:
            resetGame()
        default:
            break
        }
    }
}
