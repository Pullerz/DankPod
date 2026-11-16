//
//  KlondikeViewController.swift
//  Classic
//
//  iPod Klondike (iPod classic / nano 3G): draw-one Klondike solitaire on green
//  felt. The wheel walks a blue highlight around the table — stock, waste, the
//  four foundations, then the seven tableau piles right to left, so a clockwise
//  turn loops around the screen. Center picks cards up and puts them down,
//  ⏮ narrows how much of a face-up run is picked up, ⏭ fires the top card at
//  the foundations. Scoring is Windows Solitaire's standard scoring.
//

import UIKit

class KlondikeViewController: PodGameViewController {

    // MARK: - Model

    private struct Card {
        let rank: Int   // 1 = ace … 13 = king
        let suit: Int   // 0 ♠, 1 ♥, 2 ♦, 3 ♣
        var isRed: Bool { suit == 1 || suit == 2 }
    }

    private enum Pile: Hashable {
        case stock, waste, foundation(Int), tableau(Int)
    }

    private enum Phase { case dealing, playing, autoFinishing, confirmingNewGame, celebrating, won }

    /// Cards picked up by the hand: the top `count` cards of `pile`.
    private struct Held {
        let pile: Pile
        let count: Int
    }

    override var gameTitle: String { "Klondike" }
    override var usesFrameLoop: Bool { false }
    override var canPause: Bool { false }

    // Game state
    private var phase: Phase = .dealing
    private var score = 0
    private var cards: [Card] = []          // indexed by card id, fixed for the session
    private var faceUp = [Bool](repeating: false, count: 52)
    private var stock: [Int] = []
    private var waste: [Int] = []
    private var foundations: [[Int]] = Array(repeating: [], count: 4)
    private var tableau: [[Int]] = Array(repeating: [], count: 7)
    private var held: Held?
    private var cursor = 0                  // index into cursorOrder
    private var pickCount = 1               // tableau: how many face-up cards the hand will lift
    /// Bumped on every new deal and on exit so stale delayed work bails out.
    private var generation = 0

    /// Top row left to right, then the tableau right to left: clockwise loops the table.
    private let cursorOrder: [Pile] = [.stock, .waste,
                                       .foundation(0), .foundation(1), .foundation(2), .foundation(3),
                                       .tableau(6), .tableau(5), .tableau(4), .tableau(3),
                                       .tableau(2), .tableau(1), .tableau(0)]
    private var currentPile: Pile { cursorOrder[cursor] }

    // Views — everything lives in `table` so card z-ordering never pokes through overlays.
    private let table = UIView()
    private var felt: CAGradientLayer?
    private var cardViews: [CardView] = []
    private var slotViews: [Pile: UIView] = [:]
    private let highlight = CAGradientLayer()
    private let highlightMask = CAShapeLayer()

    // Layout (computed from the real bounds)
    private var cardSize = CGSize(width: 50, height: 70)
    private var columnX: [CGFloat] = Array(repeating: 0, count: 7)
    private var topRowY: CGFloat = 0
    private var tableauY: CGFloat = 0

    // Win cascade
    private struct Bouncer {
        let image: CGImage
        var position: CGPoint
        var velocity: CGVector
    }
    private var cascadeLink: CADisplayLink?
    private var cascadeLastTime: CFTimeInterval = 0
    private var cascadeContext: CGContext?
    private var cascadeScale: CGFloat = 2
    private let cascadeView = UIView()
    private var cascadeQueue: [Int] = []
    private var bouncers: [Bouncer] = []
    private var launchTimer: CGFloat = 0

    // Tuning
    private let moveDuration: TimeInterval = 0.16
    private let cursorDuration: CFTimeInterval = 0.13
    private let heldLift: CGFloat = 5               // how far held cards float above their spot
    private let autoFinishInterval: TimeInterval = 0.09
    private let cascadeGravity: CGFloat = 1100
    private let cascadeBounce: CGFloat = 0.72
    private let cascadeLaunchInterval: CGFloat = 0.2

    // Windows Solitaire standard scoring
    private let pointsWasteToTableau = 5
    private let pointsToFoundation = 10
    private let pointsFlip = 5
    private let pointsFoundationToTableau = -15
    private let pointsRecycle = -100

    // MARK: - Setup

