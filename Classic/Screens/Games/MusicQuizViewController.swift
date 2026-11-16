//
//  MusicQuizViewController.swift
//  Classic
//
//  iPod Music Quiz (5G iPod / nano 1G–2G): a random song from the library starts
//  playing from somewhere in the middle and the player picks its title from a
//  list of five before the bar drains. Faster answers score more; each of the
//  ten rounds gives a little less time than the last.
//
//  Snippets play through the application music player so the user's own queue
//  is never touched; if the system player was playing it's paused for the quiz
//  and resumed on the way out.
//

import UIKit
import MediaPlayer

class MusicQuizViewController: PodGameViewController {

    private enum Phase { case loading, unavailable, starting, asking, revealing, gameOver }

    private struct Choice {
        let title: String
        let artist: String
    }

    override var gameTitle: String { "Music Quiz" }

    // Game state
    private var phase: Phase = .loading
    private var score = 0
    private var round = 0
    private var selection = 0
    private var choices: [Choice] = []
    private var correctIndex = 0
    private var timeLimit: CGFloat = 10
    private var timeLeft: CGFloat = 10
    private var revealTimer: CGFloat = 0
    private var startTimer: CGFloat = 0
    private var playFailures = 0
    /// Bumped whenever a round starts or the quiz is left, so stale player callbacks bail out.
    private var roundToken = 0

    // Library
    private var playable: [MPMediaItem] = []
    private var titlePool: [Choice] = []            // distinct titles, for the wrong answers
    private var usedSongs: Set<MPMediaEntityPersistentID> = []

    // Playback
    private let player = MPMusicPlayerController.applicationMusicPlayer
    private var pausedSystemPlayer = false

    // Views
    private var header: CAGradientLayer?
    private let headerRule = CALayer()
    private let roundLabel = UILabel()
    private let questionLabel = UILabel()
    private let pointsLabel = UILabel()
    private let barTrack = UIView()
    private let barFill = CAGradientLayer()
    private let barShine = CAGradientLayer()
    private var barIsWarning = false
    private var eqBars: [CAGradientLayer] = []
    private var eqPhases: [(CGFloat, CGFloat, CGFloat)] = []
    private var eqLevel: CGFloat = 0                // 0…1, eases toward 1 while music plays
    private var eqTime: CGFloat = 0
    private var rows: [QuizRowView] = []
    private let dimView = UIView()

    // Layout
    private var rowHeight: CGFloat = 30
    private var eqRect = CGRect.zero

    // Tuning
    private let rounds = 10
    private let choiceCount = 5
    private let baseTime: CGFloat = 10
    private let timeStepPerRound: CGFloat = 0.5     // round 10 gives 5.5s
    private let minTime: CGFloat = 5
    private let maxPoints: CGFloat = 100
    private let revealDuration: CGFloat = 2.2
    private let startTimeout: CGFloat = 5
    private let eqBarCount = 13

    // Palette
    private let greenTop = UIColor(red: 130/255, green: 215/255, blue: 95/255, alpha: 1)
    private let greenBottom = UIColor(red: 45/255, green: 155/255, blue: 45/255, alpha: 1)
    private let redTop = UIColor(red: 240/255, green: 115/255, blue: 105/255, alpha: 1)
    private let redBottom = UIColor(red: 190/255, green: 30/255, blue: 30/255, alpha: 1)

    // MARK: - Setup

