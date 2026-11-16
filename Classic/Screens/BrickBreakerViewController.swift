//
//  BrickBreakerViewController.swift
//  Classic
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//
//  iPod Brick follows Atari Breakout's difficulty rules (Brick is Apple's
//  Breakout remake): the ball speeds up after the 4th and 12th hits and the
//  first time it reaches the orange and red rows, and the paddle shrinks once
//  the ball breaks through to the back wall. On top of that the ball creeps
//  faster the longer a rally lasts, and every level starts faster than the last.
//

import UIKit

class BrickBreakerViewController: PodGameViewController {

    private enum Phase { case waitingToLaunch, playing, levelCleared, gameOver }

    private struct Brick {
        let view: UIView
        let row: Int
        var alive: Bool
    }

    override var gameTitle: String { "Brick" }

    // Game state
    private var phase: Phase = .waitingToLaunch
    private var score = 0
    private var lives = 3
    private var level = 1

    // Difficulty state (reset for each ball)
    private var hits = 0
    private var speedBoosts = 0          // number of Breakout-style speed steps taken
    private var reachedOrange = false
    private var reachedRed = false
    private var paddleShrunk = false
    private var rallyTime: CGFloat = 0

    // Views
    private var bricks: [Brick] = []
    private let paddle = UIView()
    private var ball: UIView!
    private var background: CAGradientLayer?

    // Physics (points per second)
    private var velocity = CGVector.zero
    private var paddleTargetX: CGFloat = 0

    // Layout
    private let brickRows = 8
    private let brickColumns = 11
    private let brickHeight: CGFloat = 10
    private let brickSpacing: CGFloat = 2
    private let brickTopOffset: CGFloat = 4
    private let paddleHeight: CGFloat = 10
    private let paddleBottomOffset: CGFloat = 12
    private let ballSize: CGFloat = 9

    // Tuning
    private let baseSpeed: CGFloat = 165          // level 1 launch speed
    private let levelSpeedStep: CGFloat = 0.10    // +10% per level
    private let boostFactor: CGFloat = 1.13       // per Breakout speed step
    private let rallyRampPerSecond: CGFloat = 0.006
    private let maxSpeedMultiplier: CGFloat = 2.6
    private let maxBounceAngle: CGFloat = .pi / 3 // 60° from vertical at paddle edge

    // Top to bottom: red, red, orange, orange, yellow, yellow, green, green.
    private let rowColors: [UIColor] = [
        UIColor(red: 210/255, green: 50/255, blue: 50/255, alpha: 1),
        UIColor(red: 210/255, green: 50/255, blue: 50/255, alpha: 1),
        UIColor(red: 225/255, green: 130/255, blue: 30/255, alpha: 1),
        UIColor(red: 225/255, green: 130/255, blue: 30/255, alpha: 1),
        UIColor(red: 215/255, green: 205/255, blue: 40/255, alpha: 1),
        UIColor(red: 215/255, green: 205/255, blue: 40/255, alpha: 1),
        UIColor(red: 45/255, green: 175/255, blue: 45/255, alpha: 1),
        UIColor(red: 45/255, green: 175/255, blue: 45/255, alpha: 1),
    ]
    /// Breakout scoring: green 1, yellow 3, orange 5, red 7 (×10 for a meatier HUD).
    private func points(forRow row: Int) -> Int { [70, 70, 50, 50, 30, 30, 10, 10][row] }

    private var fullPaddleWidth: CGFloat { view.bounds.width * 0.15 }

    // MARK: - Setup

    override func setupGame() {
        background = GameStyle.gradientLayer(GameStyle.skyTop, GameStyle.skyBottom, frame: view.bounds)
        view.layer.insertSublayer(background!, at: 0)

        paddle.backgroundColor = .black
        paddle.layer.cornerRadius = 2
        view.addSubview(paddle)

        ball = GameStyle.sphereView(diameter: ballSize)
        view.addSubview(ball)

        paddle.frame.size = CGSize(width: fullPaddleWidth, height: paddleHeight)
        paddle.center.x = view.bounds.midX
        paddleTargetX = paddle.center.x
        buildLevel()
        resetBall()
    }

    override func layoutGame() {
        background?.frame = view.bounds
        paddle.frame.size.width = paddleShrunk ? fullPaddleWidth * 0.6 : fullPaddleWidth
        paddle.frame.origin.y = view.bounds.height - paddleBottomOffset - paddleHeight
        clampPaddle()
        if phase == .waitingToLaunch {
            layoutBricks()
            resetBall()
        }
    }

