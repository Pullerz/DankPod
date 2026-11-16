//
//  IQuizViewController.swift
//  Classic
//
//  iQuiz (iPod classic / nano 3G, 2007): pick a quiz pack, then answer ten
//  multiple-choice questions against a draining countdown bar. Faster answers
//  score more (100 × the fraction of time left, never less than 10 for a
//  correct answer) and each question gives a little less time than the last.
//
//  Four packs are bundled below; "My Music" builds its questions from the
//  user's own library (artists, albums, years and song titles).
//

import UIKit
import MediaPlayer

class IQuizViewController: PodGameViewController {

    private enum Phase { case title, list, loading, unavailable, asking, revealing, results }

    override var gameTitle: String { "iQuiz" }
    override var scoreKey: String { "iQuiz.\(currentPackName)" }
    override var canPause: Bool { phase == .asking || phase == .revealing }

    // State
    private var phase: Phase = .title
    private var listIndex = 0
    private var currentPack = 0
    private var questions: [IQuizQuestion] = []
    private var questionIndex = 0
    private var selection = 0
    private var score = 0
    private var correctCount = 0
    private var timeLimit: CGFloat = 12
    private var timeLeft: CGFloat = 12
    private var revealTimer: CGFloat = 0
    private var clock: CGFloat = 0
    /// Bumped whenever a library load should be abandoned.
    private var loadToken = 0
    private var library: [IQuizLibrarySong]?

    // Tuning
    private let questionsPerRound = 10
    private let baseTime: CGFloat = 12
    private let timeStep: CGFloat = 0.4          // question 10 gives 8.4s
    private let minTime: CGFloat = 8
    private let revealDuration: CGFloat = 1.6
    private let answerCount = 4

    private var packNames: [String] { IQuizBank.packs.map { $0.name } + [IQuizBank.myMusic] }
    private var currentPackName: String { packNames[min(currentPack, packNames.count - 1)] }
    private var isMyMusic: Bool { currentPack == IQuizBank.packs.count }

    // Title card
    private let titleView = UIView()
    private var titleBackground: CAGradientLayer?
    private let logoView = IQuizLogoView()
    private let taglineLabel = UILabel()
    private let hintLabel = UILabel()

    // Quiz list
    private let tableView = UITableView()

    // Round
    private let roundView = UIView()
    private var header: CAGradientLayer?
    private let headerRule = CALayer()
    private let roundLabel = UILabel()
    private let questionLabel = UILabel()
    private let pointsLabel = UILabel()
    private let barTrack = UIView()
    private let barFill = CAGradientLayer()
    private let barShine = CAGradientLayer()
    private var barIsWarning = false
    private var rows: [IQuizAnswerRow] = []
    private let dimView = UIView()
    private var questionArea = CGRect.zero

    // Palette
    private let greenBottom = UIColor(red: 45/255, green: 155/255, blue: 45/255, alpha: 1)
    private let redTop = UIColor(red: 240/255, green: 115/255, blue: 105/255, alpha: 1)
    private let redBottom = UIColor(red: 190/255, green: 30/255, blue: 30/255, alpha: 1)

    // MARK: - Setup

    override func setupGame() {
        view.backgroundColor = .white

        // Title card
        titleBackground = GameStyle.gradientLayer(.white, UIColor(white: 0.86, alpha: 1), frame: .zero)
        titleView.layer.addSublayer(titleBackground!)
        titleView.addSubview(logoView)
        taglineLabel.text = "Trivia for your iPod"
        taglineLabel.font = GameStyle.font(13)
        taglineLabel.textColor = UIColor(white: 0.35, alpha: 1)
        taglineLabel.textAlignment = .center
        titleView.addSubview(taglineLabel)
        hintLabel.text = "Press center to begin"
        hintLabel.font = GameStyle.lightFont(12)
        hintLabel.textColor = UIColor(white: 0.45, alpha: 1)
        hintLabel.textAlignment = .center
        titleView.addSubview(hintLabel)
        view.addSubview(titleView)

        // Quiz list
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .white
        tableView.isHidden = true
        view.addSubview(tableView)

        // Round
        roundView.backgroundColor = .white
        roundView.isHidden = true
        header = GameStyle.gradientLayer(.white, UIColor(white: 0.9, alpha: 1), frame: .zero)
        roundView.layer.addSublayer(header!)
        headerRule.backgroundColor = UIColor(white: 0.7, alpha: 1).cgColor
        roundView.layer.addSublayer(headerRule)

        roundLabel.font = GameStyle.font(12)
        roundLabel.textColor = UIColor(white: 0.45, alpha: 1)
        roundLabel.textAlignment = .center
        roundView.addSubview(roundLabel)

        questionLabel.font = GameStyle.font(16)
        questionLabel.textColor = .black
        questionLabel.textAlignment = .center
        questionLabel.numberOfLines = 0
        questionLabel.lineBreakMode = .byWordWrapping
        roundView.addSubview(questionLabel)

        // Glossy countdown bar in the Now Playing progress-bar style.
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
        roundView.addSubview(barTrack)

        pointsLabel.font = GameStyle.font(13)
        pointsLabel.textAlignment = .right
        roundView.addSubview(pointsLabel)

        for _ in 0..<answerCount {
            let row = IQuizAnswerRow()
            roundView.addSubview(row)
            rows.append(row)
        }
        view.addSubview(roundView)

        dimView.backgroundColor = UIColor(white: 0, alpha: 0.45)

        showTitle()
    }

    override func layoutGame() {
        let w = view.bounds.width, h = view.bounds.height

        // Title card
        titleView.frame = view.bounds
        titleBackground?.frame = titleView.bounds
        let logoW = min(w * 0.72, 280)
        let logoH = logoW * 0.46
        logoView.transform = .identity
        logoView.frame = CGRect(x: (w - logoW) / 2, y: max(8, h * 0.42 - logoH / 2), width: logoW, height: logoH)
        logoView.setNeedsDisplay()
        taglineLabel.frame = CGRect(x: 12, y: logoView.frame.maxY + 10, width: w - 24, height: 17)
        hintLabel.frame = CGRect(x: 12, y: min(h - 22, taglineLabel.frame.maxY + 14), width: w - 24, height: 15)

        // Quiz list
        tableView.frame = view.bounds

        // Round
        roundView.frame = view.bounds
        let rowHeight = min(30, max(24, floor(h / 9)))
        let rowsTop = h - rowHeight * CGFloat(answerCount) - 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        header?.frame = CGRect(x: 0, y: 0, width: w, height: rowsTop - 1)
        headerRule.frame = CGRect(x: 0, y: rowsTop - 1, width: w, height: 1)
        CATransaction.commit()

        roundLabel.frame = CGRect(x: 12, y: 6, width: w - 24, height: 15)
        let barY = rowsTop - 18
        barTrack.frame = CGRect(x: 14, y: barY, width: w - 14 - 62, height: 10)
        barTrack.layer.cornerRadius = 5
        barTrack.layer.sublayers?.first { $0.name == "shade" }?.frame = barTrack.bounds
        pointsLabel.frame = CGRect(x: w - 58, y: barY - 3, width: 46, height: 16)
        questionArea = CGRect(x: 14, y: 23, width: w - 28, height: max(20, barY - 6 - 23))
        layoutQuestionLabel()
        updateBar()

        for (i, row) in rows.enumerated() {
            row.frame = CGRect(x: 0, y: rowsTop + CGFloat(i) * rowHeight, width: w, height: rowHeight)
        }
        dimView.frame = view.bounds
    }

