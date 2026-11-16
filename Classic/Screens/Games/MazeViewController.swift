//
//  MazeViewController.swift
//  Classic
//
//  The iPod nano 4G "Maze": tilt the iPod to roll a steel ball around a
//  wooden labyrinth, collecting every glowing orb before the clock runs out.
//  Each level carves a fresh maze (recursive backtracker) with smaller cells,
//  more orbs and proportionally less time; whatever time is left over is
//  banked as a bonus.
//
//  Tilt comes from CoreMotion gravity, measured relative to however the
//  player is holding the iPod when the level starts (usually ~40° toward
//  them). Without an accelerometer (the simulator) the click wheel steers
//  the ball's heading instead and the center button starts / stops it.
//

import UIKit
import CoreMotion
import simd

class MazeViewController: PodGameViewController {

    private enum Phase { case ready, playing, levelCleared, gameOver }

    private struct Orb {
        let view: UIImageView
        let col: Int
        let row: Int
        var collected: Bool
    }

    override var gameTitle: String { "Maze" }

    // Game state
    private var phase: Phase = .ready
    private var score = 0
    private var level = 1
    private var timeLeft: CGFloat = 0
    private var levelTime: CGFloat = 1
    private var lastShownSecond = -1

    // Maze grid: `true` means a wall is standing.
    private var cols = 0
    private var rows = 0
    private var hWalls: [[Bool]] = []   // (rows + 1) lines × cols segments
    private var vWalls: [[Bool]] = []   // rows lines × (cols + 1) segments
    private var wallRects: [CGRect] = []

    // Geometry (recomputed on layout)
    private var mazeRect: CGRect = .zero
    private var cellW: CGFloat = 0
    private var cellH: CGFloat = 0
    private var wallThickness: CGFloat = 4
    private var ballRadius: CGFloat = 6
    private var orbDiameter: CGFloat = 10
    private var renderedSize: CGSize = .zero

    // Views
    private let mazeView = UIImageView()
    private let ballShadow = UIImageView()
    private let ballView = UIImageView()
    private let headingView = UIView()
    private let headingArrow = CAShapeLayer()
    private var orbs: [Orb] = []
    private let timerTrack = UIView()
    private let timerFill = UIView()
    private let timerGradient = CAGradientLayer()
    private let timeLabel = UILabel()
    private var timerIsWarning = false

    // Physics (points, seconds)
    private var ballPos: CGPoint = .zero
    private var velocity = CGVector.zero

    // Motion
    private let motion = CMMotionManager()
    private var useTilt: Bool { motion.isDeviceMotionAvailable }
    private var neutral = simd_quatd(angle: 0, axis: simd_double3(0, 0, 1))

    // Wheel fallback (no accelerometer)
    private var heading: CGFloat = 0     // radians, 0 = right, clockwise positive
    private var rolling = false

    // Housekeeping
    private var backlightClock: CGFloat = 0
    private var lastBumpTime: CFTimeInterval = 0
    private let bumpHaptic = UIImpactFeedbackGenerator(style: .light)

    // Layout
    private let timerBarHeight: CGFloat = 8
    private let timerTopInset: CGFloat = 5
    private let mazeTopInset: CGFloat = 18
    private let mazeSideInset: CGFloat = 6

    // Tuning
    private let firstCellSize: CGFloat = 46       // target cell size on level 1
    private let cellShrinkPerLevel: CGFloat = 4
    private let minCellSize: CGFloat = 21
    private let firstOrbCount = 3
    private let maxOrbCount = 12
    private let braidFraction = 0.08              // share of dead ends opened into loops
    private let secondsPerCell: CGFloat = 0.42
    private let secondsPerOrb: CGFloat = 3.5
    private let timeShrinkPerLevel: CGFloat = 0.07
    private let minTimeFactor: CGFloat = 0.55
    private let tiltAcceleration: CGFloat = 1150  // pt/s² per g of tilt
    private let tiltDeadZone: CGFloat = 0.025     // ~1.5° of slop before the ball moves
    private let rollingFriction: CGFloat = 1.4    // velocity decay per second
    private let maxSpeed: CGFloat = 520
    private let wallRestitution: CGFloat = 0.38
    private let wheelCruiseSpeed: CGFloat = 125
    private let wheelBrakeFriction: CGFloat = 9
    private let orbPoints = 100
    private let bonusPerSecond = 10
    private let backlightKeepAlive: CGFloat = 2