    override func setupGame() {
        view.backgroundColor = .white

        header = GameStyle.gradientLayer(.white, UIColor(white: 0.9, alpha: 1), frame: .zero)
        view.layer.addSublayer(header!)
        headerRule.backgroundColor = UIColor(white: 0.7, alpha: 1).cgColor
        view.layer.addSublayer(headerRule)

        roundLabel.font = GameStyle.font(12)
        roundLabel.textColor = UIColor(white: 0.45, alpha: 1)
        roundLabel.textAlignment = .center
        view.addSubview(roundLabel)

        questionLabel.font = GameStyle.font(17)
        questionLabel.textColor = .black
        questionLabel.textAlignment = .center
        questionLabel.adjustsFontSizeToFitWidth = true
        questionLabel.minimumScaleFactor = 0.7
        view.addSubview(questionLabel)

        for _ in 0..<eqBarCount {
            let bar = CAGradientLayer()
            bar.colors = [GameStyle.selectionTop.cgColor, GameStyle.selectionBottom.cgColor]
            bar.cornerRadius = 1.5
            bar.anchorPoint = CGPoint(x: 0.5, y: 1)
            view.layer.addSublayer(bar)
            eqBars.append(bar)
            eqPhases.append((CGFloat.random(in: 5...11), CGFloat.random(in: 0...(2 * .pi)), CGFloat.random(in: 2...4)))
        }

        // Countdown bar in the Now Playing progress-bar style.
        barTrack.backgroundColor = UIColor(white: 0.88, alpha: 1)
        barTrack.layer.borderColor = UIColor(white: 0.55, alpha: 1).cgColor
        barTrack.layer.borderWidth = 0.75
        barTrack.clipsToBounds = true
        let trackShade = GameStyle.gradientLayer(UIColor(white: 0.78, alpha: 1), UIColor(white: 0.97, alpha: 1), frame: .zero)
        trackShade.name = "shade"
        barTrack.layer.addSublayer(trackShade)
        barFill.startPoint = CGPoint(x: 0.5, y: 0)
        barFill.endPoint = CGPoint(x: 0.5, y: 1)
        barTrack.layer.addSublayer(barFill)
        barShine.colors = [UIColor(white: 1, alpha: 0.6).cgColor, UIColor(white: 1, alpha: 0.1).cgColor]
        barFill.addSublayer(barShine)
        setBarWarning(false, force: true)
        view.addSubview(barTrack)

        pointsLabel.font = GameStyle.font(13)
        pointsLabel.textColor = GameStyle.selectionBottom
        pointsLabel.textAlignment = .right
        view.addSubview(pointsLabel)

        for _ in 0..<choiceCount {
            let row = QuizRowView()
            view.addSubview(row)
            rows.append(row)
        }

        dimView.backgroundColor = UIColor(white: 0, alpha: 0.45)

        player.repeatMode = .none
        player.shuffleMode = .off

        roundLabel.text = " "
        questionLabel.text = "Loading Music…"
        layoutGame()
        checkAuthorization()
    }