    /// Picks the biggest Helvetica Bold size (17…10pt) at which the question fits, then centres it.
    private func layoutQuestionLabel() {
        let text = questionLabel.text ?? ""
        let area = questionArea
        guard area.width > 0 else { return }
        var size: CGFloat = 17
        var fitted = CGSize.zero
        while true {
            let font = GameStyle.font(size)
            fitted = (text as NSString).boundingRect(with: CGSize(width: area.width, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin],
                                                     attributes: [.font: font], context: nil).size
            if fitted.height <= area.height || size <= 10 { break }
            size -= 1
        }
        questionLabel.font = GameStyle.font(size)
        let height = min(area.height, ceil(fitted.height))
        questionLabel.frame = CGRect(x: area.minX, y: area.midY - height / 2, width: area.width, height: height)
    }

    override func refreshHUD() {
        switch phase {
        case .asking, .revealing, .results: hudScore = score
        default: hudScore = nil
        }
        hudLives = nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if phase == .list { selectListRow() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        loadToken += 1
        if phase == .loading { phase = .unavailable }
    }

    // MARK: - Screens

    private func showTitle() {
        phase = .title
        hideMessage()
        titleView.isHidden = false
        tableView.isHidden = true
        roundView.isHidden = true
        clock = 0
        refreshHUD()
    }

    private func showList() {
        if isGamePaused { setPaused(false) }
        loadToken += 1
        phase = .list
        hideMessage()
        titleView.isHidden = true
        roundView.isHidden = true
        tableView.isHidden = false
        tableView.reloadData()
        selectListRow()
        refreshHUD()
    }

    private func selectListRow() {
        let ip = IndexPath(row: listIndex, section: 0)
        guard listIndex < tableView.numberOfRows(inSection: 0) else { return }
        tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
        tableView.scrollToRow(at: ip, at: .none, animated: false)
    }

    // MARK: - Starting a quiz

    private func startPack(_ index: Int) {
        currentPack = index
        if isMyMusic {
            phase = .loading
            showMessage("My Music", lines: ["Building questions from", "your music library…"])
            checkAuthorization()
        } else {
            let entries = IQuizBank.packs[index].entries.shuffled().prefix(questionsPerRound)
            startRound(entries.map { IQuizQuestion(entry: $0) })
        }
    }

    private func startRound(_ qs: [IQuizQuestion]) {
        hideMessage()
        questions = qs
        questionIndex = 0
        score = 0
        correctCount = 0
        titleView.isHidden = true
        tableView.isHidden = true
        roundView.isHidden = false
        phase = .asking
        refreshHUD()
        showQuestion()
    }

    private func showQuestion() {
        let q = questions[questionIndex]
        timeLimit = max(minTime, baseTime - timeStep * CGFloat(questionIndex))
        timeLeft = timeLimit
        selection = 0
        roundLabel.textColor = UIColor(white: 0.45, alpha: 1)
        roundLabel.text = "Question \(questionIndex + 1) of \(questions.count)"
        questionLabel.text = q.text
        layoutQuestionLabel()
        for (i, row) in rows.enumerated() {
            row.title = i < q.answers.count ? q.answers[i] : ""
            row.state = i == selection ? .selected : .normal
        }
        phase = .asking
        setBarWarning(false)
        updateBar()
    }

    private func points(for fraction: CGFloat) -> Int {
        max(10, Int((100 * fraction).rounded()))
    }

    private func answer(_ index: Int?) {
        guard phase == .asking else { return }
        phase = .revealing
        revealTimer = revealDuration
        let q = questions[questionIndex]
        for (i, row) in rows.enumerated() {
            if i == q.correct { row.state = .correct }
            else if i == index { row.state = .wrong }
            else { row.state = .normal }
        }
        if index == q.correct {
            let p = points(for: timeLimit > 0 ? timeLeft / timeLimit : 0)
            score += p
            correctCount += 1
            hudScore = score
            roundLabel.textColor = greenBottom
            roundLabel.text = "Correct! +\(p)"
            tick(.light)
        } else {
            roundLabel.textColor = redBottom
            roundLabel.text = index == nil ? "Time's Up!" : "Wrong!"
            tick(.heavy)
        }
    }

    private func advance() {
        questionIndex += 1
        if questionIndex < questions.count {
            showQuestion()
        } else {
            finishRound()
        }
    }

    private func finishRound() {
        phase = .results
        let isBest = HighScores.submit(score, for: scoreKey) && score > 0
        let best = HighScores.best(for: scoreKey)
        hudScore = score
        showMessage(currentPackName, lines: [
            "\(correctCount) of \(questions.count) correct",
            "Score: \(score)",
            isBest ? "New Best Score!" : "Best: \(best)",
            "Center to play again · Menu for quizzes"
        ])
    }

    // MARK: - My Music

    private func checkAuthorization() {
        let token = loadToken
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            loadLibrary()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self, self.phase == .loading, self.loadToken == token else { return }
                    if status == .authorized { self.loadLibrary() } else { self.showLibraryProblem(access: true) }
                }
            }
        default:
            showLibraryProblem(access: true)
        }
    }

    private func showLibraryProblem(access: Bool) {
        phase = .unavailable
        if access {
            showMessage("My Music", lines: ["Allow access to your music library",
                                            "in Settings to play this quiz.",
                                            "Press Menu to choose another quiz"])
        } else {
            showMessage("My Music", lines: ["Your library needs songs from at least",
                                            "four different artists for this quiz.",
                                            "Press Menu to choose another quiz"])
        }
    }

    private func loadLibrary() {
        let token = loadToken
        let cached = library
        let count = questionsPerRound
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let songs = cached ?? IQuizLibrarySong.loadAll()
            let qs = IQuizLibraryQuiz.makeQuestions(from: songs, count: count)
            DispatchQueue.main.async {
                guard let self, self.phase == .loading, self.loadToken == token else { return }
                self.library = songs
                if qs.count < 5 {
                    self.showLibraryProblem(access: false)
                } else {
                    self.startRound(qs)
                }
            }
        }
    }

    // MARK: - Frame loop

    override func update(dt: CGFloat) {
        switch phase {
        case .title:
            clock += dt
            let pulse = sin(clock * 2 * .pi / 1.6)
            let s = 1 + 0.035 * pulse
            logoView.transform = CGAffineTransform(scaleX: s, y: s)
            hintLabel.alpha = 0.55 + 0.45 * (0.5 + 0.5 * cos(clock * 2 * .pi / 1.6))
        case .asking:
            timeLeft = max(0, timeLeft - dt)
            updateBar()
            if timeLeft <= 0 { answer(nil) }
        case .revealing:
            revealTimer -= dt
            if revealTimer <= 0 { advance() }
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
        if phase == .asking { pointsLabel.text = "+\(points(for: fraction))" }
        setBarWarning(fraction < 0.3)
    }

    private func setBarWarning(_ warning: Bool, force: Bool = false) {
        guard warning != barIsWarning || force else { return }
        barIsWarning = warning
        barFill.colors = warning ? [redTop.cgColor, redBottom.cgColor]
                                 : [GameStyle.selectionTop.cgColor, GameStyle.selectionBottom.cgColor]
        pointsLabel.textColor = warning ? redBottom : GameStyle.selectionBottom
    }

    // MARK: - Pause

    override func setPaused(_ paused: Bool) {
        let was = isGamePaused
        if paused && !was && canPause && !isShowingMessage {
            view.addSubview(dimView)        // under the PAUSED label the base adds next
        }
        super.setPaused(paused)
        if !isGamePaused { dimView.removeFromSuperview() }
    }

    // MARK: - Haptics

    private func tick(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard SettingsStore.shared.clickerEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: 0.5)
    }

    // MARK: - Input

    override func wheelRotated(_ direction: RotationDirection) {
        let delta = direction == .CLOCKWISE ? 1 : -1
        switch phase {
        case .list:
            let next = listIndex + delta
            guard next >= 0, next < packNames.count else { return }
            listIndex = next
            selectListRow()
        case .asking:
            let next = selection + delta
            guard next >= 0, next < rows.count else { return }
            rows[selection].state = .normal
            selection = next
            rows[selection].state = .selected
            tick(.light)
        default:
            break
        }
    }

    override func selectPressed() {
        switch phase {
        case .title:
            showList()
        case .list:
            startPack(listIndex)
        case .asking:
            answer(selection)
        case .revealing:
            advance()
        case .results:
            startPack(currentPack)
        case .unavailable, .loading:
            break
        }
    }

    override func playPausePressed(pressure: ClickWheelTouchPressure) {
        if (phase == .title || phase == .list) && pressure == .NORMAL {
            AppDelegate.music.playPause()
        } else {
            super.playPausePressed(pressure: pressure)
        }
    }

    override func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            switch phase {
            case .loading, .unavailable, .asking, .revealing, .results:
                showList()
                return
            case .title, .list:
                break
            }
        }
        loadToken += 1
        super.menuPressed(pressure: pressure)
    }
}