    override func setupGame() {
        felt = CAGradientLayer()
        felt!.type = .radial
        felt!.colors = [UIColor(red: 52/255, green: 150/255, blue: 78/255, alpha: 1).cgColor,
                        UIColor(red: 18/255, green: 96/255, blue: 44/255, alpha: 1).cgColor]
        felt!.startPoint = CGPoint(x: 0.5, y: 0.42)
        felt!.endPoint = CGPoint(x: 1.15, y: 1.25)
        table.frame = view.bounds
        table.layer.addSublayer(felt!)
        view.addSubview(table)

        for pile in [Pile.stock, .waste] + (0..<4).map { .foundation($0) } + (0..<7).map { .tableau($0) } {
            let slot = makeSlotView(for: pile)
            table.addSubview(slot)
            slotViews[pile] = slot
        }

        for suit in 0..<4 {
            for rank in 1...13 {
                cards.append(Card(rank: rank, suit: suit))
                let v = CardView(rank: rank, suit: suit)
                table.addSubview(v)
                cardViews.append(v)
            }
        }

        // Selection ring: the iPod blue gradient, masked to a rounded outline.
        highlight.colors = [GameStyle.selectionTop.cgColor, GameStyle.selectionBottom.cgColor]
        highlight.startPoint = CGPoint(x: 0.5, y: 0)
        highlight.endPoint = CGPoint(x: 0.5, y: 1)
        highlightMask.fillColor = nil
        highlightMask.strokeColor = UIColor.black.cgColor
        highlightMask.lineWidth = 3
        highlight.mask = highlightMask
        highlight.zPosition = 80
        table.layer.addSublayer(highlight)

        cascadeView.isUserInteractionEnabled = false
        cascadeView.isHidden = true
        view.addSubview(cascadeView)

        computeMetrics()
        newGame()
    }

    override func layoutGame() {
        table.frame = view.bounds
        felt?.frame = view.bounds
        cascadeView.frame = view.bounds
        computeMetrics()
        for (pile, slot) in slotViews { slot.frame = slotFrame(pile) }
        guard phase != .dealing, phase != .celebrating else { return }
        layoutCards(animated: false)
        updateHighlight(animated: false)
    }

    override func refreshHUD() {
        hudScore = score
        hudLives = nil
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCascade()
        generation += 1
    }

    override func gameWillExit() {
        stopCascade()
        generation += 1
    }

    private func computeMetrics() {
        let w = view.bounds.width, h = view.bounds.height
        let gap = max(3, floor(w * 0.012))
        var cardW = floor((w - gap * 8) / 7)
        var cardH = round(cardW * 1.38)
        // Very short screens: keep the top row from eating the tableau.
        if cardH > h * 0.235 {
            cardH = floor(h * 0.235)
            cardW = floor(cardH / 1.38)
        }
        cardSize = CGSize(width: cardW, height: cardH)
        let spare = w - cardW * 7 - gap * 6
        for i in 0..<7 { columnX[i] = floor(spare / 2 + CGFloat(i) * (cardW + gap)) }
        topRowY = gap + 1
        tableauY = round(topRowY + cardH + gap * 1.8)
    }

    private func slotFrame(_ pile: Pile) -> CGRect {
        let origin: CGPoint
        switch pile {
        case .stock: origin = CGPoint(x: columnX[0], y: topRowY)
        case .waste: origin = CGPoint(x: columnX[1], y: topRowY)
        case .foundation(let i): origin = CGPoint(x: columnX[3 + i], y: topRowY)
        case .tableau(let i): origin = CGPoint(x: columnX[i], y: tableauY)
        }
        return CGRect(origin: origin, size: cardSize)
    }

    /// Faint outlines marking where piles live when they're empty.
    private func makeSlotView(for pile: Pile) -> UIView {
        let v = SlotView()
        switch pile {
        case .stock: v.glyph = .recycle
        case .foundation: v.glyph = .ace
        default: v.glyph = .none
        }
        return v
    }

    // MARK: - Dealing