    override func layoutGame() {
        let w = view.bounds.width, h = view.bounds.height
        rowHeight = min(32, max(26, floor(h / 9.5)))
        let rowsTop = h - rowHeight * CGFloat(choiceCount) - 4
        header?.frame = CGRect(x: 0, y: 0, width: w, height: rowsTop - 2)
        headerRule.frame = CGRect(x: 0, y: rowsTop - 2, width: w, height: 1)

        roundLabel.frame = CGRect(x: 12, y: 8, width: w - 24, height: 15)
        questionLabel.frame = CGRect(x: 12, y: 24, width: w - 24, height: 22)

        let barY = rowsTop - 22
        barTrack.frame = CGRect(x: 14, y: barY, width: w - 14 - 62, height: 10)
        barTrack.layer.cornerRadius = 5
        barTrack.layer.sublayers?.first { $0.name == "shade" }?.frame = barTrack.bounds
        pointsLabel.frame = CGRect(x: w - 58, y: barY - 3, width: 46, height: 16)

        eqRect = CGRect(x: 0, y: 52, width: w, height: max(10, barY - 10 - 52))
        let barW: CGFloat = 9, gap: CGFloat = 4
        let total = CGFloat(eqBarCount) * barW + CGFloat(eqBarCount - 1) * gap
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in eqBars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: barW, height: 3)
            bar.position = CGPoint(x: (w - total) / 2 + CGFloat(i) * (barW + gap) + barW / 2, y: eqRect.maxY)
        }
        CATransaction.commit()
        updateEqualizer(dt: 0)
        updateBar()

        for (i, row) in rows.enumerated() {
            row.frame = CGRect(x: 0, y: rowsTop + CGFloat(i) * rowHeight, width: w, height: rowHeight)
        }
        dimView.frame = view.bounds
    }

    override func refreshHUD() {
        hudScore = phase == .unavailable || phase == .loading ? nil : score
        hudLives = nil
    }

    // MARK: - Library

    private func checkAuthorization() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            loadLibrary()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self, self.phase == .loading else { return }
                    if status == .authorized { self.loadLibrary() } else { self.showNoAccess() }
                }
            }
        default:
            showNoAccess()
        }
    }

    private func showNoAccess() {
        phase = .unavailable
        questionLabel.text = "Music Quiz"
        showMessage("Music Quiz", lines: ["Allow access to your music library", "in Settings to play.",
                                          "Press Menu to exit"])
    }

    private func showNotEnoughSongs() {
        phase = .unavailable
        questionLabel.text = "Music Quiz"
        showMessage("Music Quiz", lines: ["Add at least 5 songs to", "your library to play Music Quiz.",
                                          "Press Menu to exit"])
    }

    private func loadLibrary() {
        phase = .loading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = MPMediaQuery.songs().items ?? []
            func named(_ item: MPMediaItem) -> Bool {
                !(item.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            }
            // Prefer local songs long enough to start mid-way; fall back if that's too strict.
            var pool = items.filter { named($0) && !$0.isCloudItem && $0.playbackDuration > 30 }
            if pool.isEmpty { pool = items.filter { named($0) && !$0.isCloudItem } }
            if pool.isEmpty { pool = items.filter(named) }

            var seen = Set<String>()
            var titles: [Choice] = []
            for item in items where named(item) {
                let title = item.title!.trimmingCharacters(in: .whitespaces)
                guard seen.insert(title.lowercased()).inserted else { continue }
                titles.append(Choice(title: title, artist: item.artist ?? "Unknown Artist"))
            }

            DispatchQueue.main.async {
                guard let self, self.phase == .loading else { return }
                self.playable = pool
                self.titlePool = titles
                if pool.isEmpty || titles.count < self.choiceCount {
                    self.showNotEnoughSongs()
                } else {
                    self.startGame()
                }
            }
        }
    }

    // MARK: - Game flow

    private func startGame() {
        hideMessage()
        score = 0
        round = 0
        playFailures = 0
        usedSongs = []
        hudScore = score
        hudLives = nil
        let system = AppDelegate.music.musicPlayer
        if !pausedSystemPlayer && system.playbackState == .playing {
            system.pause()
            pausedSystemPlayer = true
        }
        nextRound()
    }

    private func nextRound() {
        round += 1
        guard round <= rounds else {
            endGame()
            return
        }
        roundToken += 1
        player.stop()

        timeLimit = max(minTime, baseTime - timeStepPerRound * CGFloat(round - 1))
        timeLeft = timeLimit
        startTimer = 0
        setBarWarning(false)
        updateBar()

        // Pick a song we haven't used this game (repeats only once the pool runs dry).
        var fresh = playable.filter { !usedSongs.contains($0.persistentID) }
        if fresh.isEmpty {
            usedSongs = []
            fresh = playable
        }
        let song = fresh.randomElement()!
        usedSongs.insert(song.persistentID)

        let title = (song.title ?? "").trimmingCharacters(in: .whitespaces)
        let correct = Choice(title: title, artist: song.artist ?? "Unknown Artist")
        let wrong = titlePool.filter { $0.title.lowercased() != title.lowercased() }.shuffled().prefix(choiceCount - 1)
        var list = Array(wrong) + [correct]
        list.shuffle()
        choices = list
        correctIndex = list.firstIndex { $0.title == correct.title } ?? 0
        selection = 0

        for (i, row) in rows.enumerated() {
            row.configure(title: choices[i].title, artist: choices[i].artist)
            row.state = i == selection ? .selected : .normal
        }
        roundLabel.text = "Round \(round) of \(rounds)"
        questionLabel.textColor = .black
        questionLabel.text = "Listen…"
        phase = .starting

        play(song)
    }

    /// Starts the snippet from a random point in the middle of the song.
    private func play(_ song: MPMediaItem) {
        let token = roundToken
        let duration = song.playbackDuration
        let window = max(0, duration - Double(timeLimit) - revealSeconds - 4)
        let start = window > 0 ? Double.random(in: (window * 0.2)...(window * 0.8)) : 0

        player.setQueue(with: MPMediaItemCollection(items: [song]))
        player.prepareToPlay { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.roundToken == token, self.phase == .starting else { return }
                if error != nil {
                    self.playbackFailed()
                    return
                }
                self.player.currentPlaybackTime = start
                if !self.isGamePaused { self.player.play() }
                self.player.currentPlaybackTime = start
                self.playFailures = 0
                self.phase = .asking
                self.questionLabel.text = "Which song is this?"
            }
        }
    }

    private var revealSeconds: Double { Double(revealDuration) }

    /// A song that won't play gets swapped for another; a library that won't play at all ends the quiz.
    private func playbackFailed() {
        playFailures += 1
        roundToken += 1
        player.stop()
        if playFailures >= 3 {
            phase = .unavailable
            showMessage("Music Quiz", lines: ["Couldn't play songs from", "your library right now.",
                                              "Press center to try again"])
        } else {
            round -= 1
            nextRound()
        }
    }

    private func answer(_ index: Int?) {
        guard phase == .asking else { return }
        phase = .revealing
        revealTimer = revealDuration

        let correct = index == correctIndex
        for (i, row) in rows.enumerated() {
            if i == correctIndex {
                row.state = .correct
            } else if i == index {
                row.state = .wrong
            } else {
                row.state = .normal
            }
        }
        if correct {
            let points = max(1, Int(ceil(maxPoints * timeLeft / timeLimit)))
            score += points
            hudScore = score
            questionLabel.textColor = greenBottom
            questionLabel.text = "Correct! +\(points)"
            tick(.light)
        } else {
            questionLabel.textColor = redBottom
            questionLabel.text = index == nil ? "Time's Up!" : "Wrong!"
            tick(.heavy)
        }
    }

    private func endGame() {
        roundToken += 1
        player.stop()
        phase = .gameOver
        showGameOver(score: score)
    }

    private func stopAudio() {
        roundToken += 1
        player.stop()
        if pausedSystemPlayer {
            pausedSystemPlayer = false
            AppDelegate.music.musicPlayer.play()
        }
    }

    override func gameWillExit() {
        stopAudio()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopAudio()
        // Leaving: make sure a late library load or player callback can't start a round.
        phase = .gameOver
    }

    // MARK: - Pause

    override func setPaused(_ paused: Bool) {
        let was = isGamePaused
        if paused && !was && canPause && !isShowingMessage {
            view.addSubview(dimView)        // under the PAUSED label the base adds next
        }
        super.setPaused(paused)
        guard isGamePaused != was else {
            if !isGamePaused { dimView.removeFromSuperview() }
            return
        }
        if isGamePaused {
            player.pause()
        } else {
            dimView.removeFromSuperview()
            if phase == .asking || phase == .revealing { player.play() }
        }
    }

    // MARK: - Frame loop

    override func update(dt: CGFloat) {
        updateEqualizer(dt: dt)
        switch phase {
        case .starting:
            startTimer += dt
            if startTimer > startTimeout { playbackFailed() }
        case .asking:
            timeLeft = max(0, timeLeft - dt)
            updateBar()
            if timeLeft <= 0 { answer(nil) }
        case .revealing:
            revealTimer -= dt
            if revealTimer <= 0 { nextRound() }
        default:
            break
        }
    }

    private func updateBar() {
        let fraction = timeLimit > 0 ? max(0, min(1, timeLeft / timeLimit)) : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = barTrack.bounds
        barFill.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        barShine.frame = CGRect(x: 0, y: 0, width: barFill.frame.width, height: bounds.height * 0.5)
        CATransaction.commit()
        if phase == .asking || phase == .starting {
            pointsLabel.text = "+\(max(1, Int(ceil(maxPoints * fraction))))"
        }
        setBarWarning(fraction < 0.3)
    }

    private func setBarWarning(_ warning: Bool, force: Bool = false) {
        guard warning != barIsWarning || force else { return }
        barIsWarning = warning
        barFill.colors = warning ? [redTop.cgColor, redBottom.cgColor]
                                 : [GameStyle.selectionTop.cgColor, GameStyle.selectionBottom.cgColor]
        pointsLabel.textColor = warning ? redBottom : GameStyle.selectionBottom
    }

    /// A little bouncing level meter that dances while the snippet plays.
    private func updateEqualizer(dt: CGFloat) {
        let target: CGFloat = phase == .asking || phase == .revealing ? 1 : 0
        eqLevel += (target - eqLevel) * min(1, dt * 6)
        eqTime += dt
        let maxH = eqRect.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in eqBars.enumerated() {
            let (speed, phaseOffset, wobble) = eqPhases[i]
            let a = abs(sin(eqTime * speed + phaseOffset))
            let b = abs(sin(eqTime * wobble + phaseOffset * 2))
            // Middle bars run a touch taller, like a real spectrum.
            let centreBias = 1 - abs(CGFloat(i) - CGFloat(eqBarCount - 1) / 2) / CGFloat(eqBarCount) * 0.8
            let level = (0.15 + 0.85 * (a * 0.65 + b * 0.35)) * centreBias
            let h = max(3, maxH * (0.06 + 0.94 * level * eqLevel))
            bar.bounds.size.height = h
        }
        CATransaction.commit()
    }

    // MARK: - Haptics

    private func tick(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard SettingsStore.shared.clickerEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: 0.5)
    }

    // MARK: - Input

    override func wheelRotated(_ direction: RotationDirection) {
        guard phase == .starting || phase == .asking else { return }
        let next = selection + (direction == .CLOCKWISE ? 1 : -1)
        guard next >= 0, next < rows.count else { return }
        rows[selection].state = .normal
        selection = next
        rows[selection].state = .selected
        tick(.light)
    }

    override func selectPressed() {
        switch phase {
        case .asking:
            answer(selection)
        case .revealing:
            nextRound()
        case .gameOver:
            startGame()
        case .unavailable:
            hideMessage()
            phase = .loading
            questionLabel.text = "Loading Music…"
            checkAuthorization()
        case .loading, .starting:
            break
        }
    }
}