// MARK: - Quiz list table

extension IQuizViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        packNames.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = packNames[indexPath.row]
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        30
    }
}

// MARK: - Questions

private struct IQuizQuestion {
    let text: String
    let answers: [String]
    let correct: Int

    /// `answers[0]` is the right one; they're shuffled for display.
    init(text: String, correctAnswer: String, wrong: [String]) {
        var all = [correctAnswer] + wrong
        all.shuffle()
        self.text = text
        self.answers = all
        self.correct = all.firstIndex(of: correctAnswer) ?? 0
    }

    init(entry: IQuizEntry) {
        self.init(text: entry.question, correctAnswer: entry.answers[0], wrong: Array(entry.answers.dropFirst()))
    }
}

private struct IQuizEntry {
    let question: String
    /// First answer is correct.
    let answers: [String]
}

private func Q(_ question: String, _ correct: String, _ w1: String, _ w2: String, _ w3: String) -> IQuizEntry {
    IQuizEntry(question: question, answers: [correct, w1, w2, w3])
}

// MARK: - My Music question generator

private struct IQuizLibrarySong {
    let title: String
    let artist: String
    let album: String?
    let year: Int?

    static func loadAll() -> [IQuizLibrarySong] {
        let items = MPMediaQuery.songs().items ?? []
        let thisYear = Calendar.current.component(.year, from: Date())
        func clean(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        return items.compactMap { item in
            guard let title = clean(item.title), let artist = clean(item.artist) else { return nil }
            var year: Int?
            if let date = item.releaseDate {
                year = Calendar.current.component(.year, from: date)
            } else if let n = item.value(forProperty: "year") as? NSNumber {
                year = n.intValue
            }
            if let y = year, !(1900...thisYear).contains(y) { year = nil }
            return IQuizLibrarySong(title: title, artist: artist, album: clean(item.albumTitle), year: year)
        }
    }
}

private enum IQuizLibraryQuiz {
    private enum Kind: CaseIterable { case whoSings, whichAlbum, whichYear, songBy }