    private func newGame() {
        generation += 1
        stopCascade()
        hideMessage()
        held = nil
        score = 0
        hudScore = score
        cursor = 0
        pickCount = 1

        var deck = Array(0..<52)
        deck.shuffle()
        faceUp = Array(repeating: false, count: 52)
        stock = []
        waste = []
        foundations = Array(repeating: [], count: 4)
        tableau = Array(repeating: [], count: 7)

        // Real dealing order: a row at a time across the piles that still need cards.
        var next = 0
        var dealOrder: [Int] = []
        for row in 0..<7 {
            for col in row..<7 {
                tableau[col].append(deck[next])
                dealOrder.append(deck[next])
                next += 1
            }
        }
        stock = Array(deck[next...])

        // Everything starts face down on the stock, then flies out.
        let stockFrame = slotFrame(.stock)
        for v in cardViews {
            v.layer.removeAllAnimations()
            v.isHidden = false
            v.faceUp = false
            v.frame = stockFrame
            v.setLifted(false)
        }

        phase = .dealing
        highlight.isHidden = true
        let layout = computeLayout()
        for (i, id) in dealOrder.enumerated() {
            let v = cardViews[id]
            v.layer.zPosition = 30 + CGFloat(i) * 0.1
            UIView.animate(withDuration: 0.22, delay: 0.05 + Double(i) * 0.028,
                           options: [.curveEaseOut]) {
                v.frame = layout.frames[id]
            }
        }
        for id in stock { cardViews[id].layer.zPosition = layout.z[id] }

        let total = 0.05 + Double(dealOrder.count) * 0.028 + 0.22
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            guard let self, self.generation == gen else { return }
            for i in 0..<7 { self.flipTopIfNeeded(tableau: i, scoring: false) }
            self.phase = .playing
            self.layoutCards(animated: false)
            self.highlight.isHidden = false
            self.updateHighlight(animated: false)
        }
    }

    // MARK: - Pile access

    private func cards(in pile: Pile) -> [Int] {
        switch pile {
        case .stock: return stock
        case .waste: return waste
        case .foundation(let i): return foundations[i]
        case .tableau(let i): return tableau[i]
        }
    }

    private func setCards(_ list: [Int], in pile: Pile) {
        switch pile {
        case .stock: stock = list
        case .waste: waste = list
        case .foundation(let i): foundations[i] = list
        case .tableau(let i): tableau[i] = list
        }
    }

    /// The pile without any cards the hand is currently holding from it.
    private func baseCards(of pile: Pile) -> [Int] {
        let list = cards(in: pile)
        guard let held, held.pile == pile else { return list }
        return Array(list.dropLast(held.count))
    }

    private func heldCards() -> [Int] {
        guard let held else { return [] }
        return Array(cards(in: held.pile).suffix(held.count))
    }

    /// Length of the face-up run at the bottom of a tableau pile (all of it is movable).
    private func faceUpRun(_ i: Int) -> Int {
        var n = 0
        for id in tableau[i].reversed() where faceUp[id] { n += 1 }
        return n
    }

    // MARK: - Layout

    /// Card frames for one tableau pile, compressing the fan when it would run off the bottom.
    private func tableauGeometry(_ i: Int) -> (frames: [CGRect], landing: CGPoint, up: CGFloat) {
        let base = baseCards(of: .tableau(i))
        let extra = (held != nil && currentPile == .tableau(i)) ? held!.count : 0
        let downCount = base.filter { !faceUp[$0] }.count
        let upCount = base.count - downCount + extra
        var down = max(3, round(cardSize.height * 0.075))
        var up = round(cardSize.height * 0.25)
        let available = view.bounds.height - tableauY - cardSize.height - 3
        func needed() -> CGFloat { CGFloat(downCount) * down + CGFloat(max(upCount - 1, 0)) * up }
        if needed() > available { down = min(down, 3) }
        if needed() > available, upCount > 1 {
            up = max(7, floor((available - CGFloat(downCount) * down) / CGFloat(upCount - 1)))
        }

        var frames: [CGRect] = []
        var y = tableauY
        for id in base {
            frames.append(CGRect(x: columnX[i], y: y, width: cardSize.width, height: cardSize.height))
            y += faceUp[id] ? up : down
        }
        return (frames, CGPoint(x: columnX[i], y: y), up)
    }

    private func computeLayout() -> (frames: [CGRect], z: [CGFloat]) {
        var frames = [CGRect](repeating: .zero, count: 52)
        var z = [CGFloat](repeating: 0, count: 52)

        let topPiles: [Pile] = [.stock, .waste] + (0..<4).map { .foundation($0) }
        for pile in topPiles {
            let base = baseCards(of: pile)
            let slot = slotFrame(pile)
            for (k, id) in base.enumerated() {
                frames[id] = slot
                z[id] = CGFloat(k) * 0.01
            }
        }
        var landing: CGPoint = .zero
        var spacing = round(cardSize.height * 0.25)
        for i in 0..<7 {
            let geo = tableauGeometry(i)
            for (k, id) in tableau[i].prefix(geo.frames.count).enumerated() {
                frames[id] = geo.frames[k]
                z[id] = CGFloat(k)
            }
            if currentPile == .tableau(i) {
                landing = geo.landing
                spacing = geo.up
            }
        }

        // Held cards float over the cursor, fanned like they'd land.
        if let held {
            let target = currentPile
            var origin: CGPoint
            switch target {
            case .tableau: origin = landing
            default:
                origin = slotFrame(target).origin
                if target != held.pile { origin.y += round(cardSize.height * 0.3) }
            }
            origin.y -= heldLift
            for (k, id) in heldCards().enumerated() {
                frames[id] = CGRect(origin: CGPoint(x: origin.x, y: origin.y + CGFloat(k) * spacing),
                                    size: cardSize)
                z[id] = 100 + CGFloat(k)
            }
        }
        return (frames, z)
    }

    private func layoutCards(animated: Bool, duration: TimeInterval? = nil) {
        let layout = computeLayout()
        let heldSet = Set(heldCards())
        for (id, v) in cardViews.enumerated() {
            let target = layout.frames[id]
            let moving = abs(v.frame.minX - target.minX) + abs(v.frame.minY - target.minY) > 1
            // Cards in flight pass over everything that's staying put.
            var zp = layout.z[id]
            if moving && zp < 100 { zp += 40 }
            v.layer.zPosition = zp
            v.setLifted(heldSet.contains(id))
            guard moving || v.frame.size != target.size else { continue }
            if animated {
                UIView.animate(withDuration: duration ?? moveDuration, delay: 0,
                               options: [.curveEaseOut, .beginFromCurrentState]) {
                    v.frame = target
                }
            } else {
                v.frame = target
            }
        }
    }

    // MARK: - Highlight

    private func highlightRect() -> CGRect {
        let pile = currentPile
        guard case .tableau(let i) = pile else { return slotFrame(pile) }
        let geo = tableauGeometry(i)
        guard let last = geo.frames.last else { return slotFrame(pile) }
        if held != nil { return last }
        let start = max(0, geo.frames.count - pickCount)
        return geo.frames[start].union(last)
    }

    private func updateHighlight(animated: Bool) {
        let rect = highlightRect().insetBy(dx: -2.5, dy: -2.5)
        let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: rect.size).insetBy(dx: 1.5, dy: 1.5),
                                cornerRadius: max(4, cardSize.width * 0.1) + 1).cgPath
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(cursorDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        highlight.frame = rect
        highlightMask.frame = CGRect(origin: .zero, size: rect.size)
        highlightMask.path = path
        CATransaction.commit()
    }

    // MARK: - Rules

    private func canPlace(_ ids: [Int], on pile: Pile) -> Bool {
        guard let first = ids.first else { return false }
        let card = cards[first]
        switch pile {
        case .foundation(let i):
            guard ids.count == 1 else { return false }
            guard let top = foundations[i].last else { return card.rank == 1 }
            return cards[top].suit == card.suit && card.rank == cards[top].rank + 1
        case .tableau(let i):
            guard let top = tableau[i].last else { return card.rank == 13 }
            return faceUp[top] && cards[top].isRed != card.isRed && card.rank == cards[top].rank - 1
        default:
            return false
        }
    }

    /// The foundation a single card could go to, preferring its own suit's pile.
    private func foundationTarget(for id: Int) -> Pile? {
        let fits = (0..<4).filter { canPlace([id], on: .foundation($0)) }
        if let own = fits.first(where: { !foundations[$0].isEmpty }) { return .foundation(own) }
        return fits.first.map { .foundation($0) }
    }

    /// Moves the top `count` cards between piles, scoring Windows-style.
    private func move(count: Int, from source: Pile, to target: Pile) {
        var src = cards(in: source)
        let moving = Array(src.suffix(count))
        src.removeLast(count)
        setCards(src, in: source)
        setCards(cards(in: target) + moving, in: target)

        switch (source, target) {
        case (.waste, .tableau): addScore(pointsWasteToTableau)
        case (.waste, .foundation), (.tableau, .foundation): addScore(pointsToFoundation)
        case (.foundation, .tableau): addScore(pointsFoundationToTableau)
        default: break
        }
    }

    private func addScore(_ delta: Int) {
        score = max(0, score + delta)
        hudScore = score
    }

    /// Turns over a face-down card left on top of a tableau pile.
    private func flipTopIfNeeded(tableau i: Int, scoring: Bool = true) {
        guard let top = tableau[i].last, !faceUp[top] else { return }
        faceUp[top] = true
        if scoring { addScore(pointsFlip) }
        let v = cardViews[top]
        UIView.transition(with: v, duration: 0.24, options: [.transitionFlipFromLeft, .allowAnimatedContent]) {
            v.faceUp = true
            v.layer.displayIfNeeded()
        }
    }

    /// Common tail after any successful move: flip, relayout, check for the end.
    private func afterMove(from source: Pile) {
        layoutCards(animated: true)
        if case .tableau(let i) = source {
            let gen = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + moveDuration * 0.6) { [weak self] in
                guard let self, self.generation == gen else { return }
                self.flipTopIfNeeded(tableau: i)
                guard self.phase == .playing else { return }
                self.resetPickCount()
                self.updateHighlight(animated: true)
                self.checkForEnd()
            }
        }
        resetPickCount()
        updateHighlight(animated: true)
        checkForEnd()
    }

    private func resetPickCount() {
        if case .tableau(let i) = currentPile { pickCount = max(1, faceUpRun(i)) } else { pickCount = 1 }
    }

    // MARK: - Actions

    private func dealFromStock() {
        if let id = stock.last {
            stock.removeLast()
            waste.append(id)
            faceUp[id] = true
            let v = cardViews[id]
            UIView.transition(with: v, duration: 0.22, options: [.transitionFlipFromRight, .allowAnimatedContent]) {
                v.faceUp = true
                v.layer.displayIfNeeded()
            }
            layoutCards(animated: true, duration: 0.2)
            tick(.light)
        } else if !waste.isEmpty {
            // Turn the waste back over to make a new stock.
            stock = waste.reversed()
            waste = []
            for id in stock {
                faceUp[id] = false
                cardViews[id].faceUp = false
            }
            addScore(pointsRecycle)
            layoutCards(animated: true, duration: 0.22)
            tick(.medium)
        } else {
            tick(.light)
        }
    }

    private func pickUp() {
        let pile = currentPile
        switch pile {
        case .stock:
            dealFromStock()
            return
        case .waste, .foundation:
            guard !cards(in: pile).isEmpty else { tick(.light); return }
            held = Held(pile: pile, count: 1)
        case .tableau(let i):
            let run = faceUpRun(i)
            guard run > 0 else { tick(.light); return }
            held = Held(pile: pile, count: min(max(pickCount, 1), run))
        }
        tick(.light)
        layoutCards(animated: true, duration: 0.12)
        updateHighlight(animated: true)
    }

    private func drop() {
        guard let h = held else { return }
        let target = currentPile
        let ids = heldCards()
        held = nil
        if target != h.pile && canPlace(ids, on: target) {
            move(count: h.count, from: h.pile, to: target)
            tick(.medium)
            afterMove(from: h.pile)
        } else {
            // Same pile or illegal: the cards drift home.
            if target != h.pile { tick(.heavy) }
            layoutCards(animated: true)
            resetPickCount()
            updateHighlight(animated: true)
        }
    }

    /// ⏭: fire a single card at the foundations.
    private func sendToFoundation() {
        let source: Pile
        if let h = held {
            guard h.count == 1 else { tick(.heavy); return }
            source = h.pile
        } else {
            switch currentPile {
            case .stock, .waste: source = .waste
            case .tableau: source = currentPile
            case .foundation: tick(.heavy); return
            }
        }
        guard let id = cards(in: source).last, faceUp[id],
              let target = foundationTarget(for: id), target != source else {
            tick(.heavy)
            return
        }
        held = nil
        move(count: 1, from: source, to: target)
        tick(.medium)
        afterMove(from: source)
    }

    // MARK: - Ending

    private var foundationCount: Int { foundations.reduce(0) { $0 + $1.count } }

    private func checkForEnd() {
        if foundationCount == 52 {
            won()
            return
        }
        // Everything's exposed: finish the game for the player.
        let allUp = tableau.allSatisfy { $0.allSatisfy { faceUp[$0] } }
        if phase == .playing, stock.isEmpty, waste.isEmpty, allUp {
            phase = .autoFinishing
            highlight.isHidden = true
            scheduleAutoFinishStep()
        }
    }

    private func scheduleAutoFinishStep() {
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + autoFinishInterval + moveDuration * 0.5) { [weak self] in
            guard let self, self.generation == gen, self.phase == .autoFinishing else { return }
            self.autoFinishStep()
        }
    }

    private func autoFinishStep() {
        // Lowest card first so nothing blocks.
        let candidates = (0..<7).compactMap { i -> (Int, Int, Pile)? in
            guard let id = tableau[i].last, let target = foundationTarget(for: id) else { return nil }
            return (cards[id].rank, i, target)
        }
        guard let best = candidates.min(by: { $0.0 < $1.0 }) else {
            // Shouldn't happen once every card is face up, but never wedge the game.
            phase = .playing
            highlight.isHidden = false
            updateHighlight(animated: false)
            return
        }
        move(count: 1, from: .tableau(best.1), to: best.2)
        tick(.light)
        layoutCards(animated: true, duration: 0.14)
        if foundationCount == 52 {
            won()
        } else {
            scheduleAutoFinishStep()
        }
    }

    private func won() {
        phase = .celebrating
        held = nil
        highlight.isHidden = true
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.generation == gen, self.phase == .celebrating else { return }
            self.startCascade()
        }
    }

    private func showWin() {
        stopCascade()
        phase = .won
        showGameOver(score: score, title: "YOU WIN!")
    }

    // MARK: - Win cascade

    /// The Windows-style bouncing card cascade, painted into a persistent bitmap so
    /// every bounce leaves a trail — no views are created per frame.
    private func startCascade() {
        let size = view.bounds.size
        cascadeScale = min(view.traitCollection.displayScale, 2)
        let pw = Int(size.width * cascadeScale), ph = Int(size.height * cascadeScale)
        guard pw > 0, ph > 0,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else {
            showWin()
            return
        }
        ctx.scaleBy(x: cascadeScale, y: cascadeScale)
        cascadeContext = ctx
        cascadeView.layer.contents = nil
        cascadeView.layer.contentsScale = cascadeScale
        cascadeView.frame = view.bounds
        cascadeView.isHidden = false

        // Kings first, round-robin across the foundations, like the original.
        cascadeQueue = []
        for depth in 0..<13 {
            for f in 0..<4 {
                let pile = foundations[f]
                if depth < pile.count { cascadeQueue.append(pile[pile.count - 1 - depth]) }
            }
        }
        bouncers = []
        launchTimer = cascadeLaunchInterval

        let link = CADisplayLink(target: self, selector: #selector(cascadeTick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        cascadeLastTime = 0
        cascadeLink = link
    }

    private func stopCascade() {
        cascadeLink?.invalidate()
        cascadeLink = nil
        cascadeContext = nil
        bouncers = []
        cascadeQueue = []
        cascadeView.layer.contents = nil
        cascadeView.isHidden = true
    }

    private func cardImage(_ id: Int) -> CGImage? {
        let v = cardViews[id]
        let format = UIGraphicsImageRendererFormat()
        format.scale = cascadeScale
        let renderer = UIGraphicsImageRenderer(bounds: v.bounds, format: format)
        return renderer.image { ctx in v.layer.render(in: ctx.cgContext) }.cgImage
    }

    @objc private func cascadeTick(_ link: CADisplayLink) {
        defer { cascadeLastTime = link.timestamp }
        guard cascadeLastTime > 0, let ctx = cascadeContext else { return }
        let dt = CGFloat(min(link.timestamp - cascadeLastTime, 1.0 / 30.0))
        let size = view.bounds.size

        launchTimer += dt
        if launchTimer >= cascadeLaunchInterval, !cascadeQueue.isEmpty {
            launchTimer = 0
            let id = cascadeQueue.removeFirst()
            let v = cardViews[id]
            if let image = cardImage(id) {
                let dir: CGFloat = Bool.random() ? 1 : -1
                bouncers.append(Bouncer(image: image, position: v.frame.origin,
                                        velocity: CGVector(dx: dir * CGFloat.random(in: 70...190),
                                                           dy: CGFloat.random(in: -260 ... -40))))
            }
            v.isHidden = true
        }

        let w = cardSize.width, h = cardSize.height
        for i in bouncers.indices {
            var b = bouncers[i]
            b.velocity.dy += cascadeGravity * dt
            b.position.x += b.velocity.dx * dt
            b.position.y += b.velocity.dy * dt
            if b.position.y + h > size.height {
                b.position.y = size.height - h
                b.velocity.dy = -abs(b.velocity.dy) * cascadeBounce
            }
            bouncers[i] = b
            // Bitmap context is y-up; flip into it.
            ctx.draw(b.image, in: CGRect(x: b.position.x, y: size.height - b.position.y - h, width: w, height: h))
        }
        bouncers.removeAll { $0.position.x > size.width || $0.position.x + w < 0 }
        cascadeView.layer.contents = ctx.makeImage()

        if cascadeQueue.isEmpty && bouncers.isEmpty {
            // Keep the trail painting on screen behind the win card.
            let painting = cascadeView.layer.contents
            showWin()
            cascadeView.layer.contents = painting
            cascadeView.isHidden = false
        }
    }

    // MARK: - Haptics

    private func tick(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard SettingsStore.shared.clickerEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: style == .heavy ? 0.7 : 0.5)
    }

    // MARK: - Input

    override func wheelRotated(_ direction: RotationDirection) {
        guard phase == .playing else { return }
        let step = direction == .CLOCKWISE ? 1 : -1
        cursor = (cursor + step + cursorOrder.count) % cursorOrder.count
        resetPickCount()
        tick(.light)
        if held != nil { layoutCards(animated: true, duration: 0.13) }
        updateHighlight(animated: true)
    }

    override func selectPressed() {
        switch phase {
        case .playing:
            if held == nil { pickUp() } else { drop() }
        case .confirmingNewGame:
            newGame()
        case .celebrating:
            showWin()   // skip the cascade
        case .won:
            newGame()
        case .dealing, .autoFinishing:
            break
        }
    }

    override func nextPressed() {
        guard phase == .playing else { return }
        sendToFoundation()
    }

    /// ⏮ on a tableau pile walks the pick-up point down the face-up run, wrapping.
    override func previousPressed() {
        guard phase == .playing, held == nil, case .tableau(let i) = currentPile else { return }
        let run = faceUpRun(i)
        guard run > 1 else { return }
        pickCount = pickCount <= 1 ? run : pickCount - 1
        tick(.light)
        updateHighlight(animated: true)
    }

    /// Play/Pause doesn't pause a turn-based game; it offers a fresh deal instead.
    override func playPausePressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        switch phase {
        case .playing:
            if held != nil {
                held = nil
                layoutCards(animated: true)
                updateHighlight(animated: true)
            }
            phase = .confirmingNewGame
            showMessage("NEW GAME?", lines: ["Press center to deal again", "Press Play/Pause to keep playing"])
        case .confirmingNewGame:
            hideMessage()
            phase = .playing
        default:
            break
        }
    }
}

