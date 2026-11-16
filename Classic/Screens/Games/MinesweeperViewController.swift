//
//  MinesweeperViewController.swift
//  Classic
//
//  Minesweeper on a 16×12 field. The first reveal is always safe and opens an
//  area (no mines in the 3×3 around it); zeros flood-fill; pressing center on a
//  number with the right count of adjacent flags "chords" its neighbours.
//  Each cleared round adds six mines to the next, up to a hard cap.
//
//  Controls:
//    Wheel           — move the cursor in reading order (wraps rows)
//    Next ⏭ / Prev ⏮ — jump the cursor down / up a row
//    Center          — reveal (or chord on a revealed number)
//    Play/Pause      — toggle a flag. Minesweeper is turn-based, so it has no
//                      use for pause; the button is re-purposed here only.
//
//  The frame loop stays on purely to drive the clock, which only runs while a
//  round is in play. Mines remaining are shown in the nav bar score slot; the
//  round and elapsed time sit in a slim strip above the field. Best times are
//  kept per mine count under this game's own UserDefaults key, and the furthest
//  round reached goes to HighScores.
//

import UIKit

class MinesweeperViewController: PodGameViewController {

    private enum Phase { case ready, playing, ending, finished }

    private struct Cell {
        var mine = false
        var adjacent = 0
        var revealed = false
        var flagged = false
    }

    /// Two layers per tile: the tile face and the glyph (number, flag or mine) on top.
    private struct Tile {
        let base: CALayer
        let glyph: CALayer
    }

    /// Pre-rendered artwork for the current cell size.
    private struct Artwork {
        var raised: CGImage?
        var revealed: CGImage?
        var exploded: CGImage?
        var numbers: [CGImage?] = []
        var flag: CGImage?
        var mine: CGImage?
        var wrongFlag: CGImage?
    }

    override var gameTitle: String { "Minesweeper" }
    override var canPause: Bool { false }

    // Game state
    private var phase: Phase = .ready
    private var cells: [Cell] = []
    private var roundNumber = 1
    private var mineCount = 0
    private var flagsPlaced = 0
    private var revealedCount = 0
    private var explodedIndex: Int?
    private var lastRoundWon = false
    private var elapsed: CGFloat = 0
    private var shownSeconds = -1
    private var cursor = 0
    private var wheelAccumulator: CGFloat = 0
    private var endGeneration = 0   // invalidates stale delayed callbacks

    // Layers & views
    private var background: CAGradientLayer?
    private let header = CAGradientLayer()
    private let headerLine = CALayer()
    private let roundLabel = UILabel()
    private let bestLabel = UILabel()
    private let timeLabel = UILabel()
    private let clockIcon = CAShapeLayer()
    private let field = CALayer()
    private let fieldFrame = CALayer()
    private let cursorLayer = CAShapeLayer()
    private var tiles: [Tile] = []
    private var art = Artwork()
    private var renderedCellSize: CGFloat = 0

    // Layout
    private let columns = 16
    private let rows = 12
    private var cellSize: CGFloat = 20
    private let headerHeight: CGFloat = 22

    // Tuning
    private let radiansPerCell: CGFloat = 0.26
    private let baseMines = 28
    private let minesPerRound = 6
    private let maxMines = 70
    private let revealRippleStep: CFTimeInterval = 0.014
    private let maxRippleDelay: CFTimeInterval = 0.35

    // Palette
    private let ink = UIColor(red: 28/255, green: 42/255, blue: 60/255, alpha: 1)
    /// Classic number colours: 1 blue, 2 green, 3 red, 4 navy, 5 maroon, 6 teal, 7 black, 8 grey.
    private let numberColors: [UIColor] = [
        .clear,
        UIColor(red: 25/255, green: 70/255, blue: 220/255, alpha: 1),
        UIColor(red: 30/255, green: 135/255, blue: 40/255, alpha: 1),
        UIColor(red: 215/255, green: 30/255, blue: 30/255, alpha: 1),
        UIColor(red: 15/255, green: 30/255, blue: 125/255, alpha: 1),
        UIColor(red: 125/255, green: 20/255, blue: 20/255, alpha: 1),
        UIColor(red: 15/255, green: 125/255, blue: 125/255, alpha: 1),
        UIColor(white: 0.08, alpha: 1),
        UIColor(white: 0.45, alpha: 1),
    ]

    private let selection = UISelectionFeedbackGenerator()