    static func makeQuestions(from songs: [IQuizLibrarySong], count: Int) -> [IQuizQuestion] {
        func key(_ s: String) -> String { s.lowercased() }

        var artistNames: [String: String] = [:]          // key → display
        var albumNames: [String: String] = [:]
        var titleNames: [String: String] = [:]
        var artistsByTitle: [String: Set<String>] = [:]
        var albumsByTitle: [String: Set<String>] = [:]
        var yearsByTitle: [String: Set<Int>] = [:]
        for s in songs {
            let t = key(s.title), a = key(s.artist)
            artistNames[a] = artistNames[a] ?? s.artist
            titleNames[t] = titleNames[t] ?? s.title
            artistsByTitle[t, default: []].insert(a)
            if let album = s.album {
                let k = key(album)
                albumNames[k] = albumNames[k] ?? album
                albumsByTitle[t, default: []].insert(k)
            }
            if let y = s.year { yearsByTitle[t, default: []].insert(y) }
        }
        guard artistNames.count >= 4 else { return [] }

        let artistKeys = Array(artistNames.keys)
        let albumKeys = Array(albumNames.keys)
        let titleKeys = Array(titleNames.keys)
        let thisYear = Calendar.current.component(.year, from: Date())

        /// Up to `n` random elements of `pool` passing `allowed`, without scanning a huge library every time.
        func pick(_ n: Int, from pool: [String], where allowed: (String) -> Bool) -> [String]? {
            var out: [String] = []
            var seen = Set<String>()
            for _ in 0..<min(pool.count * 2, 400) {
                guard let k = pool.randomElement(), !seen.contains(k) else { continue }
                seen.insert(k)
                if allowed(k) { out.append(k) }
                if out.count == n { return out }
            }
            // Small libraries: fall back to an exhaustive pass.
            for k in pool.shuffled() where !seen.contains(k) && allowed(k) {
                out.append(k)
                if out.count == n { return out }
            }
            return nil
        }

        func make(_ kind: Kind, _ s: IQuizLibrarySong) -> IQuizQuestion? {
            let t = key(s.title)
            switch kind {
            case .whoSings:
                let singers = artistsByTitle[t] ?? []
                guard let wrong = pick(3, from: artistKeys, where: { !singers.contains($0) }) else { return nil }
                return IQuizQuestion(text: "Who sings ‘\(s.title)’?", correctAnswer: s.artist,
                                     wrong: wrong.map { artistNames[$0]! })
            case .whichAlbum:
                guard let album = s.album else { return nil }
                let albums = albumsByTitle[t] ?? []
                guard let wrong = pick(3, from: albumKeys, where: { !albums.contains($0) }) else { return nil }
                return IQuizQuestion(text: "Which album is ‘\(s.title)’ on?", correctAnswer: album,
                                     wrong: wrong.map { albumNames[$0]! })
            case .whichYear:
                guard let year = s.year, let years = yearsByTitle[t], years.count == 1 else { return nil }
                let candidates = (1...8).flatMap { [year - $0, year + $0] }
                    .filter { $0 >= 1900 && $0 <= thisYear }
                    .shuffled()
                guard candidates.count >= 3 else { return nil }
                return IQuizQuestion(text: "Which year was ‘\(s.title)’ released?", correctAnswer: String(year),
                                     wrong: candidates.prefix(3).map(String.init))
            case .songBy:
                let a = key(s.artist)
                guard let wrong = pick(3, from: titleKeys, where: { !(artistsByTitle[$0]?.contains(a) ?? false) })
                else { return nil }
                return IQuizQuestion(text: "Which of these songs is by \(s.artist)?", correctAnswer: s.title,
                                     wrong: wrong.map { titleNames[$0]! })
            }
        }

        var result: [IQuizQuestion] = []
        var usedTitles = Set<String>()
        var kindCursor = Int.random(in: 0..<Kind.allCases.count)
        for s in songs.shuffled() {
            guard result.count < count else { break }
            guard usedTitles.insert(key(s.title)).inserted else { continue }
            // Rotate through the kinds so a round mixes question types.
            for offset in 0..<Kind.allCases.count {
                let kind = Kind.allCases[(kindCursor + offset) % Kind.allCases.count]
                if let q = make(kind, s) {
                    result.append(q)
                    kindCursor += 1
                    break
                }
            }
        }
        return result
    }
}

// MARK: - Answer row

/// One answer, styled like `CustomTableViewCell`: Helvetica Bold 15, iPod blue
/// gradient when selected, green/red once the answer is revealed.
private final class IQuizAnswerRow: UIView {

    enum State { case normal, selected, correct, wrong }

    private let background = CAGradientLayer()
    private let label = UILabel()

    var state: State = .normal { didSet { apply() } }
    var title: String {
        get { label.text ?? "" }
        set { label.text = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        background.startPoint = CGPoint(x: 0.5, y: 0)
        background.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(background)
        label.font = GameStyle.font(15)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        apply()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.frame = bounds
        CATransaction.commit()
        label.frame = CGRect(x: 15, y: 0, width: bounds.width - 15 - 12, height: bounds.height)
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
        label.textColor = colors == nil ? .black : .white
    }
}

// MARK: - Logo

/// The glossy iQuiz wordmark: a rounded blue lozenge with "iQuiz" in white and an
/// orange question-mark badge on its shoulder, all drawn in Core Graphics.
private final class IQuizLogoView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let b = bounds
        let space = CGColorSpaceCreateDeviceRGB()
        let badgeD = b.height * 0.5
        let badge = CGRect(x: b.maxX - badgeD - 3, y: 2, width: badgeD, height: badgeD)
        let plate = CGRect(x: 4, y: badgeD * 0.38, width: b.width - 8 - badgeD * 0.35,
                           height: b.height - badgeD * 0.38 - 8)
        let radius = plate.height * 0.32
        let platePath = UIBezierPath(roundedRect: plate, cornerRadius: radius)

        // Drop shadow.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 5, color: UIColor(white: 0, alpha: 0.4).cgColor)
        UIColor(red: 20/255, green: 60/255, blue: 150/255, alpha: 1).setFill()
        platePath.fill()
        ctx.restoreGState()