    override func refreshHUD() {
        hudScore = score
        hudLives = lives
    }

    // MARK: - Levels

    /// Later levels knock holes in the wall so they play differently, not just faster.
    private func brickExists(row: Int, col: Int) -> Bool {
        switch (level - 1) % 4 {
        case 1: return (row + col) % 2 == 0 || row >= 6                     // checkerboard
        case 2: return !(col == 2 || col == 5 || col == 8) || row < 2        // pillars
        case 3: return abs(col - brickColumns / 2) <= row                    // pyramid
        default: return true                                                 // full wall
        }
    }

    private func buildLevel() {
        bricks.forEach { $0.view.removeFromSuperview() }
        bricks.removeAll()
        for row in 0..<brickRows {
            for col in 0..<brickColumns where brickExists(row: row, col: col) {
                let v = UIView()
                v.tag = col
                v.layer.shadowColor = UIColor.black.cgColor
                v.layer.shadowOffset = CGSize(width: 1, height: 2)
                v.layer.shadowOpacity = 0.5
                v.layer.shadowRadius = 0
                view.insertSubview(v, belowSubview: paddle)
                bricks.append(Brick(view: v, row: row, alive: true))
            }
        }
        layoutBricks()
    }

    private func layoutBricks() {
        let width = (view.bounds.width - CGFloat(brickColumns - 1) * brickSpacing) / CGFloat(brickColumns)
        for brick in bricks {
            let frame = CGRect(x: CGFloat(brick.view.tag) * (width + brickSpacing),
                               y: brickTopOffset + CGFloat(brick.row) * (brickHeight + brickSpacing),
                               width: width, height: brickHeight)
            guard brick.view.frame != frame else { continue }
            brick.view.frame = frame
            brick.view.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            let color = rowColors[brick.row]
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let light = UIColor(hue: h, saturation: max(s - 0.15, 0), brightness: min(b + 0.25, 1), alpha: 1)
            let dark = UIColor(hue: h, saturation: min(s + 0.1, 1), brightness: max(b - 0.15, 0), alpha: 1)
            brick.view.backgroundColor = color
            brick.view.layer.addSublayer(GameStyle.gradientLayer(light, dark, frame: brick.view.bounds))
        }
    }

    // MARK: - Ball

    private func resetBall() {
        velocity = .zero
        hits = 0
        speedBoosts = 0
        reachedOrange = false
        reachedRed = false
        rallyTime = 0
        setPaddleShrunk(false)
        ball.center = CGPoint(x: paddle.center.x, y: paddle.frame.minY - ballSize / 2 - 1)
    }

    private var levelSpeed: CGFloat { baseSpeed * (1 + levelSpeedStep * CGFloat(level - 1)) }

    /// Current target speed from all the difficulty rules.
    private var currentSpeed: CGFloat {
        let multiplier = pow(boostFactor, CGFloat(speedBoosts)) * (1 + rallyRampPerSecond * rallyTime)
        return levelSpeed * min(multiplier, maxSpeedMultiplier)
    }

    private func launch() {
        let angle = CGFloat.random(in: -0.4...0.4)
        velocity = CGVector(dx: sin(angle) * levelSpeed, dy: -cos(angle) * levelSpeed)
        phase = .playing
    }

    private func setSpeed(_ speed: CGFloat) {
        let current = hypot(velocity.dx, velocity.dy)
        guard current > 0 else { return }
        velocity.dx *= speed / current
        velocity.dy *= speed / current
    }

    private func boost() {
        speedBoosts += 1
    }

    private func setPaddleShrunk(_ shrunk: Bool) {
        guard shrunk != paddleShrunk else { return }
        paddleShrunk = shrunk
        let center = paddle.center.x
        UIView.animate(withDuration: 0.15) {
            self.paddle.frame.size.width = shrunk ? self.fullPaddleWidth * 0.6 : self.fullPaddleWidth
            self.paddle.center.x = center
        }
    }

    // MARK: - Frame loop

    override func update(dt: CGFloat) {
        movePaddle(dt: dt)
        guard phase == .playing else {
            if phase == .waitingToLaunch {
                ball.center.x = paddle.center.x
            }
            return
        }

        rallyTime += dt
        setSpeed(currentSpeed)

        // Sub-step so a fast ball never skips through a 10pt brick.
        let distance = hypot(velocity.dx, velocity.dy) * dt
        let steps = max(1, Int(ceil(distance / (ballSize * 0.4))))
        let stepDt = dt / CGFloat(steps)
        for _ in 0..<steps {
            step(dt: stepDt)
            if phase != .playing { break }
        }
    }