// MARK: - Card view

/// A single playing card, drawn with Core Graphics: compact corner index for tight
/// fans, a big pip in the middle, and a patterned blue back.
private final class CardView: UIView {

    let rank: Int
    let suit: Int
    var faceUp = false { didSet { if faceUp != oldValue { setNeedsDisplay() } } }

    private static let rankNames = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
    // U+FE0E forces the text (not emoji) presentation.
    static let suitGlyphs = ["\u{2660}\u{FE0E}", "\u{2665}\u{FE0E}", "\u{2666}\u{FE0E}", "\u{2663}\u{FE0E}"]
    private static let red = UIColor(red: 0.82, green: 0.06, blue: 0.1, alpha: 1)
    private static let black = UIColor(white: 0.08, alpha: 1)

    private var isRed: Bool { suit == 1 || suit == 2 }
    private var cornerRadius: CGFloat { max(3, bounds.width * 0.09) }

    init(rank: Int, suit: Int) {
        self.rank = rank
        self.suit = suit
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        layer.shadowColor = UIColor.black.cgColor
        setLifted(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Held cards get a deeper shadow so they read as floating.
    func setLifted(_ lifted: Bool) {
        layer.shadowOpacity = lifted ? 0.5 : 0.3
        layer.shadowRadius = lifted ? 3 : 0.8
        layer.shadowOffset = CGSize(width: 0, height: lifted ? 3 : 0.5)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = UIBezierPath(roundedRect: r, cornerRadius: cornerRadius)
        if faceUp { drawFace(ctx, path: path, rect: r) } else { drawBack(ctx, path: path, rect: r) }
    }

    private func fillGradient(_ ctx: CGContext, _ colors: [UIColor], in rect: CGRect) {
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors.map { $0.cgColor } as CFArray, locations: nil) else { return }
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY),
                               end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    }