        // Body gradient.
        ctx.saveGState()
        platePath.addClip()
        let body = [UIColor(red: 110/255, green: 175/255, blue: 255/255, alpha: 1).cgColor,
                    UIColor(red: 35/255, green: 105/255, blue: 225/255, alpha: 1).cgColor,
                    UIColor(red: 15/255, green: 55/255, blue: 160/255, alpha: 1).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: body, locations: [0, 0.55, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: plate.minY), end: CGPoint(x: 0, y: plate.maxY), options: [])
        }
        // Specular gloss across the top half.
        let glossRect = CGRect(x: plate.minX + 3, y: plate.minY + 2, width: plate.width - 6, height: plate.height * 0.48)
        let gloss = UIBezierPath(roundedRect: glossRect, byRoundingCorners: [.topLeft, .topRight],
                                 cornerRadii: CGSize(width: radius - 2, height: radius - 2))
        ctx.saveGState()
        gloss.addClip()
        let shine = [UIColor(white: 1, alpha: 0.7).cgColor, UIColor(white: 1, alpha: 0.12).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: shine, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: glossRect.minY), end: CGPoint(x: 0, y: glossRect.maxY), options: [])
        }
        ctx.restoreGState()
        ctx.restoreGState()

        // Rim.
        UIColor(red: 10/255, green: 40/255, blue: 120/255, alpha: 1).setStroke()
        platePath.lineWidth = 1
        platePath.stroke()
        let inner = UIBezierPath(roundedRect: plate.insetBy(dx: 1.5, dy: 1.5), cornerRadius: radius - 1.5)
        UIColor(white: 1, alpha: 0.35).setStroke()
        inner.lineWidth = 0.75
        inner.stroke()

        // Wordmark.
        let fontSize = plate.height * 0.6
        let shadow = NSShadow()
        shadow.shadowColor = UIColor(white: 0, alpha: 0.45)
        shadow.shadowOffset = CGSize(width: 0, height: 1.5)
        shadow.shadowBlurRadius = 2
        let word = NSAttributedString(string: "iQuiz", attributes: [
            .font: GameStyle.font(fontSize),
            .foregroundColor: UIColor.white,
            .shadow: shadow,
            .kern: -fontSize * 0.02
        ])
        let ws = word.size()
        let textBox = CGRect(x: plate.minX, y: plate.minY, width: plate.width - badgeD * 0.4, height: plate.height)
        word.draw(at: CGPoint(x: textBox.midX - ws.width / 2, y: textBox.midY - ws.height / 2))

        // Question-mark badge.
        let badgePath = UIBezierPath(ovalIn: badge)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor(white: 0, alpha: 0.4).cgColor)
        UIColor.white.setFill()
        badgePath.fill()
        ctx.restoreGState()

        let badgeInner = badge.insetBy(dx: 2.5, dy: 2.5)
        let innerPath = UIBezierPath(ovalIn: badgeInner)
        ctx.saveGState()
        innerPath.addClip()
        let orange = [UIColor(red: 255/255, green: 200/255, blue: 80/255, alpha: 1).cgColor,
                      UIColor(red: 245/255, green: 135/255, blue: 25/255, alpha: 1).cgColor,
                      UIColor(red: 210/255, green: 85/255, blue: 10/255, alpha: 1).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: orange, locations: [0, 0.55, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: badgeInner.minY), end: CGPoint(x: 0, y: badgeInner.maxY), options: [])
        }
        let badgeGloss = CGRect(x: badgeInner.minX + badgeInner.width * 0.12, y: badgeInner.minY + 1,
                                width: badgeInner.width * 0.76, height: badgeInner.height * 0.5)
        UIBezierPath(ovalIn: badgeGloss).addClip()
        if let g = CGGradient(colorsSpace: space, colors: shine, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: badgeGloss.minY), end: CGPoint(x: 0, y: badgeGloss.maxY), options: [])
        }
        ctx.restoreGState()

        let qSize = badgeInner.height * 0.72
        let mark = NSAttributedString(string: "?", attributes: [
            .font: GameStyle.font(qSize),
            .foregroundColor: UIColor.white,
            .shadow: shadow
        ])
        let ms = mark.size()
        mark.draw(at: CGPoint(x: badgeInner.midX - ms.width / 2, y: badgeInner.midY - ms.height / 2))
    }
}

// MARK: - Bundled packs

private enum IQuizBank {
    static let myMusic = "My Music"

    static let packs: [(name: String, entries: [IQuizEntry])] = [
        ("Music Trivia", music),
        ("iPod & Apple History", apple),
        ("General Knowledge", general),
        ("Movies & TV", movies),
    ]

    // Each entry: question, correct answer, then three wrong answers.

    static let music: [IQuizEntry] = [
        Q("Which band released the album ‘Abbey Road’?", "The Beatles", "The Rolling Stones", "The Who", "The Kinks"),
        Q("Who is known as the ‘King of Pop’?", "Michael Jackson", "Prince", "Elvis Presley", "Justin Timberlake"),
        Q("In which year was Michael Jackson’s ‘Thriller’ released?", "1982", "1979", "1984", "1986"),
        Q("Bono is the lead singer of which band?", "U2", "Coldplay", "R.E.M.", "Oasis"),
        Q("Freddie Mercury was the lead singer of which band?", "Queen", "Led Zeppelin", "Genesis", "Deep Purple"),
        Q("Who released the album ‘Purple Rain’ in 1984?", "Prince", "Madonna", "David Bowie", "Stevie Wonder"),
        Q("Which instrument is Jimi Hendrix famous for playing?", "Guitar", "Drums", "Piano", "Saxophone"),
        Q("Kurt Cobain was the frontman of which band?", "Nirvana", "Pearl Jam", "Soundgarden", "Alice in Chains"),
        Q("‘Rumours’ (1977) is an album by which band?", "Fleetwood Mac", "Eagles", "The Doobie Brothers", "Steely Dan"),
        Q("Who released the 1971 song ‘Imagine’?", "John Lennon", "Paul McCartney", "George Harrison", "Ringo Starr"),
        Q("‘The Dark Side of the Moon’ is an album by which band?", "Pink Floyd", "Yes", "The Doors", "Rush"),
        Q("Who sang ‘Like a Prayer’?", "Madonna", "Cyndi Lauper", "Whitney Houston", "Janet Jackson"),
        Q("How many strings does a standard guitar have?", "6", "4", "5", "8"),
        Q("How many keys does a standard piano have?", "88", "76", "92", "100"),
        Q("Which country does ABBA come from?", "Sweden", "Norway", "Denmark", "Finland"),
        Q("What is the name of Elvis Presley’s Memphis home?", "Graceland", "Neverland", "Paisley Park", "Sun Studio"),
        Q("‘Back in Black’ is an album by which band?", "AC/DC", "Def Leppard", "Kiss", "Van Halen"),
        Q("Which band released ‘OK Computer’ in 1997?", "Radiohead", "Blur", "Muse", "Oasis"),
        Q("Who is the lead singer of Coldplay?", "Chris Martin", "Thom Yorke", "Brandon Flowers", "Liam Gallagher"),
        Q("Which singer is nicknamed ‘The Boss’?", "Bruce Springsteen", "Bob Dylan", "Tom Petty", "Billy Joel"),
        Q("In which year did Queen release ‘Bohemian Rhapsody’?", "1975", "1971", "1978", "1981"),
        Q("Mick Jagger is the lead singer of which band?", "The Rolling Stones", "Aerosmith", "The Who", "The Kinks"),
        Q("Who composed the ‘Moonlight Sonata’?", "Beethoven", "Mozart", "Bach", "Chopin"),
        Q("Who composed ‘The Four Seasons’?", "Vivaldi", "Handel", "Haydn", "Bach"),
        Q("Which duo had a huge 2003 hit with ‘Hey Ya!’?", "OutKast", "The White Stripes", "Daft Punk", "Gnarls Barkley"),
        Q("Which country does Daft Punk come from?", "France", "Germany", "Belgium", "Netherlands"),
        Q("Which heavy metal band’s mascot is called Eddie?", "Iron Maiden", "Metallica", "Megadeth", "Slayer"),
        Q("Who had a 1967 hit with ‘Respect’?", "Aretha Franklin", "Diana Ross", "Tina Turner", "Etta James"),
        Q("Which album opens with ‘Smells Like Teen Spirit’?", "Nevermind", "In Utero", "Bleach", "Ten"),
        Q("Which group sang ‘Wannabe’ in 1996?", "Spice Girls", "All Saints", "Destiny’s Child", "TLC"),
        Q("Bob Marley is most associated with which genre?", "Reggae", "Ska", "Calypso", "Soul"),
        Q("Which band recorded ‘Hotel California’?", "Eagles", "The Byrds", "Fleetwood Mac", "America"),
        Q("Who sang ‘Rocket Man’ in 1972?", "Elton John", "Billy Joel", "Rod Stewart", "Phil Collins"),
        Q("Which Beatles album features ‘Here Comes the Sun’?", "Abbey Road", "Revolver", "Let It Be", "Help!"),
        Q("After Nirvana, Dave Grohl founded which band?", "Foo Fighters", "Green Day", "Audioslave", "Weezer"),
        Q("Who sang ‘Billie Jean’?", "Michael Jackson", "Prince", "Lionel Richie", "George Michael"),
        Q("What does ‘DJ’ stand for?", "Disc Jockey", "Digital Jockey", "Dance Judge", "Disc Juggler"),
        Q("Which band recorded ‘Stairway to Heaven’?", "Led Zeppelin", "Deep Purple", "Black Sabbath", "The Doors"),
        Q("Beyoncé first found fame in which group?", "Destiny’s Child", "TLC", "En Vogue", "Spice Girls"),
        Q("Which rapper’s real name is Marshall Mathers?", "Eminem", "Jay-Z", "Nas", "50 Cent"),
        Q("Which singer was known as ‘The Man in Black’?", "Johnny Cash", "Roy Orbison", "Elvis Presley", "Hank Williams"),
        Q("‘The Thin White Duke’ was a persona of which artist?", "David Bowie", "Lou Reed", "Iggy Pop", "Bryan Ferry"),
        Q("Which band recorded ‘Mr. Brightside’?", "The Killers", "The Strokes", "Franz Ferdinand", "Kings of Leon"),
        Q("How many Beatles were there in the classic line-up?", "4", "3", "5", "6"),
        Q("Who composed the opera ‘The Magic Flute’?", "Mozart", "Wagner", "Verdi", "Puccini"),
    ]