    private func movePaddle(dt: CGFloat) {
        // Ease toward the wheel target so the paddle glides rather than teleports.
        let blend = min(1, dt * 30)
        paddle.center.x += (paddleTargetX - paddle.center.x) * blend
        clampPaddle()
    }

    private func clampPaddle() {
        let half = paddle.frame.width / 2
        paddle.center.x = min(max(paddle.center.x, half), view.bounds.width - half)
        paddleTargetX = min(max(paddleTargetX, half), view.bounds.width - half)
    }

    private func step(dt: CGFloat) {
        let previous = ball.frame
        ball.center.x += velocity.dx * dt
        ball.center.y += velocity.dy * dt
        let f = ball.frame
        let w = view.bounds.width

        // Walls
        if f.minX <= 0 { velocity.dx = abs(velocity.dx); ball.frame.origin.x = 0 }
        if f.maxX >= w { velocity.dx = -abs(velocity.dx); ball.frame.origin.x = w - ballSize }
        if f.minY <= 0 {
            velocity.dy = abs(velocity.dy)
            ball.frame.origin.y = 0
            // Breaking through to the back wall shrinks the paddle.
            if reachedRed { setPaddleShrunk(true) }
        }

        // Paddle
        let p = paddle.frame
        if velocity.dy > 0, previous.maxY <= p.minY + 1, f.maxY >= p.minY,
           f.maxX >= p.minX, f.minX <= p.maxX {
            ball.frame.origin.y = p.minY - ballSize
            // Where it lands on the paddle sets the angle — edges send it wide.
            let offset = min(max((ball.center.x - p.midX) / (p.width / 2), -1), 1)
            let angle = offset * maxBounceAngle
            let speed = hypot(velocity.dx, velocity.dy)
            velocity = CGVector(dx: sin(angle) * speed, dy: -cos(angle) * speed)
            tick(.light)
        }

        // Bricks
        for i in bricks.indices where bricks[i].alive {
            let b = bricks[i].view.frame
            guard ball.frame.intersects(b) else { continue }
            bricks[i].alive = false
            bricks[i].view.isHidden = true

            // Reflect on the axis of least penetration, using the pre-move frame.
            if previous.maxX <= b.minX || previous.minX >= b.maxX {
                velocity.dx = -velocity.dx
            } else {
                velocity.dy = -velocity.dy
            }

            score += points(forRow: bricks[i].row)
            hudScore = score
            registerHit(row: bricks[i].row)
            break
        }

        // Ball lost
        if ball.frame.minY >= view.bounds.height {
            lives -= 1
            hudLives = lives
            tick(.heavy)
            if lives > 0 {
                phase = .waitingToLaunch
                resetBall()
            } else {
                phase = .gameOver
                showGameOver(score: score)
            }
            return
        }

        if !bricks.contains(where: { $0.alive }) {
            levelCleared()
        }
    }

    private func registerHit(row: Int) {
        hits += 1
        if hits == 4 || hits == 12 { boost() }
        if row <= 3 && !reachedOrange { reachedOrange = true; boost() }
        if row <= 1 && !reachedRed { reachedRed = true; boost() }
    }

    private func levelCleared() {
        phase = .levelCleared
        level += 1
        showMessage("LEVEL \(level)", lines: ["Score: \(score)"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.phase == .levelCleared else { return }
            self.hideMessage()
            self.buildLevel()
            self.phase = .waitingToLaunch
            self.resetBall()
        }
    }

    private func restart() {
        hideMessage()
        score = 0
        lives = 3
        level = 1
        refreshHUD()
        buildLevel()
        paddle.center.x = view.bounds.midX
        paddleTargetX = paddle.center.x
        phase = .waitingToLaunch
        resetBall()
    }

    private func tick(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard SettingsStore.shared.clickerEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: 0.5)
    }

    // MARK: - Input

    // Analog wheel: half a turn sweeps the paddle across the whole screen.
    override var prefersContinuousWheelInput: Bool { true }

    override func clickWheelDidRotateContinuously(event: ClickWheelRotationEvent) {
        guard !isGamePaused, event.state == .changed else { return }
        paddleTargetX += event.deltaRadians / .pi * view.bounds.width
        clampPaddle()
    }

    override func selectPressed() {
        switch phase {
        case .waitingToLaunch: launch()
        case .gameOver: restart()
        default: break
        }
    }
}