    private func drawFace(_ ctx: CGContext, path: UIBezierPath, rect: CGRect) {
        ctx.saveGState()
        path.addClip()
        fillGradient(ctx, [.white, UIColor(white: 0.93, alpha: 1)], in: rect)
        ctx.restoreGState()
        UIColor(white: 0.55, alpha: 1).setStroke()
        path.lineWidth = 0.75
        path.stroke()

        let color = isRed ? Self.red : Self.black
        let h = bounds.height, w = bounds.width
        let indexSize = max(9, round(h * 0.2))

        // Corner index: rank top-left, suit top-right — both visible in a tight fan.
        let rankText = Self.rankNames[rank - 1] as NSString
        let rankAttrs: [NSAttributedString.Key: Any] = [
            .font: GameStyle.font(indexSize), .foregroundColor: color,
            .kern: rank == 10 ? -1.0 : 0.0
        ]
        rankText.draw(at: CGPoint(x: 2.5, y: 0.5), withAttributes: rankAttrs)

        let suitText = Self.suitGlyphs[suit] as NSString
        let smallSuit: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: indexSize * 0.92, weight: .bold), .foregroundColor: color
        ]
        let ss = suitText.size(withAttributes: smallSuit)
        suitText.draw(at: CGPoint(x: w - ss.width - 2.5, y: 1), withAttributes: smallSuit)

        if rank > 10 {
            // Court cards: a framed panel with the letter, in lieu of a portrait.
            let panel = CGRect(x: w * 0.17, y: h * 0.3, width: w * 0.66, height: h * 0.62)
            let panelPath = UIBezierPath(roundedRect: panel, cornerRadius: 2)
            (isRed ? UIColor(red: 1, green: 0.93, blue: 0.9, alpha: 1)
                   : UIColor(red: 0.91, green: 0.93, blue: 1, alpha: 1)).setFill()
            panelPath.fill()
            UIColor(red: 0.85, green: 0.68, blue: 0.2, alpha: 1).setStroke()
            panelPath.lineWidth = 1
            panelPath.stroke()
            let letterAttrs: [NSAttributedString.Key: Any] = [.font: GameStyle.font(h * 0.3), .foregroundColor: color]
            let ls = rankText.size(withAttributes: letterAttrs)
            rankText.draw(at: CGPoint(x: panel.midX - ls.width / 2, y: panel.minY + panel.height * 0.06),
                          withAttributes: letterAttrs)
            let pipAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: h * 0.17, weight: .bold), .foregroundColor: color
            ]
            let ps = suitText.size(withAttributes: pipAttrs)
            suitText.draw(at: CGPoint(x: panel.midX - ps.width / 2, y: panel.maxY - ps.height - panel.height * 0.04),
                          withAttributes: pipAttrs)
        } else {
            let pipAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: h * (rank == 1 ? 0.52 : 0.42), weight: .regular),
                .foregroundColor: color
            ]
            let ps = suitText.size(withAttributes: pipAttrs)
            suitText.draw(at: CGPoint(x: w / 2 - ps.width / 2, y: h * 0.61 - ps.height / 2), withAttributes: pipAttrs)
        }
    }

    private func drawBack(_ ctx: CGContext, path: UIBezierPath, rect: CGRect) {
        ctx.saveGState()
        path.addClip()
        fillGradient(ctx, [UIColor(red: 75/255, green: 135/255, blue: 220/255, alpha: 1),
                           UIColor(red: 22/255, green: 62/255, blue: 158/255, alpha: 1)], in: rect)

        // White inset border with a diamond lattice inside it.
        let inner = rect.insetBy(dx: 2.5, dy: 2.5)
        let innerPath = UIBezierPath(roundedRect: inner, cornerRadius: max(1.5, cornerRadius - 2))
        ctx.saveGState()
        innerPath.addClip()
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.28).cgColor)
        ctx.setLineWidth(0.7)
        let span = rect.height
        var t = rect.minX - span
        while t < rect.maxX + span {
            ctx.move(to: CGPoint(x: t, y: rect.minY))
            ctx.addLine(to: CGPoint(x: t + span, y: rect.maxY))
            ctx.move(to: CGPoint(x: t + span, y: rect.minY))
            ctx.addLine(to: CGPoint(x: t, y: rect.maxY))
            t += 5
        }
        ctx.strokePath()
        ctx.restoreGState()
        UIColor(white: 1, alpha: 0.9).setStroke()
        innerPath.lineWidth = 1.1
        innerPath.stroke()

        // Gloss across the top half.
        fillGradient(ctx, [UIColor(white: 1, alpha: 0.28), UIColor(white: 1, alpha: 0.04)],
                     in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.5))
        ctx.restoreGState()

        UIColor(white: 0, alpha: 0.4).setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }
}