    static let apple: [IQuizEntry] = [
        Q("In which year was the first iPod announced?", "2001", "1999", "2003", "2005"),
        Q("How much storage did the original iPod have?", "5 GB", "1 GB", "10 GB", "20 GB"),
        Q("What was the original iPod’s famous slogan?", "1,000 songs in your pocket", "Music everywhere",
          "Rip. Mix. Burn.", "Think different"),
        Q("In which year did the iTunes Music Store open?", "2003", "2001", "2004", "2005"),
        Q("How much did a song cost when the iTunes Music Store launched?", "99¢", "49¢", "$1.29", "$1.99"),
        Q("What did the first iPod shuffle not have?", "A screen", "A battery", "A headphone jack", "A play button"),
        Q("Which iPod replaced the iPod mini in 2005?", "iPod nano", "iPod shuffle", "iPod touch", "iPod classic"),
        Q("In which year was the iPod touch introduced?", "2007", "2005", "2008", "2009"),
        Q("In which year was the first iPhone announced?", "2007", "2005", "2006", "2008"),
        Q("Who co-founded Apple with Steve Jobs and Ronald Wayne?", "Steve Wozniak", "Bill Gates", "Tim Cook", "Jony Ive"),
        Q("In which year was Apple founded?", "1976", "1974", "1980", "1984"),
        Q("In which year was the Macintosh introduced?", "1984", "1981", "1986", "1989"),
        Q("Who directed Apple’s famous ‘1984’ Macintosh advert?", "Ridley Scott", "Steven Spielberg", "James Cameron", "George Lucas"),
        Q("In which year did the original iMac debut?", "1998", "1996", "2000", "2002"),
        Q("Who is often called the ‘father of the iPod’?", "Tony Fadell", "Scott Forstall", "Phil Schiller", "Steve Wozniak"),
        Q("How did the original iPod connect to a Mac?", "FireWire", "USB-C", "Bluetooth", "Lightning"),
        Q("Which iPod was the first to have a click wheel?", "iPod mini", "Original iPod", "iPod nano", "iPod shuffle"),
        Q("What was the largest capacity of iPod classic sold?", "160 GB", "80 GB", "120 GB", "250 GB"),
        Q("What did Apple’s very first logo show?", "Isaac Newton under a tree", "A rainbow apple", "A pear", "A computer"),
        Q("Buying which company brought Steve Jobs back to Apple?", "NeXT", "Pixar", "Be Inc.", "Adobe"),
        Q("iTunes grew out of which app that Apple bought in 2000?", "SoundJam MP", "Winamp", "RealJukebox", "MusicMatch"),
        Q("What colour were the earphones in the iPod silhouette adverts?", "White", "Black", "Silver", "Red"),
        Q("In which year did the first Apple retail stores open?", "2001", "1995", "1998", "2003"),
        Q("In which year did Apple Computer, Inc. become Apple Inc.?", "2007", "2001", "2005", "2010"),
        Q("Mac OS X 10.5 was named after which big cat?", "Leopard", "Tiger", "Panther", "Jaguar"),
        Q("In which year did Apple announce its switch to Intel chips?", "2005", "2003", "2007", "2008"),
        Q("Which processor family did Macs use just before Intel?", "PowerPC", "ARM", "SPARC", "Alpha"),
        Q("What was Apple’s very first computer called?", "Apple I", "Lisa", "Apple II", "Macintosh"),
        Q("In which year was the Apple II released?", "1977", "1975", "1979", "1982"),
        Q("Which game was hidden in the original iPod?", "Brick", "Snake", "Tetris", "Pong"),
        Q("In which year did the first iPod that played video arrive?", "2005", "2003", "2004", "2007"),
        Q("What was Apple’s Cupertino HQ address in the iPod era?", "1 Infinite Loop", "1 Apple Park Way",
          "1600 Amphitheatre Pkwy", "1 Hacker Way"),
        Q("Who succeeded Steve Jobs as Apple CEO in 2011?", "Tim Cook", "Phil Schiller", "Scott Forstall", "John Sculley"),
        Q("Which Apple CEO did Steve Jobs recruit from Pepsi?", "John Sculley", "Gil Amelio", "Michael Spindler", "Tim Cook"),
        Q("What kind of storage did the iPod nano use?", "Flash memory", "Hard drive", "Microdrive", "Optical disc"),
        Q("In which year did iTunes come to Windows?", "2003", "2001", "2005", "2006"),
        Q("iPods were ‘Designed by Apple in…’ where?", "California", "Cupertino", "Silicon Valley", "America"),
        Q("Which generation of iPod was the first called ‘iPod classic’?", "6th", "4th", "5th", "7th"),
        Q("In which year did Apple launch the ‘Think different’ campaign?", "1997", "1994", "2000", "2002"),
        Q("What colour was the front of the original iPod?", "White", "Black", "Silver", "Blue"),
        Q("Which Apple app was used to sync music to an iPod?", "iTunes", "QuickTime", "iPhoto", "GarageBand"),
        Q("In which city is Apple headquartered?", "Cupertino", "Palo Alto", "San Jose", "Mountain View"),
        Q("Which music-making app did Apple launch in 2004?", "GarageBand", "Logic", "Soundtrack", "iMovie"),
        Q("Which band got its own black-and-red iPod in 2004?", "U2", "Coldplay", "The Beatles", "Radiohead"),
    ]