// MARK: - Row view

/// One answer row, styled like `CustomTableViewCell`: Helvetica Bold 15, iPod blue
/// gradient when selected, green/red when the answer is revealed.
private final class QuizRowView: UIView {

    enum State { case normal, selected, correct, wrong }

    private let background = CAGradientLayer()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()

    var state: State = .normal { didSet { apply() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        background.startPoint = CGPoint(x: 0.5, y: 0)
        background.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(background)

        titleLabel.font = GameStyle.font(15)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        artistLabel.font = GameStyle.lightFont(12)
        artistLabel.textAlignment = .right
        artistLabel.lineBreakMode = .byTruncatingTail
        addSubview(artistLabel)
        apply()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, artist: String) {
        titleLabel.text = title
        artistLabel.text = artist
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.frame = bounds
        CATransaction.commit()

        let left: CGFloat = 15, right: CGFloat = 12
        var titleWidth = bounds.width - left - right
        if !artistLabel.isHidden {
            let artistWidth = min(artistLabel.sizeThatFits(bounds.size).width, bounds.width * 0.4)
            artistLabel.frame = CGRect(x: bounds.width - right - artistWidth, y: 0, width: artistWidth, height: bounds.height)
            titleWidth -= artistWidth + 8
        }
        titleLabel.frame = CGRect(x: left, y: 0, width: titleWidth, height: bounds.height)
    }

    private func apply() {
        let colors: [UIColor]?
        switch state {
        case .normal: colors = nil
        case .selected: colors = [GameStyle.selectionTop, GameStyle.selectionBottom]
        case .correct: colors = [UIColor(red: 130/255, green: 215/255, blue: 95/255, alpha: 1),
                                 UIColor(red: 45/255, green: 155/255, blue: 45/255, alpha: 1)]
        case .wrong: colors = [UIColor(red: 240/255, green: 115/255, blue: 105/255, alpha: 1),
                               UIColor(red: 190/255, green: 30/255, blue: 30/255, alpha: 1)]
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.isHidden = colors == nil
        if let colors { background.colors = colors.map { $0.cgColor } }
        CATransaction.commit()
        titleLabel.textColor = colors == nil ? .black : .white
        artistLabel.textColor = colors == nil ? UIColor(white: 0.4, alpha: 1) : UIColor(white: 1, alpha: 0.9)
        // The artist is only revealed on the right answer.
        artistLabel.isHidden = state != .correct
        setNeedsLayout()
    }
}