    // Palette: a wooden labyrinth toy — honey walls, cream floor, steel ball, blue orbs.
    private let floorTop = UIColor(red: 0.97, green: 0.94, blue: 0.87, alpha: 1)
    private let floorBottom = UIColor(red: 0.90, green: 0.85, blue: 0.75, alpha: 1)
    private let wallLight = UIColor(red: 0.84, green: 0.64, blue: 0.40, alpha: 1)
    private let wallDark = UIColor(red: 0.66, green: 0.45, blue: 0.24, alpha: 1)
    private let warningTop = UIColor(red: 1.0, green: 0.55, blue: 0.50, alpha: 1)
    private let warningBottom = UIColor(red: 0.80, green: 0.10, blue: 0.08, alpha: 1)

    // MARK: - Setup

    override func setupGame() {
        view.backgroundColor = floorBottom

        mazeView.frame = view.bounds
        view.addSubview(mazeView)

        view.addSubview(ballShadow)
        view.addSubview(ballView)

        headingArrow.fillColor = UIColor(red: 0.15, green: 0.35, blue: 0.75, alpha: 0.9).cgColor
        headingArrow.strokeColor = UIColor.white.cgColor
        headingArrow.lineWidth = 1
        headingArrow.lineJoin = .round
        headingView.layer.addSublayer(headingArrow)
        headingView.isUserInteractionEnabled = false
        view.addSubview(headingView)

        setupTimerBar()
        startMotion()
        startLevel()
    }

    override func layoutGame() {
        guard cols > 0, view.bounds.size != renderedSize else { return }
        // Keep the same maze; just re-fit it and put the ball back in its cell.
        let cell = cellAt(ballPos)
        computeGeometry()
        renderMaze()
        layoutTimerBar()
        ballPos = cellCenter(col: cell.col, row: cell.row)
        velocity = .zero
        layoutOrbs()
        placeBall()
    }

