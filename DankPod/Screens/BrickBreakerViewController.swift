//
//  BrickBreakerViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

enum BrickGameState {
    case waitingToLaunch
    case playing
    case paused
    case gameOver
}

class BrickBreakerViewController: UIViewController, ClickWheelProtocol {

    // Game state
    var state: BrickGameState = .waitingToLaunch
    var score: Int = 0
    var lives: Int = 3
    var level: Int = 1
    var hasSetupUI: Bool = false

    // Game views
    var paddle: UIView!
    var ball: UIView!
    var bricks: [UIView] = []
    var pausedLabel: UILabel!
    var gameOverOverlay: UIView!
    var lastLayoutWidth: CGFloat = 0
    var lastLayoutHeight: CGFloat = 0

    // Game physics
    var ballDX: CGFloat = 0
    var ballDY: CGFloat = 0
    let initialBallSpeed: CGFloat = 3.0
    var displayLink: CADisplayLink?
    var lastTimestamp: CFTimeInterval = 0
    let targetFrameTime: CFTimeInterval = 1.0 / 60.0

    // Layout constants — no in-game info bar; bricks start at the very top
    let brickRows: Int = 8
    let brickColumns: Int = 11
    let brickHeight: CGFloat = 10.0
    let brickSpacing: CGFloat = 2.0
    let brickTopOffset: CGFloat = 4.0
    let paddleHeight: CGFloat = 5.0
    let paddleBottomOffset: CGFloat = 12.0
    let ballSize: CGFloat = 7.0

    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Brick"
        AppDelegate.baseVC.navBarScore = score
        AppDelegate.baseVC.navBarBalls = lives
        if displayLink == nil {
            lastTimestamp = 0
            displayLink = CADisplayLink(target: self, selector: #selector(gameLoop(_:)))
            displayLink?.add(to: .main, forMode: .common)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        displayLink?.invalidate()
        displayLink = nil
        // Clear game HUD from nav bar
        AppDelegate.baseVC.navBarScore = nil
        AppDelegate.baseVC.navBarBalls = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard hasSetupUI else { return }
        let w = view.bounds.width
        let h = view.bounds.height
        guard w != lastLayoutWidth || h != lastLayoutHeight else { return }
        lastLayoutWidth = w
        lastLayoutHeight = h

        let paddleWidth = w * 0.22
        paddle.frame.size.width = paddleWidth
        paddle.frame.size.height = paddleHeight
        paddle.center.x = min(max(paddle.center.x, paddleWidth / 2), w - paddleWidth / 2)
        paddle.frame.origin.y = h - paddleBottomOffset - paddleHeight

        pausedLabel.center = CGPoint(x: w / 2, y: h / 2)

        if state == .waitingToLaunch {
            createBricks()
            resetBallOnPaddle()
        }

        if state == .gameOver, let overlay = gameOverOverlay {
            overlay.frame = view.bounds
        }

        // Re-apply gradient background when bounds are known
        applyBackgroundGradient()
    }

    deinit {
        displayLink?.invalidate()
        displayLink = nil
    }

    func applyBackgroundGradient() {
        view.layer.sublayers?.removeAll(where: { $0 is CAGradientLayer })
        let gradient = CAGradientLayer()
        gradient.frame = view.bounds
        gradient.colors = [
            UIColor(red: 100/255.0, green: 160/255.0, blue: 210/255.0, alpha: 1.0).cgColor,
            UIColor(red: 60/255.0, green: 110/255.0, blue: 170/255.0, alpha: 1.0).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        view.layer.insertSublayer(gradient, at: 0)
    }

    func setupUI() {
        if !hasSetupUI {
            view.clipsToBounds = true
            view.backgroundColor = UIColor(red: 80/255.0, green: 130/255.0, blue: 190/255.0, alpha: 1.0)

            // Create bricks
            createBricks()

            // Create ball — small black square (no corner radius), like the original
            ball = UIView()
            ball.frame = CGRect(x: 0, y: 0, width: ballSize, height: ballSize)
            ball.backgroundColor = .black
            view.addSubview(ball)

            // Create paddle — short black rounded rect
            let paddleWidth = view.bounds.width * 0.22
            paddle = UIView()
            paddle.frame = CGRect(x: 0, y: 0, width: paddleWidth, height: paddleHeight)
            paddle.backgroundColor = .black
            paddle.layer.cornerRadius = 2
            paddle.center.x = view.bounds.width / 2
            paddle.frame.origin.y = view.bounds.height - paddleBottomOffset - paddleHeight
            view.addSubview(paddle)

            resetBallOnPaddle()

            // Paused label
            pausedLabel = UILabel()
            pausedLabel.text = "PAUSED"
            pausedLabel.textColor = .white
            pausedLabel.font = UIFont(name: "Helvetica-Bold", size: 18)
            pausedLabel.textAlignment = .center
            pausedLabel.sizeToFit()
            pausedLabel.center = CGPoint(x: view.bounds.width / 2, y: view.bounds.height / 2)
            pausedLabel.isHidden = true
            view.addSubview(pausedLabel)

            hasSetupUI = true
        }
    }

    func createBricks() {
        for brick in bricks {
            brick.removeFromSuperview()
        }
        bricks.removeAll()

        let totalSpacing = CGFloat(brickColumns - 1) * brickSpacing
        let brickWidth = (view.bounds.width - totalSpacing) / CGFloat(brickColumns)

        // Original iPod BrickBreaker colour rows: red, red, orange, orange, yellow, yellow, green, green
        let rowColors: [UIColor] = [
            UIColor(red: 210/255.0, green: 50/255.0,  blue: 50/255.0,  alpha: 1.0),
            UIColor(red: 210/255.0, green: 50/255.0,  blue: 50/255.0,  alpha: 1.0),
            UIColor(red: 225/255.0, green: 130/255.0, blue: 30/255.0,  alpha: 1.0),
            UIColor(red: 225/255.0, green: 130/255.0, blue: 30/255.0,  alpha: 1.0),
            UIColor(red: 215/255.0, green: 205/255.0, blue: 40/255.0,  alpha: 1.0),
            UIColor(red: 215/255.0, green: 205/255.0, blue: 40/255.0,  alpha: 1.0),
            UIColor(red: 45/255.0,  green: 175/255.0, blue: 45/255.0,  alpha: 1.0),
            UIColor(red: 45/255.0,  green: 175/255.0, blue: 45/255.0,  alpha: 1.0)
        ]

        for row in 0..<brickRows {
            for col in 0..<brickColumns {
                let brick = UIView()
                let x = CGFloat(col) * (brickWidth + brickSpacing)
                let y = brickTopOffset + CGFloat(row) * (brickHeight + brickSpacing)
                brick.frame = CGRect(x: x, y: y, width: brickWidth, height: brickHeight)
                brick.backgroundColor = rowColors[row]

                // Blocky shadow to match original iPod look
                brick.layer.shadowColor = UIColor.black.cgColor
                brick.layer.shadowOffset = CGSize(width: 1, height: 2)
                brick.layer.shadowOpacity = 0.6
                brick.layer.shadowRadius = 0

                view.addSubview(brick)
                bricks.append(brick)
            }
        }

        if ball != nil { view.bringSubviewToFront(ball) }
        if paddle != nil { view.bringSubviewToFront(paddle) }
        if pausedLabel != nil { view.bringSubviewToFront(pausedLabel) }
    }

    @objc func gameLoop(_ link: CADisplayLink) {
        guard state == .playing else {
            lastTimestamp = link.timestamp
            return
        }

        if lastTimestamp == 0 { lastTimestamp = link.timestamp }
        var dt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        if dt > targetFrameTime * 3.0 { dt = targetFrameTime }
        let scale = CGFloat(dt / targetFrameTime)

        let previousBallMaxY = ball.frame.maxY

        ball.center.x += ballDX * scale
        ball.center.y += ballDY * scale

        // Wall collisions
        if ball.frame.minX <= 0 { ballDX = abs(ballDX) }
        if ball.frame.maxX >= view.bounds.width { ballDX = -abs(ballDX) }
        if ball.frame.minY <= 0 { ballDY = abs(ballDY) }

        // Paddle collision (swept)
        if ballDY > 0 &&
           previousBallMaxY <= paddle.frame.maxY &&
           ball.frame.maxY >= paddle.frame.minY &&
           ball.frame.maxX >= paddle.frame.minX &&
           ball.frame.minX <= paddle.frame.maxX {
            ball.frame.origin.y = paddle.frame.origin.y - ballSize
            ballDY = -abs(ballDY)
            let hitPosition = min(max((ball.center.x - paddle.frame.minX) / paddle.frame.width, 0.0), 1.0)
            ballDX = (hitPosition - 0.5) * 5.0
        }

        // Brick collisions
        for brick in bricks where !brick.isHidden {
            if ball.frame.intersects(brick.frame) {
                brick.isHidden = true

                let dx = ball.center.x - brick.center.x
                let dy = ball.center.y - brick.center.y
                if abs(dx / brick.frame.width) > abs(dy / brick.frame.height) {
                    ballDX = -ballDX
                } else {
                    ballDY = -ballDY
                }

                score += 10
                AppDelegate.baseVC.navBarScore = score
                break
            }
        }

        // Ball lost
        if ball.frame.minY >= view.bounds.height {
            lives -= 1
            AppDelegate.baseVC.navBarBalls = lives
            if lives > 0 {
                resetBallOnPaddle()
                state = .waitingToLaunch
            } else {
                state = .gameOver
                showGameOver()
            }
        }

        // Level complete
        if bricks.allSatisfy({ $0.isHidden }) {
            level += 1
            createBricks()
            resetBallOnPaddle()
            state = .waitingToLaunch
        }

        // Anti-stuck
        if abs(ballDY) < 1.0 && state == .playing {
            ballDY = ballDY > 0 ? 1.5 : -1.5
        }
    }

    func resetBallOnPaddle() {
        ballDX = 0
        ballDY = 0
        ball.center.x = paddle.center.x
        ball.frame.origin.y = paddle.frame.origin.y - ballSize - 1
    }

    func showGameOver() {
        gameOverOverlay = UIView()
        gameOverOverlay.frame = view.bounds
        gameOverOverlay.backgroundColor = UIColor(red: 60/255.0, green: 110/255.0, blue: 170/255.0, alpha: 0.85)

        let gameOverLabel = UILabel()
        gameOverLabel.text = "GAME OVER"
        gameOverLabel.textColor = .white
        gameOverLabel.font = UIFont(name: "Helvetica-Bold", size: 18)
        gameOverLabel.textAlignment = .center
        gameOverLabel.sizeToFit()
        gameOverLabel.center = CGPoint(x: gameOverOverlay.bounds.width / 2, y: gameOverOverlay.bounds.height / 2 - 25)
        gameOverOverlay.addSubview(gameOverLabel)

        let scoreResultLabel = UILabel()
        scoreResultLabel.text = "Score: \(score)"
        scoreResultLabel.textColor = .white
        scoreResultLabel.font = UIFont(name: "Helvetica-Bold", size: 14)
        scoreResultLabel.textAlignment = .center
        scoreResultLabel.sizeToFit()
        scoreResultLabel.center = CGPoint(x: gameOverOverlay.bounds.width / 2, y: gameOverOverlay.bounds.height / 2 + 5)
        gameOverOverlay.addSubview(scoreResultLabel)

        let restartLabel = UILabel()
        restartLabel.text = "Press center to play again"
        restartLabel.textColor = .white
        restartLabel.font = UIFont(name: "Helvetica", size: 11)
        restartLabel.textAlignment = .center
        restartLabel.sizeToFit()
        restartLabel.center = CGPoint(x: gameOverOverlay.bounds.width / 2, y: gameOverOverlay.bounds.height / 2 + 30)
        gameOverOverlay.addSubview(restartLabel)

        view.addSubview(gameOverOverlay)
    }

    func resetGame() {
        gameOverOverlay?.removeFromSuperview()
        gameOverOverlay = nil
        score = 0
        lives = 3
        level = 1
        AppDelegate.baseVC.navBarScore = score
        AppDelegate.baseVC.navBarBalls = lives
        createBricks()
        paddle.center.x = view.bounds.width / 2
        resetBallOnPaddle()
        state = .waitingToLaunch
    }

    // MARK: - ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        let moveAmount: CGFloat = 8.0
        if rotationDirection == .CLOCKWISE {
            paddle.center.x = min(paddle.center.x + moveAmount, view.bounds.width - paddle.frame.width / 2)
        } else {
            paddle.center.x = max(paddle.center.x - moveAmount, paddle.frame.width / 2)
        }
        if state == .waitingToLaunch {
            ball.center.x = paddle.center.x
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        switch state {
        case .waitingToLaunch:
            ballDX = CGFloat.random(in: -1.5...1.5)
            ballDY = -(initialBallSpeed * (1.0 + 0.1 * CGFloat(level - 1)))
            state = .playing
        case .gameOver:
            resetGame()
        default:
            break
        }
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        if state == .playing {
            state = .paused
            pausedLabel.isHidden = false
        } else if state == .paused {
            state = .playing
            pausedLabel.isHidden = true
        }
    }

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            displayLink?.invalidate()
            displayLink = nil
            self.navigationController?.popViewController(animated: true)
        } else if pressure == .FORCE {
            displayLink?.invalidate()
            displayLink = nil
            self.navigationController?.popToRootViewController(animated: true)
        }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {}

    func previousSongPressed(pressure: ClickWheelTouchPressure) {}

}
