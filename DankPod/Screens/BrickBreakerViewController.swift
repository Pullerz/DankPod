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
    var scoreLabel: UILabel!
    var levelLabel: UILabel!
    var livesIndicators: [UIView] = []
    var pausedLabel: UILabel!
    var gameOverOverlay: UIView!
    var separator: UIView!
    var lastLayoutWidth: CGFloat = 0
    var lastLayoutHeight: CGFloat = 0
    
    // Game physics
    var ballDX: CGFloat = 0
    var ballDY: CGFloat = 0
    let initialBallSpeed: CGFloat = 3.0
    var displayLink: CADisplayLink?
    var lastTimestamp: CFTimeInterval = 0
    let targetFrameTime: CFTimeInterval = 1.0 / 60.0
    
    // Layout constants
    let infoBarHeight: CGFloat = 25.0
    let brickRows: Int = 8
    let brickColumns: Int = 8
    let brickHeight: CGFloat = 12.0
    let brickSpacing: CGFloat = 2.0
    let brickTopOffset: CGFloat = 30.0
    let paddleHeight: CGFloat = 6.0
    let paddleBottomOffset: CGFloat = 15.0
    let ballSize: CGFloat = 8.0
    
    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Brick"
        if displayLink == nil {
            lastTimestamp = 0
            displayLink = CADisplayLink(target: self, selector: #selector(gameLoop(_:)))
            displayLink?.add(to: .main, forMode: .common)
        }
        if state == .paused {
            // Resuming from pause - don't restart
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        displayLink?.invalidate()
        displayLink = nil
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard hasSetupUI else { return }
        let w = view.bounds.width
        let h = view.bounds.height
        guard w != lastLayoutWidth || h != lastLayoutHeight else { return }
        lastLayoutWidth = w
        lastLayoutHeight = h
        
        levelLabel.frame = CGRect(x: 0, y: 4, width: w, height: 18)
        for i in 0..<livesIndicators.count {
            let xPos = w - CGFloat(i + 1) * 14.0 - 10.0
            livesIndicators[i].frame = CGRect(x: xPos, y: 8, width: 8, height: 8)
        }
        separator.frame = CGRect(x: 0, y: infoBarHeight, width: w, height: 1)
        
        let paddleWidth = w * 0.2
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
    }
    
    deinit {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    func setupUI() {
        if !hasSetupUI {
            view.backgroundColor = .black
            view.clipsToBounds = true
            
            // Score label
            scoreLabel = UILabel()
            scoreLabel.frame = CGRect(x: 10, y: 4, width: 100, height: 18)
            scoreLabel.text = "Score: 0"
            scoreLabel.textColor = .white
            scoreLabel.font = UIFont(name: "Helvetica-Bold", size: 12)
            view.addSubview(scoreLabel)
            
            // Level label
            levelLabel = UILabel()
            levelLabel.frame = CGRect(x: 0, y: 4, width: view.bounds.width, height: 18)
            levelLabel.text = "Level 1"
            levelLabel.textColor = .white
            levelLabel.textAlignment = .center
            levelLabel.font = UIFont(name: "Helvetica-Bold", size: 12)
            view.addSubview(levelLabel)
            
            // Lives indicators
            for i in 0..<3 {
                let indicator = UIView()
                let xPos = view.bounds.width - CGFloat(i + 1) * 14.0 - 10.0
                indicator.frame = CGRect(x: xPos, y: 8, width: 8, height: 8)
                indicator.backgroundColor = .white
                indicator.layer.cornerRadius = 4
                view.addSubview(indicator)
                livesIndicators.append(indicator)
            }
            
            // Separator line
            separator = UIView()
            separator.backgroundColor = .gray
            view.addSubview(separator)
            
            // Create bricks
            createBricks()
            
            // Create ball
            ball = UIView()
            ball.frame = CGRect(x: 0, y: 0, width: ballSize, height: ballSize)
            ball.backgroundColor = .white
            ball.layer.cornerRadius = ballSize / 2
            view.addSubview(ball)
            
            // Create paddle
            let paddleWidth = view.bounds.width * 0.2
            paddle = UIView()
            paddle.frame = CGRect(x: 0, y: 0, width: paddleWidth, height: paddleHeight)
            paddle.backgroundColor = .white
            paddle.center.x = view.bounds.width / 2
            paddle.frame.origin.y = view.bounds.height - paddleBottomOffset - paddleHeight
            view.addSubview(paddle)
            
            // Position ball on paddle
            resetBallOnPaddle()
            
            // Paused label
            pausedLabel = UILabel()
            pausedLabel.text = "PAUSED"
            pausedLabel.textColor = .white
            pausedLabel.font = UIFont(name: "Helvetica-Bold", size: 20)
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
        
        let brickWidth = (view.bounds.width - CGFloat(brickColumns + 1) * brickSpacing) / CGFloat(brickColumns)
        
        for row in 0..<brickRows {
            for col in 0..<brickColumns {
                let brick = UIView()
                let x = brickSpacing + CGFloat(col) * (brickWidth + brickSpacing)
                let y = brickTopOffset + CGFloat(row) * (brickHeight + brickSpacing)
                brick.frame = CGRect(x: x, y: y, width: brickWidth, height: brickHeight)
                
                switch row {
                case 0, 1:
                    brick.backgroundColor = UIColor(red: 200/255.0, green: 50/255.0, blue: 50/255.0, alpha: 1.0)
                case 2, 3:
                    brick.backgroundColor = UIColor(red: 230/255.0, green: 140/255.0, blue: 30/255.0, alpha: 1.0)
                case 4, 5:
                    brick.backgroundColor = UIColor(red: 230/255.0, green: 220/255.0, blue: 50/255.0, alpha: 1.0)
                case 6, 7:
                    brick.backgroundColor = UIColor(red: 50/255.0, green: 180/255.0, blue: 50/255.0, alpha: 1.0)
                default:
                    brick.backgroundColor = .white
                }
                
                view.addSubview(brick)
                bricks.append(brick)
            }
        }
    }
    
    @objc func gameLoop(_ link: CADisplayLink) {
        guard state == .playing else {
            lastTimestamp = link.timestamp
            return
        }
        
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
        }
        let dt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        let scale = CGFloat(dt / targetFrameTime)
        
        // Move ball
        ball.center.x += ballDX * scale
        ball.center.y += ballDY * scale
        
        let playAreaTop = infoBarHeight
        
        // Wall collisions
        if ball.frame.minX <= 0 {
            ballDX = abs(ballDX)
        }
        if ball.frame.maxX >= view.bounds.width {
            ballDX = -abs(ballDX)
        }
        if ball.frame.minY <= playAreaTop {
            ballDY = abs(ballDY)
        }
        
        // Paddle collision
        if ball.frame.maxY >= paddle.frame.minY &&
           ball.frame.maxY <= paddle.frame.maxY + 4 &&
           ball.frame.maxX >= paddle.frame.minX &&
           ball.frame.minX <= paddle.frame.maxX &&
           ballDY > 0 {
            ballDY = -abs(ballDY)
            let hitPosition = (ball.center.x - paddle.frame.minX) / paddle.frame.width
            ballDX = (hitPosition - 0.5) * 5.0
        }
        
        // Brick collisions
        for brick in bricks where !brick.isHidden {
            if ball.frame.intersects(brick.frame) {
                brick.isHidden = true
                
                // Determine bounce direction
                let ballCenterX = ball.center.x
                let ballCenterY = ball.center.y
                let brickCenterX = brick.center.x
                let brickCenterY = brick.center.y
                
                let dx = ballCenterX - brickCenterX
                let dy = ballCenterY - brickCenterY
                
                if abs(dx / brick.frame.width) > abs(dy / brick.frame.height) {
                    ballDX = -ballDX
                } else {
                    ballDY = -ballDY
                }
                
                score += 10
                scoreLabel.text = "Score: \(score)"
                break
            }
        }
        
        // Ball out of bounds (below paddle)
        if ball.frame.minY >= view.bounds.height {
            lives -= 1
            updateLivesDisplay()
            if lives > 0 {
                resetBallOnPaddle()
                state = .waitingToLaunch
            } else {
                state = .gameOver
                showGameOver()
            }
        }
        
        // Level complete — all bricks hidden
        if bricks.allSatisfy({ $0.isHidden }) {
            level += 1
            levelLabel.text = "Level \(level)"
            createBricks()
            resetBallOnPaddle()
            state = .waitingToLaunch
        }
        
        // Anti-stuck: ensure ballDY has minimum magnitude
        if abs(ballDY) < 1.0 && state == .playing {
            ballDY = ballDY > 0 ? 1.5 : -1.5
        }
    }
    
    func resetBallOnPaddle() {
        ballDX = 0
        ballDY = 0
        ball.center.x = paddle.center.x
        ball.frame.origin.y = paddle.frame.origin.y - ballSize - 2
    }
    
    func updateLivesDisplay() {
        for i in 0..<livesIndicators.count {
            livesIndicators[i].isHidden = i >= lives
        }
    }
    
    func showGameOver() {
        gameOverOverlay = UIView()
        gameOverOverlay.frame = view.bounds
        gameOverOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        
        let gameOverLabel = UILabel()
        gameOverLabel.text = "GAME OVER"
        gameOverLabel.textColor = .white
        gameOverLabel.font = UIFont(name: "Helvetica-Bold", size: 20)
        gameOverLabel.textAlignment = .center
        gameOverLabel.sizeToFit()
        gameOverLabel.center = CGPoint(x: gameOverOverlay.bounds.width / 2, y: gameOverOverlay.bounds.height / 2 - 30)
        gameOverOverlay.addSubview(gameOverLabel)
        
        let scoreResultLabel = UILabel()
        scoreResultLabel.text = "Score: \(score)"
        scoreResultLabel.textColor = .white
        scoreResultLabel.font = UIFont(name: "Helvetica-Bold", size: 16)
        scoreResultLabel.textAlignment = .center
        scoreResultLabel.sizeToFit()
        scoreResultLabel.center = CGPoint(x: gameOverOverlay.bounds.width / 2, y: gameOverOverlay.bounds.height / 2 + 10)
        gameOverOverlay.addSubview(scoreResultLabel)
        
        let restartLabel = UILabel()
        restartLabel.text = "Press center to play again"
        restartLabel.textColor = .white
        restartLabel.font = UIFont(name: "Helvetica", size: 12)
        restartLabel.textAlignment = .center
        restartLabel.sizeToFit()
        restartLabel.center = CGPoint(x: gameOverOverlay.bounds.width / 2, y: gameOverOverlay.bounds.height / 2 + 40)
        gameOverOverlay.addSubview(restartLabel)
        
        view.addSubview(gameOverOverlay)
    }
    
    func resetGame() {
        gameOverOverlay?.removeFromSuperview()
        gameOverOverlay = nil
        score = 0
        lives = 3
        level = 1
        scoreLabel.text = "Score: 0"
        levelLabel.text = "Level 1"
        updateLivesDisplay()
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
        if (pressure == .NORMAL) {
            displayLink?.invalidate()
            displayLink = nil
            self.navigationController?.popViewController(animated: true)
        } else if (pressure == .FORCE) {
            displayLink?.invalidate()
            displayLink = nil
            self.navigationController?.popToRootViewController(animated: true)
        }
    }
    
    func nextSongPressed(pressure: ClickWheelTouchPressure) {
        
    }
    
    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        
    }


}