    // MARK: - Setup

    override func setupGame() {
        let bg = GameStyle.gradientLayer(UIColor(red: 214/255, green: 222/255, blue: 232/255, alpha: 1),
                                         UIColor(red: 168/255, green: 182/255, blue: 200/255, alpha: 1),
                                         frame: view.bounds)
        view.layer.insertSublayer(bg, at: 0)
        background = bg

        // Slim brushed-metal strip for the round + clock.
        header.colors = [UIColor(white: 0.98, alpha: 1).cgColor, UIColor(red: 196/255, green: 205/255, blue: 217/255, alpha: 1).cgColor]
        view.layer.addSublayer(header)
        headerLine.backgroundColor = UIColor(red: 120/255, green: 134/255, blue: 154/255, alpha: 1).cgColor
        view.layer.addSublayer(headerLine)
        for label in [roundLabel, bestLabel, timeLabel] {
            label.textColor = ink
            label.shadowColor = UIColor(white: 1, alpha: 0.8)
            label.shadowOffset = CGSize(width: 0, height: 1)
            view.addSubview(label)
        }
        roundLabel.font = GameStyle.font(12)
        bestLabel.font = GameStyle.lightFont(11)
        bestLabel.textAlignment = .center
        timeLabel.font = GameStyle.font(13)
        timeLabel.textAlignment = .right
        clockIcon.fillColor = UIColor.white.cgColor
        clockIcon.strokeColor = ink.cgColor
        clockIcon.lineWidth = 1.2
        clockIcon.lineCap = .round
        view.layer.addSublayer(clockIcon)

        fieldFrame.backgroundColor = UIColor(red: 120/255, green: 136/255, blue: 158/255, alpha: 1).cgColor
        fieldFrame.cornerRadius = 2
        fieldFrame.shadowColor = UIColor.black.cgColor
        fieldFrame.shadowOpacity = 0.3
        fieldFrame.shadowRadius = 1.5
        fieldFrame.shadowOffset = CGSize(width: 0, height: 1)
        view.layer.addSublayer(fieldFrame)
        view.layer.addSublayer(field)

        let noActions: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "opacity": NSNull()]
        tiles = (0..<(columns * rows)).map { _ in
            let base = CALayer()
            base.actions = noActions
            let glyph = CALayer()
            glyph.actions = noActions
            base.addSublayer(glyph)
            field.addSublayer(base)
            return Tile(base: base, glyph: glyph)
        }

        // Glowing iPod-blue cursor ring.
        cursorLayer.fillColor = UIColor(red: 109/255, green: 197/255, blue: 234/255, alpha: 0.18).cgColor
        cursorLayer.strokeColor = GameStyle.selectionBottom.cgColor
        cursorLayer.lineWidth = 2
        cursorLayer.shadowColor = GameStyle.selectionTop.cgColor
        cursorLayer.shadowOffset = .zero
        cursorLayer.shadowRadius = 4
        cursorLayer.shadowOpacity = 1
        field.addSublayer(cursorLayer)
        let glow = CABasicAnimation(keyPath: "shadowOpacity")
        glow.fromValue = 1
        glow.toValue = 0.35
        glow.duration = 0.8
        glow.autoreverses = true
        glow.repeatCount = .infinity
        glow.isRemovedOnCompletion = false
        glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cursorLayer.add(glow, forKey: "glow")