    static let general: [IQuizEntry] = [
        Q("What is the capital of Australia?", "Canberra", "Sydney", "Melbourne", "Perth"),
        Q("What is the largest planet in our solar system?", "Jupiter", "Saturn", "Neptune", "Earth"),
        Q("What is the chemical symbol for gold?", "Au", "Ag", "Gd", "Go"),
        Q("How many continents are there?", "7", "5", "6", "8"),
        Q("What is the largest ocean on Earth?", "Pacific", "Atlantic", "Indian", "Arctic"),
        Q("Who painted the Mona Lisa?", "Leonardo da Vinci", "Michelangelo", "Raphael", "Botticelli"),
        Q("At what temperature does water boil at sea level?", "100 °C", "90 °C", "110 °C", "120 °C"),
        Q("What is the hardest natural substance?", "Diamond", "Quartz", "Granite", "Topaz"),
        Q("Which planet is known as the Red Planet?", "Mars", "Venus", "Jupiter", "Mercury"),
        Q("How many sides does a hexagon have?", "6", "5", "7", "8"),
        Q("Who wrote ‘Romeo and Juliet’?", "William Shakespeare", "Charles Dickens", "Christopher Marlowe", "Geoffrey Chaucer"),
        Q("What is the smallest prime number?", "2", "1", "3", "0"),
        Q("What is the square root of 144?", "12", "11", "14", "16"),
        Q("Which gas do plants absorb from the air?", "Carbon dioxide", "Oxygen", "Nitrogen", "Helium"),
        Q("What is the largest animal on Earth?", "Blue whale", "African elephant", "Giraffe", "Whale shark"),
        Q("What is the fastest land animal?", "Cheetah", "Lion", "Horse", "Greyhound"),
        Q("What is the currency of Japan?", "Yen", "Won", "Yuan", "Ringgit"),
        Q("In which country are the Pyramids of Giza?", "Egypt", "Mexico", "Peru", "Sudan"),
        Q("How many players does a football (soccer) team have on the pitch?", "11", "9", "10", "12"),
        Q("At how many degrees Fahrenheit does water freeze?", "32", "0", "10", "42"),
        Q("Who was the first person to walk on the Moon?", "Neil Armstrong", "Buzz Aldrin", "Yuri Gagarin", "John Glenn"),
        Q("In which year did humans first land on the Moon?", "1969", "1965", "1972", "1975"),
        Q("What is the chemical formula for water?", "H₂O", "CO₂", "O₂", "H₂O₂"),
        Q("What is the tallest mountain above sea level?", "Mount Everest", "K2", "Kilimanjaro", "Mont Blanc"),
        Q("What is the largest country by area?", "Russia", "Canada", "China", "United States"),
        Q("How many legs does a spider have?", "8", "6", "10", "12"),
        Q("Who developed the theory of relativity?", "Albert Einstein", "Isaac Newton", "Niels Bohr", "Galileo Galilei"),
        Q("Which organ pumps blood around the body?", "Heart", "Liver", "Lungs", "Kidneys"),
        Q("How many minutes are there in a day?", "1,440", "1,240", "1,400", "1,600"),
        Q("What is the main language spoken in Brazil?", "Portuguese", "Spanish", "French", "Italian"),
        Q("What is the capital of Canada?", "Ottawa", "Toronto", "Vancouver", "Montreal"),
        Q("Who wrote the novel ‘1984’?", "George Orwell", "Aldous Huxley", "H. G. Wells", "Ray Bradbury"),
        Q("What is the largest hot desert in the world?", "Sahara", "Gobi", "Kalahari", "Mojave"),
        Q("Which element has the atomic number 1?", "Hydrogen", "Helium", "Oxygen", "Carbon"),
        Q("How many bones are in the adult human body?", "206", "186", "212", "230"),
        Q("Which planet is closest to the Sun?", "Mercury", "Venus", "Mars", "Earth"),
        Q("Which blood type is the universal donor?", "O negative", "AB positive", "A negative", "B positive"),
        Q("The Great Barrier Reef lies off the coast of which country?", "Australia", "Indonesia", "New Zealand", "Brazil"),
        Q("Who is credited with inventing the telephone?", "Alexander Graham Bell", "Thomas Edison", "Nikola Tesla", "Guglielmo Marconi"),
        Q("Roughly how fast does light travel?", "300,000 km/s", "30,000 km/s", "150,000 km/s", "3,000,000 km/s"),
        Q("In which city is the Colosseum?", "Rome", "Athens", "Istanbul", "Naples"),
        Q("How many degrees are in a right angle?", "90", "45", "180", "360"),
        Q("What is the capital of Spain?", "Madrid", "Barcelona", "Seville", "Valencia"),
        Q("Which planet is famous for its bright rings?", "Saturn", "Mars", "Venus", "Mercury"),
        Q("Who wrote ‘Pride and Prejudice’?", "Jane Austen", "Charlotte Brontë", "Emily Brontë", "George Eliot"),
    ]