    override func refreshHUD() {
        hudScore = score
        hudLives = nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if cols > 0 { startMotion() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopMotion()
    }

    override func gameWillExit() {
        stopMotion()
        phase = .gameOver
    }

    // MARK: - Motion

    private func startMotion() {
        guard useTilt, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates()
    }

    private func stopMotion() {
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
    }

    private var currentGravity: simd_double3? {
        guard let g = motion.deviceMotion?.gravity else { return nil }
        let v = simd_double3(g.x, g.y, g.z)
        return simd_length(v) > 0.1 ? simd_normalize(v) : nil
    }

    /// Treat the current grip as "level": rotate the measured gravity onto the
    /// screen's normal so only changes from here roll the ball.
    private func calibrate() {
        guard let g = currentGravity else { return }
        let down = simd_double3(0, 0, -1)
        // Upside-down (face down) has no well-defined shortest rotation; keep the old one.
        guard simd_dot(g, down) > -0.95 else { return }
        neutral = simd_quatd(from: g, to: down)
    }

    /// Screen-space tilt in g (x right, y down), dead zone applied.
    private func tiltVector() -> CGVector {
        guard let g = currentGravity else { return .zero }
        let v = neutral.act(g)
        var t = CGVector(dx: CGFloat(v.x), dy: CGFloat(-v.y))
        let mag = hypot(t.dx, t.dy)
        guard mag > tiltDeadZone else { return .zero }
        let scale = (mag - tiltDeadZone) / mag
        t.dx *= scale
        t.dy *= scale
        return t
    }

    // MARK: - Levels

    private var cellTarget: CGFloat { max(minCellSize, firstCellSize - cellShrinkPerLevel * CGFloat(level - 1)) }
    private var orbCount: Int { min(maxOrbCount, firstOrbCount + level - 1) }

    private func startLevel() {
        let area = availableMazeArea()
        cols = max(4, Int((area.width / cellTarget).rounded()))
        rows = max(3, Int((area.height / cellTarget).rounded()))
        generateMaze()
        computeGeometry()
        renderMaze()
        layoutTimerBar()

        let timeFactor = max(minTimeFactor, 1 - timeShrinkPerLevel * CGFloat(level - 1))
        timeLeft = ((CGFloat(cols * rows) * secondsPerCell + CGFloat(orbCount) * secondsPerOrb) * timeFactor).rounded()
        timeLeft = max(timeLeft, 20)
        levelTime = timeLeft
        lastShownSecond = -1
        setTimerWarning(false)
        updateTimerBar()

        placeOrbs()
        ballPos = cellCenter(col: 0, row: 0)
        velocity = .zero
        heading = 0
        rolling = false
        placeBall()

        phase = .ready
        calibrate()
        showMessage("LEVEL \(level)", lines: [
            "Collect \(orbCount) orbs in \(Int(timeLeft)) seconds",
            useTilt ? "Hold the iPod comfortably and press center. Tilt to roll."
                    : "Wheel steers, center rolls and stops. ⏮ ⏭ turn 90°."
        ])
    }

    /// Recursive backtracker (iterative, so big mazes can't blow the stack),
    /// then a few dead ends knocked through so the maze has some loops.
    private func generateMaze() {
        hWalls = Array(repeating: Array(repeating: true, count: cols), count: rows + 1)
        vWalls = Array(repeating: Array(repeating: true, count: cols + 1), count: rows)
        var visited = Array(repeating: Array(repeating: false, count: cols), count: rows)
        var stack: [(col: Int, row: Int)] = [(0, 0)]
        visited[0][0] = true

        while let current = stack.last {
            let (c, r) = current
            var options: [(col: Int, row: Int)] = []
            if r > 0, !visited[r - 1][c] { options.append((c, r - 1)) }
            if r < rows - 1, !visited[r + 1][c] { options.append((c, r + 1)) }
            if c > 0, !visited[r][c - 1] { options.append((c - 1, r)) }
            if c < cols - 1, !visited[r][c + 1] { options.append((c + 1, r)) }
            guard let next = options.randomElement() else {
                stack.removeLast()
                continue
            }
            removeWall(between: current, and: next)
            visited[next.row][next.col] = true
            stack.append(next)
        }

        // Braid: open a share of dead ends into a neighbour.
        for r in 0..<rows {
            for c in 0..<cols where openSides(col: c, row: r).count == 1 && Double.random(in: 0..<1) < braidFraction {
                var closed: [(col: Int, row: Int)] = []
                if r > 0, hWalls[r][c] { closed.append((c, r - 1)) }
                if r < rows - 1, hWalls[r + 1][c] { closed.append((c, r + 1)) }
                if c > 0, vWalls[r][c] { closed.append((c - 1, r)) }
                if c < cols - 1, vWalls[r][c + 1] { closed.append((c + 1, r)) }
                if let n = closed.randomElement() { removeWall(between: (c, r), and: n) }
            }
        }
    }

    private func removeWall(between a: (col: Int, row: Int), and b: (col: Int, row: Int)) {
        if a.col == b.col {
            hWalls[max(a.row, b.row)][a.col] = false
        } else {
            vWalls[a.row][max(a.col, b.col)] = false
        }
    }

    /// Neighbouring cells reachable from (col, row).
    private func openSides(col c: Int, row r: Int) -> [(col: Int, row: Int)] {
        var result: [(col: Int, row: Int)] = []
        if r > 0, !hWalls[r][c] { result.append((c, r - 1)) }
        if r < rows - 1, !hWalls[r + 1][c] { result.append((c, r + 1)) }
        if c > 0, !vWalls[r][c] { result.append((c - 1, r)) }
        if c < cols - 1, !vWalls[r][c + 1] { result.append((c + 1, r)) }
        return result
    }

    /// Orbs go far from the start, preferring dead ends, spread out from each other.
    private func placeOrbs() {
        orbs.forEach { $0.view.removeFromSuperview() }
        orbs.removeAll()

        // BFS distance from the start cell.
        var dist = Array(repeating: Array(repeating: -1, count: cols), count: rows)
        var queue: [(col: Int, row: Int)] = [(0, 0)]
        dist[0][0] = 0
        var head = 0
        while head < queue.count {
            let cell = queue[head]; head += 1
            for n in openSides(col: cell.col, row: cell.row) where dist[n.row][n.col] < 0 {
                dist[n.row][n.col] = dist[cell.row][cell.col] + 1
                queue.append(n)
            }
        }

        var deadEnds: [(col: Int, row: Int)] = []
        var others: [(col: Int, row: Int)] = []
        for r in 0..<rows {
            for c in 0..<cols where dist[r][c] >= 3 {
                if openSides(col: c, row: r).count == 1 { deadEnds.append((c, r)) } else { others.append((c, r)) }
            }
        }
        let candidates = deadEnds.shuffled() + others.shuffled()

        var chosen: [(col: Int, row: Int)] = []
        for minSeparation in stride(from: 3, through: 0, by: -1) where chosen.count < orbCount {
            for cand in candidates where chosen.count < orbCount {
                let tooClose = chosen.contains { abs($0.col - cand.col) + abs($0.row - cand.row) < max(minSeparation, 1) }
                if !tooClose { chosen.append(cand) }
            }
        }

        if chosen.isEmpty, let anywhere = (0..<(cols * rows)).dropFirst().randomElement() {
            chosen.append((anywhere % cols, anywhere / cols))
        }

        let image = orbImage()
        for (i, cell) in chosen.enumerated() {
            let v = UIImageView(image: image)
            view.insertSubview(v, belowSubview: ballShadow)
            addPulse(to: v.layer, phase: Double(i) * 0.37)
            orbs.append(Orb(view: v, col: cell.col, row: cell.row, collected: false))
        }
        layoutOrbs()
    }

    private func layoutOrbs() {
        let image = orbImage()
        for orb in orbs where !orb.collected {
            orb.view.image = image
            orb.view.bounds = CGRect(origin: .zero, size: image.size)
            orb.view.center = cellCenter(col: orb.col, row: orb.row)
        }
    }

    private func addPulse(to layer: CALayer, phase: Double) {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.82
        pulse.toValue = 1.08
        pulse.duration = 0.75
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.timeOffset = phase
        pulse.isRemovedOnCompletion = false
        layer.add(pulse, forKey: "pulse")

        let glow = CABasicAnimation(keyPath: "opacity")
        glow.fromValue = 0.75
        glow.toValue = 1.0
        glow.duration = 0.75
        glow.autoreverses = true
        glow.repeatCount = .infinity
        glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.timeOffset = phase
        glow.isRemovedOnCompletion = false
        layer.add(glow, forKey: "glow")
    }

    // MARK: - Geometry

    private func availableMazeArea() -> CGRect {
        CGRect(x: mazeSideInset, y: mazeTopInset,
               width: view.bounds.width - mazeSideInset * 2,
               height: view.bounds.height - mazeTopInset - mazeSideInset)
    }

    private func computeGeometry() {
        let area = availableMazeArea()
        let base = min(area.width / CGFloat(cols), area.height / CGFloat(rows))
        wallThickness = max(4, (base * 0.17).rounded())
        // Cells stretch to fill the area exactly; walls sit centred on grid lines.
        cellW = (area.width - wallThickness) / CGFloat(cols)
        cellH = (area.height - wallThickness) / CGFloat(rows)
        mazeRect = CGRect(x: area.minX + wallThickness / 2, y: area.minY + wallThickness / 2,
                          width: cellW * CGFloat(cols), height: cellH * CGFloat(rows))
        let corridor = min(cellW, cellH) - wallThickness
        ballRadius = max(4, min(corridor * 0.36, 11))
        orbDiameter = max(7, min(corridor * 0.42, 13))
        buildWallRects()
        renderBall()
    }

    private func gridX(_ i: Int) -> CGFloat { mazeRect.minX + CGFloat(i) * cellW }
    private func gridY(_ j: Int) -> CGFloat { mazeRect.minY + CGFloat(j) * cellH }

    private func cellCenter(col: Int, row: Int) -> CGPoint {
        CGPoint(x: gridX(col) + cellW / 2, y: gridY(row) + cellH / 2)
    }

    private func cellAt(_ p: CGPoint) -> (col: Int, row: Int) {
        guard cellW > 0, cellH > 0 else { return (0, 0) }
        let c = Int(((p.x - mazeRect.minX) / cellW).rounded(.down))
        let r = Int(((p.y - mazeRect.minY) / cellH).rounded(.down))
        return (min(max(c, 0), cols - 1), min(max(r, 0), rows - 1))
    }

    /// Merge runs of wall segments into long rectangles (fewer collision tests,
    /// and no seams in the artwork). Each run overhangs by half a wall at both
    /// ends so corners are filled.
    private func buildWallRects() {
        guard cols > 0, cellW > 0 else { wallRects = []; return }
        let half = wallThickness / 2
        var rects: [CGRect] = []
        for j in 0...rows {
            var i = 0
            while i < cols {
                guard hWalls[j][i] else { i += 1; continue }
                let start = i
                while i < cols, hWalls[j][i] { i += 1 }
                rects.append(CGRect(x: gridX(start) - half, y: gridY(j) - half,
                                    width: gridX(i) - gridX(start) + wallThickness, height: wallThickness))
            }
        }
        for i in 0...cols {
            var j = 0
            while j < rows {
                guard vWalls[j][i] else { j += 1; continue }
                let start = j
                while j < rows, vWalls[j][i] { j += 1 }
                rects.append(CGRect(x: gridX(i) - half, y: gridY(start) - half,
                                    width: wallThickness, height: gridY(j) - gridY(start) + wallThickness))
            }
        }
        wallRects = rects
    }

    // MARK: - Artwork

    /// Floor and walls are baked into a single image per level.
    private func renderMaze() {
        let size = view.bounds.size
        renderedSize = size
        let bounds = CGRect(origin: .zero, size: size)
        let wallPath = CGMutablePath()
        wallRects.forEach { wallPath.addRect($0) }

        let image = UIGraphicsImageRenderer(size: size).image { rc in
            let ctx = rc.cgContext
            let space = CGColorSpaceCreateDeviceRGB()

            // Floor: soft cream gradient with faint brushed streaks and a vignette.
            if let g = CGGradient(colorsSpace: space, colors: [floorTop.cgColor, floorBottom.cgColor] as CFArray,
                                  locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            for _ in 0..<Int(size.height * 1.2) {
                let y = CGFloat.random(in: 0..<size.height)
                let x = CGFloat.random(in: -40..<size.width)
                let len = CGFloat.random(in: 30...160)
                let light = Bool.random()
                ctx.setStrokeColor(UIColor(white: light ? 1 : 0.45, alpha: light ? 0.18 : 0.035).cgColor)
                ctx.setLineWidth(0.6)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + len, y: y))
                ctx.strokePath()
            }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            if let v = CGGradient(colorsSpace: space,
                                  colors: [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.14).cgColor] as CFArray,
                                  locations: [0.55, 1]) {
                ctx.drawRadialGradient(v, startCenter: center, startRadius: 0, endCenter: center,
                                       endRadius: hypot(size.width, size.height) / 2, options: [.drawsAfterEndLocation])
            }

            // Start pad: a faint engraved ring in the first cell.
            let start = cellCenter(col: 0, row: 0)
            let ringR = ballRadius + 3
            ctx.setStrokeColor(UIColor(white: 0, alpha: 0.12).cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: start.x - ringR, y: start.y - ringR + 0.5, width: ringR * 2, height: ringR * 2))
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.6).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: CGRect(x: start.x - ringR, y: start.y - ringR + 1.5, width: ringR * 2, height: ringR * 2))

            // Walls cast a soft shadow down-right onto the floor.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 1.5, height: 2.5), blur: 3.5, color: UIColor(white: 0, alpha: 0.45).cgColor)
            ctx.addPath(wallPath)
            ctx.setFillColor(wallDark.cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            // Wood: honey gradient with grain, clipped to the walls.
            ctx.saveGState()
            ctx.addPath(wallPath)
            ctx.clip()
            if let g = CGGradient(colorsSpace: space, colors: [wallLight.cgColor, wallDark.cgColor] as CFArray,
                                  locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width * 0.3, y: size.height), options: [])
            }
            var y: CGFloat = 0
            while y < size.height {
                let wobble = CGFloat.random(in: 0.5...2.5)
                let phase = CGFloat.random(in: 0..<(.pi * 2))
                ctx.setStrokeColor(UIColor(red: 0.45, green: 0.27, blue: 0.12, alpha: CGFloat.random(in: 0.08...0.2)).cgColor)
                ctx.setLineWidth(CGFloat.random(in: 0.5...1.2))
                ctx.move(to: CGPoint(x: 0, y: y))
                var x: CGFloat = 0
                while x <= size.width {
                    ctx.addLine(to: CGPoint(x: x, y: y + sin(x / 23 + phase) * wobble))
                    x += 6
                }
                ctx.strokePath()
                y += CGFloat.random(in: 1.5...3.5)
            }

            // Bevel: highlight on top-left inner edges, shade on bottom-right.
            let outside = CGPath(rect: bounds.insetBy(dx: -20, dy: -20), transform: nil).subtracting(wallPath)
            let bevel = max(1, wallThickness * 0.22)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: bevel, height: bevel), blur: 0.8, color: UIColor(white: 1, alpha: 0.7).cgColor)
            ctx.addPath(outside)
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: -bevel, height: -bevel), blur: 0.8,
                          color: UIColor(red: 0.25, green: 0.13, blue: 0.04, alpha: 0.7).cgColor)
            ctx.addPath(outside)
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.restoreGState()
        }
        mazeView.frame = view.bounds
        mazeView.image = image
    }

    /// Polished steel ball plus a separate soft shadow that sits under it.
    private func renderBall() {
        let d = ballRadius * 2
        let rect = CGRect(x: 0, y: 0, width: d, height: d)
        ballView.image = UIGraphicsImageRenderer(size: rect.size).image { rc in
            let ctx = rc.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            ctx.addEllipse(in: rect)
            ctx.clip()
            let colors = [UIColor(white: 1, alpha: 1), UIColor(white: 0.86, alpha: 1),
                          UIColor(white: 0.52, alpha: 1), UIColor(white: 0.22, alpha: 1)].map { $0.cgColor }
            if let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 0.18, 0.62, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: d * 0.36, y: d * 0.32), startRadius: 0,
                                       endCenter: CGPoint(x: d * 0.45, y: d * 0.45), endRadius: d * 0.62,
                                       options: [.drawsAfterEndLocation])
            }
            // Warm bounce light from the wooden floor along the lower rim.
            let warm = [UIColor(red: 0.95, green: 0.82, blue: 0.6, alpha: 0.55).cgColor,
                        UIColor(red: 0.95, green: 0.82, blue: 0.6, alpha: 0).cgColor]
            if let g = CGGradient(colorsSpace: space, colors: warm as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: d * 0.62, y: d * 1.02), startRadius: 0,
                                       endCenter: CGPoint(x: d * 0.62, y: d * 1.02), endRadius: d * 0.5, options: [])
            }
            // Crisp specular.
            ctx.setFillColor(UIColor(white: 1, alpha: 0.95).cgColor)
            ctx.fillEllipse(in: CGRect(x: d * 0.24, y: d * 0.18, width: d * 0.2, height: d * 0.14))
        }
        ballView.bounds = rect

        let s = d * 1.6
        ballShadow.image = UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { rc in
            let colors = [UIColor(white: 0, alpha: 0.45).cgColor, UIColor(white: 0, alpha: 0).cgColor]
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.35, 1]) {
                let c = CGPoint(x: s / 2, y: s / 2)
                rc.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: s / 2, options: [])
            }
        }
        ballShadow.bounds = CGRect(x: 0, y: 0, width: s, height: s)

        let r = ballRadius
        let arrow = UIBezierPath()
        arrow.move(to: CGPoint(x: r + 9, y: 0))
        arrow.addLine(to: CGPoint(x: r + 3, y: -4))
        arrow.addLine(to: CGPoint(x: r + 3, y: 4))
        arrow.close()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        headingArrow.path = arrow.cgPath
        CATransaction.commit()
        headingView.isHidden = useTilt
    }

    private func orbImage() -> UIImage {
        let d = orbDiameter
        let s = (d * 2.4).rounded(.up)
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { rc in
            let ctx = rc.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let c = CGPoint(x: s / 2, y: s / 2)
            // Halo
            let halo = [UIColor(red: 0.35, green: 0.8, blue: 1, alpha: 0.6).cgColor,
                        UIColor(red: 0.35, green: 0.8, blue: 1, alpha: 0).cgColor]
            if let g = CGGradient(colorsSpace: space, colors: halo as CFArray, locations: [0.3, 1]) {
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: s / 2, options: [])
            }
            // Core
            let core = CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)
            ctx.saveGState()
            ctx.addEllipse(in: core)
            ctx.clip()
            let colors = [UIColor.white, UIColor(red: 0.55, green: 0.9, blue: 1, alpha: 1),
                          UIColor(red: 0.05, green: 0.45, blue: 0.9, alpha: 1)].map { $0.cgColor }
            if let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 0.35, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: core.minX + d * 0.4, y: core.minY + d * 0.35),
                                       startRadius: 0, endCenter: c, endRadius: d * 0.55, options: [.drawsAfterEndLocation])
            }
            ctx.restoreGState()
            ctx.setFillColor(UIColor(white: 1, alpha: 0.9).cgColor)
            ctx.fillEllipse(in: CGRect(x: core.minX + d * 0.22, y: core.minY + d * 0.14, width: d * 0.3, height: d * 0.2))
        }
    }

    // MARK: - Timer bar

    private func setupTimerBar() {
        timerTrack.backgroundColor = UIColor(white: 0.55, alpha: 1)
        timerTrack.layer.borderColor = UIColor(white: 0.35, alpha: 1).cgColor
        timerTrack.layer.borderWidth = 0.5
        timerTrack.clipsToBounds = true
        let inset = CAGradientLayer()
        inset.colors = [UIColor(white: 0.62, alpha: 1).cgColor, UIColor(white: 0.88, alpha: 1).cgColor]
        inset.name = "inset"
        timerTrack.layer.addSublayer(inset)
        view.addSubview(timerTrack)

        timerFill.clipsToBounds = true
        timerGradient.locations = [0, 0.5, 0.5, 1]
        timerFill.layer.addSublayer(timerGradient)
        timerTrack.addSubview(timerFill)

        timeLabel.font = GameStyle.font(11)
        timeLabel.textColor = UIColor(white: 0.25, alpha: 1)
        timeLabel.textAlignment = .right
        timeLabel.shadowColor = UIColor(white: 1, alpha: 0.7)
        timeLabel.shadowOffset = CGSize(width: 0, height: 1)
        view.addSubview(timeLabel)
        setTimerWarning(false)
        layoutTimerBar()
    }

    private func layoutTimerBar() {
        let labelWidth: CGFloat = 34
        timerTrack.frame = CGRect(x: mazeSideInset + 2, y: timerTopInset,
                                  width: view.bounds.width - mazeSideInset * 2 - labelWidth - 8, height: timerBarHeight)
        timerTrack.layer.cornerRadius = timerBarHeight / 2
        timerFill.layer.cornerRadius = timerBarHeight / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        timerTrack.layer.sublayers?.first { $0.name == "inset" }?.frame = timerTrack.bounds
        timerGradient.frame = timerTrack.bounds
        CATransaction.commit()
        timeLabel.frame = CGRect(x: timerTrack.frame.maxX + 2, y: timerTopInset - 3, width: labelWidth, height: timerBarHeight + 6)
        updateTimerBar()
    }

    private func updateTimerBar() {
        let fraction = min(max(timeLeft / levelTime, 0), 1)
        timerFill.frame = CGRect(x: 0, y: 0, width: timerTrack.bounds.width * fraction, height: timerTrack.bounds.height)
        let second = Int(ceil(timeLeft))
        if second != lastShownSecond {
            lastShownSecond = second
            timeLabel.text = String(format: "%d:%02d", second / 60, second % 60)
        }
    }

    private func setTimerWarning(_ warning: Bool) {
        timerIsWarning = warning
        let top = warning ? warningTop : GameStyle.selectionTop
        let bottom = warning ? warningBottom : GameStyle.selectionBottom
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        timerGradient.colors = [top.cgColor, top.withAlphaComponent(0.9).cgColor, bottom.cgColor, bottom.cgColor]
        CATransaction.commit()
        timeLabel.textColor = warning ? warningBottom : UIColor(white: 0.25, alpha: 1)
    }

    // MARK: - Frame loop

    override func update(dt: CGFloat) {
        switch phase {
        case .ready:
            // Keep tracking the grip so the level starts from wherever it's held.
            calibrate()
            return
        case .playing:
            break
        default:
            return
        }

        backlightClock += dt
        if backlightClock >= backlightKeepAlive {
            backlightClock = 0
            AppDelegate.baseVC.resetBacklightTimer()
        }

        let secondBefore = Int(ceil(timeLeft))
        timeLeft -= dt
        if timeLeft <= 5, !timerIsWarning { setTimerWarning(true) }
        if Int(ceil(timeLeft)) != secondBefore, secondBefore <= 5, timeLeft > 0 { haptic(.rigid, 0.4) }
        updateTimerBar()
        if timeLeft <= 0 {
            timeLeft = 0
            updateTimerBar()
            timeUp()
            return
        }

        movePhysics(dt: dt)
        placeBall()
        collectOrbs()
    }

    private func movePhysics(dt: CGFloat) {
        if useTilt {
            let tilt = tiltVector()
            velocity.dx += tilt.dx * tiltAcceleration * dt
            velocity.dy += tilt.dy * tiltAcceleration * dt
            let damping = exp(-rollingFriction * dt)
            velocity.dx *= damping
            velocity.dy *= damping
        } else if rolling {
            // Steer toward the wheel heading at cruising speed.
            let speed = wheelCruiseSpeed * (1 + 0.04 * CGFloat(level - 1))
            let target = CGVector(dx: cos(heading) * speed, dy: sin(heading) * speed)
            let blend = min(1, dt * 5)
            velocity.dx += (target.dx - velocity.dx) * blend
            velocity.dy += (target.dy - velocity.dy) * blend
        } else {
            let damping = exp(-wheelBrakeFriction * dt)
            velocity.dx *= damping
            velocity.dy *= damping
        }

        let speed = hypot(velocity.dx, velocity.dy)
        if speed > maxSpeed {
            velocity.dx *= maxSpeed / speed
            velocity.dy *= maxSpeed / speed
        }

        // Sub-step so the ball never travels more than a third of its radius at once.
        let distance = min(speed, maxSpeed) * dt
        let steps = min(12, max(1, Int(ceil(distance / (ballRadius * 0.35)))))
        let stepDt = dt / CGFloat(steps)
        var strongestImpact: CGFloat = 0
        for _ in 0..<steps {
            ballPos.x += velocity.dx * stepDt
            ballPos.y += velocity.dy * stepDt
            strongestImpact = max(strongestImpact, resolveWalls())
        }

        // Safety net: never leave the maze, whatever happens.
        ballPos.x = min(max(ballPos.x, mazeRect.minX + ballRadius), mazeRect.maxX - ballRadius)
        ballPos.y = min(max(ballPos.y, mazeRect.minY + ballRadius), mazeRect.maxY - ballRadius)

        let now = CACurrentMediaTime()
        if strongestImpact > 60, now - lastBumpTime > 0.08, SettingsStore.shared.clickerEnabled {
            lastBumpTime = now
            bumpHaptic.impactOccurred(intensity: min(1, strongestImpact / 350))
        }
    }

    /// Circle vs. axis-aligned rectangles. Pushes the ball out along the
    /// contact normal and reflects the normal velocity. Returns the hardest
    /// impact speed seen.
    private func resolveWalls() -> CGFloat {
        let r = ballRadius
        var impact: CGFloat = 0
        for _ in 0..<3 {
            var hitAny = false
            for rect in wallRects {
                let p = ballPos
                if p.x + r <= rect.minX || p.x - r >= rect.maxX || p.y + r <= rect.minY || p.y - r >= rect.maxY { continue }
                let q = CGPoint(x: min(max(p.x, rect.minX), rect.maxX), y: min(max(p.y, rect.minY), rect.maxY))
                let dx = p.x - q.x, dy = p.y - q.y
                let d2 = dx * dx + dy * dy
                var n: CGVector
                var penetration: CGFloat
                if d2 > 1e-8 {
                    let d = sqrt(d2)
                    guard d < r else { continue }
                    n = CGVector(dx: dx / d, dy: dy / d)
                    penetration = r - d
                } else {
                    // Centre inside the wall (only after a hitch): leave by the shortest way out.
                    let left = p.x - rect.minX, right = rect.maxX - p.x
                    let top = p.y - rect.minY, bottom = rect.maxY - p.y
                    let m = min(left, right, top, bottom)
                    if m == left { n = CGVector(dx: -1, dy: 0) }
                    else if m == right { n = CGVector(dx: 1, dy: 0) }
                    else if m == top { n = CGVector(dx: 0, dy: -1) }
                    else { n = CGVector(dx: 0, dy: 1) }
                    penetration = m + r
                }
                ballPos.x += n.dx * penetration
                ballPos.y += n.dy * penetration
                let vn = velocity.dx * n.dx + velocity.dy * n.dy
                if vn < 0 {
                    velocity.dx -= (1 + wallRestitution) * vn * n.dx
                    velocity.dy -= (1 + wallRestitution) * vn * n.dy
                    // A touch of scrub along the wall.
                    velocity.dx *= 0.985
                    velocity.dy *= 0.985
                    impact = max(impact, -vn)
                }
                hitAny = true
            }
            if !hitAny { break }
        }
        return impact
    }

    private func placeBall() {
        ballView.center = ballPos
        ballShadow.center = CGPoint(x: ballPos.x + ballRadius * 0.35, y: ballPos.y + ballRadius * 0.5)
        headingView.center = ballPos
        headingView.transform = CGAffineTransform(rotationAngle: heading)
        headingView.alpha = rolling ? 1 : 0.55
    }

    private func collectOrbs() {
        let reach = ballRadius + orbDiameter * 0.45
        for i in orbs.indices where !orbs[i].collected {
            let c = cellCenter(col: orbs[i].col, row: orbs[i].row)
            guard hypot(ballPos.x - c.x, ballPos.y - c.y) < reach else { continue }
            orbs[i].collected = true
            score += orbPoints
            hudScore = score
            haptic(.medium, 0.7)
            let v = orbs[i].view
            v.layer.removeAllAnimations()
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut], animations: {
                v.transform = CGAffineTransform(scaleX: 2.2, y: 2.2)
                v.alpha = 0
            }, completion: { _ in v.isHidden = true })
        }
        if !orbs.isEmpty, orbs.allSatisfy({ $0.collected }) { levelCleared() }
    }

    // MARK: - Flow

    private func levelCleared() {
        phase = .levelCleared
        let bonus = Int(ceil(timeLeft)) * bonusPerSecond * level
        score += bonus
        hudScore = score
        haptic(.heavy, 0.6)
        showMessage("LEVEL \(level) CLEARED", lines: ["Time bonus +\(bonus)", "Score: \(score)"])
        let clearedLevel = level
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.phase == .levelCleared, self.level == clearedLevel else { return }
            self.level += 1
            self.startLevel()
        }
    }

    private func timeUp() {
        phase = .gameOver
        velocity = .zero
        haptic(.heavy, 0.8)
        showGameOver(score: score, title: "TIME'S UP")
    }

    private func restart() {
        hideMessage()
        score = 0
        level = 1
        refreshHUD()
        startLevel()
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle, _ intensity: CGFloat) {
        guard SettingsStore.shared.clickerEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
    }

    // MARK: - Input

    override func selectPressed() {
        switch phase {
        case .ready:
            calibrate()
            hideMessage()
            backlightClock = 0
            bumpHaptic.prepare()
            phase = .playing
            if !useTilt { rolling = true; placeBall() }
        case .playing:
            if !useTilt {
                rolling.toggle()
                placeBall()
            }
        case .gameOver:
            restart()
        case .levelCleared:
            break
        }
    }

    // Wheel fallback: analog heading, one full turn of the wheel = one full turn of the ball.
    override var prefersContinuousWheelInput: Bool { !useTilt }

    override func clickWheelDidRotateContinuously(event: ClickWheelRotationEvent) {
        guard !useTilt, !isGamePaused, event.state == .changed, phase == .playing || phase == .ready else { return }
        heading += event.deltaRadians
        placeBall()
    }

    override func nextPressed() { snapHeading(by: 1) }
    override func previousPressed() { snapHeading(by: -1) }

    /// ⏭/⏮ snap the heading to the next compass direction clockwise / anticlockwise.
    private func snapHeading(by quarterTurns: Int) {
        guard !useTilt, phase == .playing || phase == .ready else { return }
        let quarter = CGFloat.pi / 2
        let current = (heading / quarter)
        let snapped = quarterTurns > 0 ? floor(current + 0.01) + 1 : ceil(current - 0.01) - 1
        heading = snapped * quarter
        placeBall()
    }
}