// MARK: - Slot view

/// A faint rounded outline on the felt marking an empty pile.
private final class SlotView: UIView {
    enum Glyph { case none, ace, recycle }
    var glyph: Glyph = .none { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let r = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = UIBezierPath(roundedRect: r, cornerRadius: max(3, bounds.width * 0.09))
        UIColor(white: 0, alpha: 0.12).setFill()
        path.fill()
        UIColor(white: 1, alpha: 0.35).setStroke()
        path.lineWidth = 1
        path.stroke()

        let ink = UIColor(white: 1, alpha: 0.3)
        switch glyph {
        case .none:
            break
        case .ace:
            let text = "A" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: GameStyle.font(bounds.height * 0.34), .foregroundColor: ink]
            let s = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2), withAttributes: attrs)
        case .recycle:
            // A circular arrow: deal again from the waste.
            let radius = bounds.width * 0.24
            let c = CGPoint(x: bounds.midX, y: bounds.midY)
            let arc = UIBezierPath(arcCenter: c, radius: radius, startAngle: -.pi * 0.35,
                                   endAngle: .pi * 1.45, clockwise: true)
            arc.lineWidth = 2.5
            arc.lineCapStyle = .round
            ink.setStroke()
            arc.stroke()
            let end = CGPoint(x: c.x + radius * cos(-.pi * 0.35), y: c.y + radius * sin(-.pi * 0.35))
            let head = UIBezierPath()
            head.move(to: CGPoint(x: end.x + 5, y: end.y + 1))
            head.addLine(to: CGPoint(x: end.x - 1, y: end.y - 5))
            head.addLine(to: CGPoint(x: end.x - 2, y: end.y + 3))
            head.close()
            ink.setFill()
            head.fill()
        }
    }
}