        selection.prepare()
        newRound(1)
    }

    override func layoutGame() {
        let b = view.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background?.frame = b
        header.frame = CGRect(x: 0, y: 0, width: b.width, height: headerHeight)
        headerLine.frame = CGRect(x: 0, y: headerHeight - 0.5, width: b.width, height: 0.5)
        roundLabel.frame = CGRect(x: 10, y: 0, width: b.width / 3, height: headerHeight)
        bestLabel.frame = CGRect(x: b.width / 3, y: 0, width: b.width / 3, height: headerHeight)
        timeLabel.frame = CGRect(x: b.width - 10 - 60, y: 0, width: 60, height: headerHeight)

        // Clock glyph sits just left of the time.
        let clockSize: CGFloat = 11
        let timeWidth = (timeLabel.text as NSString? ?? "0:00").size(withAttributes: [.font: timeLabel.font!]).width
        let clockRect = CGRect(x: timeLabel.frame.maxX - timeWidth - clockSize - 5, y: (headerHeight - clockSize) / 2,
                               width: clockSize, height: clockSize)
        clockIcon.frame = clockRect
        let clock = UIBezierPath(ovalIn: CGRect(origin: .zero, size: clockRect.size).insetBy(dx: 0.6, dy: 0.6))
        let mid = CGPoint(x: clockSize / 2, y: clockSize / 2)
        clock.move(to: mid); clock.addLine(to: CGPoint(x: mid.x, y: 2.6))
        clock.move(to: mid); clock.addLine(to: CGPoint(x: clockSize - 3, y: mid.y))
        clockIcon.path = clock.cgPath

        // Field fills the rest, square cells.
        let availH = b.height - headerHeight - 10
        cellSize = max(6, floor(min((b.width - 12) / CGFloat(columns), availH / CGFloat(rows))))
        let size = CGSize(width: cellSize * CGFloat(columns), height: cellSize * CGFloat(rows))
        field.frame = CGRect(x: round((b.width - size.width) / 2),
                             y: round(headerHeight + (b.height - headerHeight - size.height) / 2),
                             width: size.width, height: size.height)
        fieldFrame.frame = field.frame.insetBy(dx: -1.5, dy: -1.5)

        for (i, t) in tiles.enumerated() {
            t.base.frame = CGRect(x: CGFloat(i % columns) * cellSize, y: CGFloat(i / columns) * cellSize,
                                  width: cellSize, height: cellSize)
            t.glyph.frame = t.base.bounds
        }
        if renderedCellSize != cellSize {
            renderedCellSize = cellSize
            art = makeArtwork(size: cellSize)
        }
        let ring = CGRect(x: 0, y: 0, width: cellSize, height: cellSize).insetBy(dx: 0.5, dy: 0.5)
        cursorLayer.bounds = CGRect(origin: .zero, size: CGSize(width: cellSize, height: cellSize))
        cursorLayer.path = UIBezierPath(roundedRect: ring, cornerRadius: 3).cgPath
        CATransaction.commit()

        renderAllTiles()
        moveCursorLayer(animated: false)
    }

    override func refreshHUD() {
        hudScore = max(0, mineCount - flagsPlaced)
        hudLives = nil
    }

    // MARK: - Artwork

    private func image(_ size: CGFloat, _ draw: (CGContext, CGFloat) -> Void) -> CGImage? {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { draw($0.cgContext, size) }.cgImage
    }

    private func makeArtwork(size: CGFloat) -> Artwork {
        var a = Artwork()
        let space = CGColorSpaceCreateDeviceRGB()

        // Raised silver-blue tile: light top-left edge, dark bottom-right edge, soft gloss.
        a.raised = image(size) { c, s in
            let bevel = max(2, round(s * 0.11))
            if let g = CGGradient(colorsSpace: space, colors: [UIColor(red: 226/255, green: 233/255, blue: 242/255, alpha: 1).cgColor,
                                                               UIColor(red: 172/255, green: 189/255, blue: 210/255, alpha: 1).cgColor] as CFArray,
                                  locations: [0, 1]) {
                c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: s), options: [])
            }
            func poly(_ pts: [CGPoint], _ color: UIColor) {
                c.setFillColor(color.cgColor)
                c.move(to: pts[0]); pts.dropFirst().forEach { c.addLine(to: $0) }
                c.closePath(); c.fillPath()
            }
            poly([CGPoint(x: 0, y: 0), CGPoint(x: s, y: 0), CGPoint(x: s - bevel, y: bevel), CGPoint(x: bevel, y: bevel),
                  CGPoint(x: bevel, y: s - bevel), CGPoint(x: 0, y: s)], UIColor(white: 1, alpha: 0.95))
            poly([CGPoint(x: s, y: 0), CGPoint(x: s, y: s), CGPoint(x: 0, y: s), CGPoint(x: bevel, y: s - bevel),
                  CGPoint(x: s - bevel, y: s - bevel), CGPoint(x: s - bevel, y: bevel)],
                 UIColor(red: 92/255, green: 112/255, blue: 140/255, alpha: 1))
            c.setFillColor(UIColor(white: 1, alpha: 0.22).cgColor)
            c.fill(CGRect(x: bevel, y: bevel, width: s - 2 * bevel, height: (s - 2 * bevel) * 0.45))
        }

        // Revealed: flat and slightly sunken (shadowed top-left, hairline grid).
        func flat(_ fill: UIColor) -> CGImage? {
            image(size) { c, s in
                c.setFillColor(fill.cgColor)
                c.fill(CGRect(x: 0, y: 0, width: s, height: s))
                c.setFillColor(UIColor(red: 60/255, green: 78/255, blue: 104/255, alpha: 0.28).cgColor)
                c.fill(CGRect(x: 0, y: 0, width: s, height: 1.5))
                c.fill(CGRect(x: 0, y: 0, width: 1.5, height: s))
                c.setFillColor(UIColor(red: 150/255, green: 165/255, blue: 185/255, alpha: 1).cgColor)
                c.fill(CGRect(x: s - 0.5, y: 0, width: 0.5, height: s))
                c.fill(CGRect(x: 0, y: s - 0.5, width: s, height: 0.5))
            }
        }
        a.revealed = flat(UIColor(red: 232/255, green: 237/255, blue: 243/255, alpha: 1))
        a.exploded = flat(UIColor(red: 230/255, green: 60/255, blue: 55/255, alpha: 1))

        // Numbers in Helvetica Bold with a faint white emboss.
        let font = GameStyle.font(round(size * 0.66))
        a.numbers = numberColors.enumerated().map { n, color in
            guard n > 0 else { return nil }
            return image(size) { _, s in
                let str = "\(n)" as NSString
                let shadow = NSShadow()
                shadow.shadowColor = UIColor(white: 1, alpha: 0.9)
                shadow.shadowOffset = CGSize(width: 0, height: 1)
                shadow.shadowBlurRadius = 0
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .shadow: shadow]
                let t = str.size(withAttributes: attrs)
                str.draw(at: CGPoint(x: (s - t.width) / 2, y: (s - t.height) / 2), withAttributes: attrs)
            }
        }

        a.flag = image(size) { c, s in self.drawFlag(c, s) }
        a.mine = image(size) { c, s in self.drawMine(c, s) }
        a.wrongFlag = image(size) { c, s in
            self.drawMine(c, s)
            c.setStrokeColor(UIColor(red: 220/255, green: 30/255, blue: 30/255, alpha: 1).cgColor)
            c.setLineWidth(max(1.5, s * 0.1))
            c.setLineCap(.round)
            c.move(to: CGPoint(x: s * 0.22, y: s * 0.22)); c.addLine(to: CGPoint(x: s * 0.78, y: s * 0.78))
            c.move(to: CGPoint(x: s * 0.78, y: s * 0.22)); c.addLine(to: CGPoint(x: s * 0.22, y: s * 0.78))
            c.strokePath()
        }
        return a
    }

    private func drawFlag(_ c: CGContext, _ s: CGFloat) {
        let poleX = s * 0.58
        // Base
        c.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor)
        c.fill(CGRect(x: s * 0.32, y: s * 0.74, width: s * 0.44, height: max(1.5, s * 0.07)))
        c.fill(CGRect(x: s * 0.42, y: s * 0.68, width: s * 0.24, height: max(1, s * 0.07)))
        // Pole
        c.fill(CGRect(x: poleX - s * 0.035, y: s * 0.18, width: max(1, s * 0.07), height: s * 0.54))
        // Pennant with a glossy highlight
        let pennant = UIBezierPath()
        pennant.move(to: CGPoint(x: poleX, y: s * 0.16))
        pennant.addLine(to: CGPoint(x: poleX, y: s * 0.52))
        pennant.addLine(to: CGPoint(x: s * 0.2, y: s * 0.34))
        pennant.close()
        c.saveGState()
        c.addPath(pennant.cgPath)
        c.clip()
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [UIColor(red: 1, green: 110/255, blue: 100/255, alpha: 1).cgColor,
                                       UIColor(red: 210/255, green: 25/255, blue: 25/255, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: s * 0.16), end: CGPoint(x: 0, y: s * 0.52), options: [])
        }
        c.restoreGState()
    }

    private func drawMine(_ c: CGContext, _ s: CGFloat) {
        let center = CGPoint(x: s / 2, y: s / 2)
        c.setStrokeColor(UIColor(white: 0.08, alpha: 1).cgColor)
        c.setLineWidth(max(1, s * 0.08))
        c.setLineCap(.round)
        for k in 0..<8 {
            let angle = CGFloat(k) * .pi / 4
            let len = s * (k % 2 == 0 ? 0.36 : 0.3)
            c.move(to: CGPoint(x: center.x - cos(angle) * len, y: center.y - sin(angle) * len))
            c.addLine(to: CGPoint(x: center.x + cos(angle) * len, y: center.y + sin(angle) * len))
        }
        c.strokePath()
        let r = s * 0.24
        c.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
        c.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        let h = s * 0.07
        c.setFillColor(UIColor(white: 1, alpha: 0.9).cgColor)
        c.fillEllipse(in: CGRect(x: center.x - r * 0.45 - h, y: center.y - r * 0.45 - h, width: 2 * h, height: 2 * h))
    }

    // MARK: - Board

    private var totalMinesForRound: Int { min(baseMines + (roundNumber - 1) * minesPerRound, maxMines) }

    private func neighbours(_ i: Int) -> [Int] {
        let r = i / columns, c = i % columns
        var out: [Int] = []
        out.reserveCapacity(8)
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                let nr = r + dr, nc = c + dc
                if nr >= 0, nr < rows, nc >= 0, nc < columns { out.append(nr * columns + nc) }
            }
        }
        return out
    }

    private func newRound(_ number: Int) {
        endGeneration += 1
        hideMessage()
        roundNumber = number
        cells = Array(repeating: Cell(), count: columns * rows)
        mineCount = totalMinesForRound
        flagsPlaced = 0
        revealedCount = 0
        explodedIndex = nil
        elapsed = 0
        shownSeconds = -1
        wheelAccumulator = 0
        phase = .ready
        roundLabel.text = "ROUND \(roundNumber)"
        updateBestLabel()
        updateClock()
        refreshHUD()
        for t in tiles {
            t.base.removeAllAnimations()
            t.glyph.removeAllAnimations()
        }
        renderAllTiles()
        moveCursorLayer(animated: false)
    }

    /// Mines are placed on the first reveal, never in the 3×3 around it.
    private func placeMines(avoiding safe: Int) {
        let excluded = Set(neighbours(safe) + [safe])
        var candidates = (0..<cells.count).filter { !excluded.contains($0) }
        candidates.shuffle()
        mineCount = min(mineCount, candidates.count)
        for i in candidates.prefix(mineCount) { cells[i].mine = true }
        for i in cells.indices {
            cells[i].adjacent = neighbours(i).reduce(0) { $0 + (cells[$1].mine ? 1 : 0) }
        }
        refreshHUD()
    }

    /// Reveals `start`, flood-filling zeros. Returns the revealed cells with their ripple depth.
    private func floodReveal(from start: Int, depth startDepth: Int = 0) -> [(Int, Int)] {
        guard !cells[start].revealed, !cells[start].flagged else { return [] }
        var out: [(Int, Int)] = []
        var queue = [(start, startDepth)]
        cells[start].revealed = true
        var head = 0
        while head < queue.count {
            let (i, d) = queue[head]
            head += 1
            out.append((i, d))
            revealedCount += 1
            guard cells[i].adjacent == 0, !cells[i].mine else { continue }
            for n in neighbours(i) where !cells[n].revealed && !cells[n].flagged {
                cells[n].revealed = true
                queue.append((n, d + 1))
            }
        }
        return out
    }

    private func reveal(_ i: Int) {
        if cells[i].mine {
            cells[i].revealed = true
            lose(at: i)
            return
        }
        let opened = floodReveal(from: i)
        for (idx, d) in opened { render(idx, delay: min(Double(d) * revealRippleStep, maxRippleDelay)) }
        haptic(opened.count > 1 ? 0.6 : 0.35)
        checkWin()
    }

    /// Center on a satisfied number opens all its unflagged neighbours.
    private func chord(_ i: Int) {
        let around = neighbours(i)
        let flags = around.filter { cells[$0].flagged }.count
        guard cells[i].adjacent > 0, flags == cells[i].adjacent else { haptic(0.2); return }
        let targets = around.filter { !cells[$0].revealed && !cells[$0].flagged }
        guard !targets.isEmpty else { return }
        if let bad = targets.first(where: { cells[$0].mine }) {
            cells[bad].revealed = true
            lose(at: bad)
            return
        }
        var opened: [(Int, Int)] = []
        for t in targets { opened += floodReveal(from: t, depth: 1) }
        for (idx, d) in opened { render(idx, delay: min(Double(d) * revealRippleStep, maxRippleDelay)) }
        haptic(0.6)
        checkWin()
    }

    private func toggleFlag(_ i: Int) {
        guard !cells[i].revealed else { return }
        cells[i].flagged.toggle()
        flagsPlaced += cells[i].flagged ? 1 : -1
        refreshHUD()
        render(i)
        // Little drop-in for a planted flag.
        if cells[i].flagged {
            let a = CAKeyframeAnimation(keyPath: "transform.scale")
            a.values = [1.5, 0.9, 1]
            a.keyTimes = [0, 0.6, 1]
            a.duration = 0.18
            tiles[i].glyph.add(a, forKey: "plant")
        }
        haptic(0.4)
    }

    // MARK: - Win / lose

    private func checkWin() {
        guard revealedCount == cells.count - mineCount else { return }
        phase = .ending
        lastRoundWon = true
        // Plant flags on everything left.
        for i in cells.indices where cells[i].mine && !cells[i].flagged {
            cells[i].flagged = true
            render(i, delay: 0.05)
        }
        flagsPlaced = mineCount
        refreshHUD()
        let seconds = Int(elapsed)
        let previousBest = bestTime(forMines: mineCount)
        let isBest = previousBest == nil || seconds < previousBest!
        if isBest { UserDefaults.standard.set(seconds, forKey: bestKey(mineCount)) }
        HighScores.submit(roundNumber, for: scoreKey)
        hapticHeavy()
        finish(after: 0.8) { [weak self] in
            guard let self else { return }
            self.showMessage("ROUND \(self.roundNumber) CLEARED", lines: [
                "Time: \(self.format(seconds))",
                isBest ? "New Best Time!" : "Best: \(self.format(previousBest ?? seconds))",
                "Press center for round \(self.roundNumber + 1)",
            ])
        }
    }

    private func lose(at i: Int) {
        phase = .ending
        lastRoundWon = false
        explodedIndex = i
        render(i)
        hapticHeavy()
        // Mines go off in a ripple outward from the one you hit.
        let r0 = i / columns, c0 = i % columns
        for j in cells.indices where j != i {
            let dist = Double(max(abs(j / columns - r0), abs(j % columns - c0)))
            if cells[j].mine && !cells[j].flagged {
                cells[j].revealed = true
                render(j, delay: 0.1 + dist * 0.03)
            } else if cells[j].flagged && !cells[j].mine {
                render(j, delay: 0.1 + dist * 0.03)
            }
        }
        let cleared = roundNumber - 1
        // Record now so leaving during the explosion ripple can't drop it.
        HighScores.submit(cleared, for: scoreKey)
        finish(after: 1.4) { [weak self] in
            guard let self else { return }
            self.showMessage("GAME OVER", lines: [
                cleared == 1 ? "1 round cleared" : "\(cleared) rounds cleared",
                "Best: \(HighScores.best(for: self.scoreKey)) rounds",
                "Press center to play again",
            ])
        }
    }

    private func finish(after delay: TimeInterval, _ show: @escaping () -> Void) {
        let generation = endGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.endGeneration == generation, self.phase == .ending,
                  self.viewIfLoaded?.window != nil else { return }
            self.phase = .finished
            show()
        }
    }

    // MARK: - Best times

    private func bestKey(_ mines: Int) -> String { "classic.games.minesweeper.bestTime.\(mines)" }

    private func bestTime(forMines mines: Int) -> Int? {
        UserDefaults.standard.object(forKey: bestKey(mines)) as? Int
    }

    private func updateBestLabel() {
        if let best = bestTime(forMines: totalMinesForRound) {
            bestLabel.text = "\(totalMinesForRound) mines · Best \(format(best))"
        } else {
            bestLabel.text = "\(totalMinesForRound) mines"
        }
    }

    private func format(_ seconds: Int) -> String {
        let s = min(seconds, 99 * 60 + 59)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Frame loop (clock only)

    override func update(dt: CGFloat) {
        guard phase == .playing else { return }
        elapsed += dt
        updateClock()
    }

    private func updateClock() {
        let s = Int(elapsed)
        guard s != shownSeconds else { return }
        shownSeconds = s
        let oldCount = timeLabel.text?.count
        timeLabel.text = format(s)
        if oldCount != timeLabel.text?.count { layoutClockIcon() }
    }

    private func layoutClockIcon() {
        guard timeLabel.font != nil, timeLabel.frame.width > 0 else { return }
        let w = (timeLabel.text as NSString? ?? "").size(withAttributes: [.font: timeLabel.font!]).width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clockIcon.frame.origin.x = timeLabel.frame.maxX - w - clockIcon.frame.width - 5
        CATransaction.commit()
    }

    // MARK: - Rendering

    private func renderAllTiles() {
        guard !tiles.isEmpty, cells.count == tiles.count else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in tiles.indices { render(i) }
        CATransaction.commit()
    }

    /// Sets a tile's artwork, optionally cross-fading in after `delay` for the reveal ripple.
    private func render(_ i: Int, delay: CFTimeInterval? = nil) {
        let cell = cells[i]
        let t = tiles[i]
        var base = art.raised
        var glyph: CGImage?
        let lost = phase != .playing && phase != .ready && !lastRoundWon
        if cell.flagged {
            if lost && !cell.mine {
                base = art.revealed
                glyph = art.wrongFlag
            } else {
                glyph = art.flag
            }
        } else if cell.revealed {
            base = i == explodedIndex ? art.exploded : art.revealed
            glyph = cell.mine ? art.mine : (cell.adjacent > 0 ? art.numbers[cell.adjacent] : nil)
        }

        if let delay {
            let begin = t.base.convertTime(CACurrentMediaTime(), from: nil) + delay
            let fade = CABasicAnimation(keyPath: "contents")
            fade.fromValue = t.base.contents
            fade.toValue = base
            fade.duration = 0.12
            fade.beginTime = begin
            fade.fillMode = .backwards
            t.base.add(fade, forKey: "reveal")
            let pop = CABasicAnimation(keyPath: "opacity")
            pop.fromValue = 0
            pop.toValue = 1
            pop.duration = 0.14
            pop.beginTime = begin
            pop.fillMode = .backwards
            t.glyph.add(pop, forKey: "reveal")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        t.base.contents = base
        t.glyph.contents = glyph
        CATransaction.commit()
    }

    private func moveCursorLayer(animated: Bool) {
        guard cellSize > 0 else { return }
        let target = CGPoint(x: (CGFloat(cursor % columns) + 0.5) * cellSize, y: (CGFloat(cursor / columns) + 0.5) * cellSize)
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.07)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        cursorLayer.position = target
        CATransaction.commit()
    }

    // MARK: - Haptics

    private func haptic(_ intensity: CGFloat) {
        guard SettingsStore.shared.clickerEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: intensity)
    }

    private func hapticHeavy() {
        guard SettingsStore.shared.clickerEnabled else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    // MARK: - Input

    private var acceptsBoardInput: Bool { phase == .ready || phase == .playing }

    private func setCursor(_ index: Int) {
        let count = columns * rows
        let new = ((index % count) + count) % count
        guard new != cursor else { return }
        // Slide between neighbours; snap when wrapping across the field.
        let animated = abs(new % columns - cursor % columns) <= 1 && abs(new / columns - cursor / columns) <= 1
        cursor = new
        moveCursorLayer(animated: animated)
        if SettingsStore.shared.clickerEnabled { selection.selectionChanged() }
    }

    override var prefersContinuousWheelInput: Bool { true }

    override func clickWheelDidRotateContinuously(event: ClickWheelRotationEvent) {
        guard acceptsBoardInput else { wheelAccumulator = 0; return }
        guard event.state == .changed else { wheelAccumulator = 0; return }
        wheelAccumulator += event.deltaRadians
        while abs(wheelAccumulator) >= radiansPerCell {
            let dir = wheelAccumulator > 0 ? 1 : -1
            wheelAccumulator -= CGFloat(dir) * radiansPerCell
            setCursor(cursor + dir)
        }
    }

    override func nextPressed() {
        guard acceptsBoardInput else { return }
        setCursor(cursor + columns)
    }

    override func previousPressed() {
        guard acceptsBoardInput else { return }
        setCursor(cursor - columns)
    }

    override func selectPressed() {
        switch phase {
        case .ready:
            placeMines(avoiding: cursor)
            phase = .playing
            reveal(cursor)
        case .playing:
            let cell = cells[cursor]
            if cell.flagged {
                haptic(0.2)
            } else if cell.revealed {
                chord(cursor)
            } else {
                reveal(cursor)
            }
        case .ending:
            break
        case .finished:
            newRound(lastRoundWon ? roundNumber + 1 : 1)
        }
    }

    /// Play/Pause plants or lifts a flag — this game never pauses.
    override func playPausePressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, phase == .playing else { return }
        toggleFlag(cursor)
    }
}