    static let movies: [IQuizEntry] = [
        Q("Who directed ‘Jaws’ (1975)?", "Steven Spielberg", "George Lucas", "Martin Scorsese", "Francis Ford Coppola"),
        Q("In ‘Star Wars’, who is Darth Vader’s son?", "Luke Skywalker", "Han Solo", "Obi-Wan Kenobi", "Lando Calrissian"),
        Q("In which town do The Simpsons live?", "Springfield", "Shelbyville", "Quahog", "South Park"),
        Q("What is the coffee shop called in ‘Friends’?", "Central Perk", "Monk’s Café", "The Max", "MacLaren’s"),
        Q("Who directed ‘Titanic’ (1997)?", "James Cameron", "Ridley Scott", "Peter Jackson", "Ron Howard"),
        Q("Which studio made ‘Toy Story’ (1995)?", "Pixar", "DreamWorks", "Blue Sky", "Illumination"),
        Q("What is the space ranger called in ‘Toy Story’?", "Buzz Lightyear", "Zurg", "Rex", "Captain Comet"),
        Q("Who directed ‘The Lord of the Rings’ film trilogy?", "Peter Jackson", "Guillermo del Toro", "Sam Raimi", "Ridley Scott"),
        Q("What is the name of Harry Potter’s school?", "Hogwarts", "Durmstrang", "Beauxbatons", "Ilvermorny"),
        Q("Who played Neo in ‘The Matrix’?", "Keanu Reeves", "Laurence Fishburne", "Tom Cruise", "Brad Pitt"),
        Q("Who played Vito Corleone in ‘The Godfather’ (1972)?", "Marlon Brando", "Al Pacino", "James Caan", "Robert Duvall"),
        Q("What is Kramer’s first name in ‘Seinfeld’?", "Cosmo", "Elmo", "Morty", "Newman"),
        Q("Which car is the time machine in ‘Back to the Future’?", "DeLorean", "Ferrari", "Mustang", "Corvette"),
        Q("How fast must the time machine go in ‘Back to the Future’?", "88 mph", "77 mph", "99 mph", "121 mph"),
        Q("What is the lion cub called in ‘The Lion King’?", "Simba", "Mufasa", "Scar", "Nala"),
        Q("Which paper company is ‘The Office’ (US) set in?", "Dunder Mifflin", "Wernham Hogg", "Initech", "Sterling Cooper"),
        Q("What is James Bond’s code number?", "007", "006", "009", "001"),
        Q("Which author created James Bond?", "Ian Fleming", "John le Carré", "Tom Clancy", "Len Deighton"),
        Q("In ‘Lost’, which Oceanic flight crashed on the island?", "Flight 815", "Flight 714", "Flight 908", "Flight 422"),
        Q("What is the Doctor’s time machine called in ‘Doctor Who’?", "The TARDIS", "The DeLorean", "The Nautilus", "The Enterprise"),
        Q("What kind of creature is Shrek?", "An ogre", "A troll", "A giant", "A goblin"),
        Q("What kind of fish is Nemo?", "Clownfish", "Angelfish", "Blue tang", "Goldfish"),
        Q("Who played Indiana Jones?", "Harrison Ford", "Kevin Costner", "Tom Selleck", "Mel Gibson"),
        Q("Who played Captain Jack Sparrow?", "Johnny Depp", "Orlando Bloom", "Jude Law", "Russell Crowe"),
        Q("Which film features the line ‘Here’s looking at you, kid’?", "Casablanca", "Citizen Kane", "Gone with the Wind", "The Maltese Falcon"),
        Q("What was Disney’s first full-length animated feature?", "Snow White and the Seven Dwarfs", "Pinocchio", "Fantasia", "Bambi"),
        Q("In which US state is ‘The Sopranos’ set?", "New Jersey", "New York", "Pennsylvania", "Illinois"),
        Q("What is Walter White’s job at the start of ‘Breaking Bad’?", "Chemistry teacher", "Pharmacist", "Doctor", "Lawyer"),
        Q("‘Jurassic Park’ is based on a novel by which author?", "Michael Crichton", "Stephen King", "Dean Koontz", "Tom Clancy"),
        Q("Which film’s theme song asks ‘Who you gonna call?’", "Ghostbusters", "Gremlins", "Beetlejuice", "Men in Black"),
        Q("What is Dorothy’s dog called in ‘The Wizard of Oz’?", "Toto", "Benji", "Lassie", "Rex"),
        Q("Who played the title role in ‘Forrest Gump’?", "Tom Hanks", "Robin Williams", "Kevin Costner", "Bill Murray"),
        Q("How many main characters are there in ‘Friends’?", "6", "4", "5", "7"),
        Q("Who starred in ‘The Fresh Prince of Bel-Air’?", "Will Smith", "Eddie Murphy", "Jamie Foxx", "Chris Rock"),
        Q("Who is headmaster of Hogwarts in the early Harry Potter films?", "Albus Dumbledore", "Severus Snape",
          "Minerva McGonagall", "Rubeus Hagrid"),
        Q("Which Pixar film is about a robot cleaning up Earth?", "WALL-E", "Up", "Cars", "Robots"),
        Q("What is Rocky’s surname in the ‘Rocky’ films?", "Balboa", "Creed", "Drago", "Lang"),
        Q("Who directed the original ‘Star Wars’ (1977)?", "George Lucas", "Steven Spielberg", "Irvin Kershner", "Ridley Scott"),
        Q("Which colour pill does Neo take in ‘The Matrix’?", "Red", "Blue", "Green", "White"),
        Q("Who is Mr. Burns’ loyal assistant in ‘The Simpsons’?", "Smithers", "Lenny", "Carl", "Moe"),
        Q("What is the Academy Award statuette better known as?", "Oscar", "Emmy", "Tony", "Grammy"),
        Q("Which TV comedy follows the Bluth family?", "Arrested Development", "Malcolm in the Middle", "Modern Family", "Scrubs"),
        Q("Who played Jack in ‘Titanic’ (1997)?", "Leonardo DiCaprio", "Matt Damon", "Brad Pitt", "Ethan Hawke"),
        Q("What is Homer Simpson’s favourite beer?", "Duff", "Buzz", "Fudd", "Tipsy"),
        Q("Which hobbit carries the One Ring to Mordor?", "Frodo Baggins", "Bilbo Baggins", "Merry Brandybuck", "Pippin Took"),
    ]
}
