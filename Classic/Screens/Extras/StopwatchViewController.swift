//
//  StopwatchViewController.swift
//  Classic
//

import UIKit

// MARK: - Store

/// Stopwatch state lives in UserDefaults as dates and durations, never as a counting
/// timer, so it keeps running across leaving the screen, backgrounding and relaunch.
private final class StopwatchStore {
    static let shared = StopwatchStore()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let startDate = "classic.stopwatch.startDate"       // Double (ref-date seconds), present only while running
        static let accumulated = "classic.stopwatch.accumulated"   // Double seconds banked from earlier runs
        static let laps = "classic.stopwatch.laps"                 // [Double] completed lap durations, oldest first
        static let lastSession = "classic.stopwatch.lastSession"   // [String: Any] log of the last reset session
    }

    struct Session {
        let date: Date
        let total: TimeInterval
        let laps: [TimeInterval]
    }

    private(set) var startDate: Date?
    private(set) var accumulated: TimeInterval
    private(set) var laps: [TimeInterval]
    private(set) var lastSession: Session?

    private init() {
        if defaults.object(forKey: Key.startDate) != nil {
            startDate = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Key.startDate))
        }
        accumulated = max(0, defaults.double(forKey: Key.accumulated))
        laps = (defaults.array(forKey: Key.laps) as? [Double]) ?? []
        if let dict = defaults.dictionary(forKey: Key.lastSession),
           let date = dict["date"] as? Double, let total = dict["total"] as? Double {
            lastSession = Session(date: Date(timeIntervalSinceReferenceDate: date),
                                  total: total,
                                  laps: (dict["laps"] as? [Double]) ?? [])
        }
    }

    var isRunning: Bool { startDate != nil }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        guard let start = startDate else { return accumulated }
        return accumulated + max(0, now.timeIntervalSince(start))
    }

    /// Time on the lap currently in progress.
    func currentLap(at now: Date = Date()) -> TimeInterval {
        max(0, elapsed(at: now) - laps.reduce(0, +))
    }

    func start() {
        guard !isRunning else { return }
        startDate = Date()
        save()
    }

    func stop() {
        guard isRunning else { return }
        accumulated = elapsed()
        startDate = nil
        save()
    }

    func lap() {
        guard isRunning else { return }
        laps.append(currentLap())
        save()
    }

    /// Clears the stopwatch, logging the finished session (iPod "Stopwatch" log style).
    func reset() {
        let total = elapsed()
        if total > 0 {
            var logged = laps
            let remainder = total - laps.reduce(0, +)
            if !logged.isEmpty && remainder > 0.05 { logged.append(remainder) }
            lastSession = Session(date: Date(), total: total, laps: logged)
        }
        startDate = nil
        accumulated = 0
        laps = []
        save()
    }

    private func save() {
        if let start = startDate {
            defaults.set(start.timeIntervalSinceReferenceDate, forKey: Key.startDate)
        } else {
            defaults.removeObject(forKey: Key.startDate)
        }
        defaults.set(accumulated, forKey: Key.accumulated)
        defaults.set(laps, forKey: Key.laps)
        if let s = lastSession {
            defaults.set(["date": s.date.timeIntervalSinceReferenceDate, "total": s.total, "laps": s.laps],
                         forKey: Key.lastSession)
        }
    }

    // MARK: Formatting

    /// "00:00:00.0"
    static func longString(_ t: TimeInterval) -> String {
        let tenths = Int((max(0, t) * 10).rounded(.down))
        let h = tenths / 36000, m = (tenths / 600) % 60, s = (tenths / 10) % 60, d = tenths % 10
        return String(format: "%02d:%02d:%02d.%d", h, m, s, d)
    }

    /// "00:12.3", or "1:02:03.4" past the hour.
    static func shortString(_ t: TimeInterval) -> String {
        let tenths = Int((max(0, t) * 10).rounded(.down))
        let h = tenths / 36000, m = (tenths / 600) % 60, s = (tenths / 10) % 60, d = tenths % 10
        if h > 0 { return String(format: "%d:%02d:%02d.%d", h, m, s, d) }
        return String(format: "%02d:%02d.%d", m, s, d)
    }
}

// MARK: - Screen

/// Extras ▸ Stopwatch. Play/Pause starts/stops, Center laps (running) or resets (stopped),
/// the wheel scrolls the lap list, Menu leaves (the stopwatch keeps running).
class StopwatchViewController: UIViewController, ClickWheelProtocol {
    private let store = StopwatchStore.shared

    private let dial = StopwatchDialView()
    private let timeLabel = UILabel()
    private let lapLabel = UILabel()
    private let statusLabel = UILabel()
    private let divider = UIView()
    private let tableView = UITableView()
    private let emptyLabel = UILabel()
    private let footer = UIView()
    private let footerGradient = CAGradientLayer()
    private let footerLeft = UILabel()
    private let footerRight = UILabel()

    private var displayLink: CADisplayLink?
    private var hasSetupUI = false
    private var counter = 0

    private struct Row { let title: String; let value: String; let dim: Bool }
    private var rows: [Row] = []

    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    // MARK: Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Stopwatch"
        reloadRows()
        refreshDisplay()
        updateRunState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDisplayLink()
    }

    deinit { displayLink?.invalidate() }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        footerGradient.frame = footer.bounds
        CATransaction.commit()
    }

    private func setupUI() {
        guard !hasSetupUI else { return }
        hasSetupUI = true
        view.backgroundColor = .white

        let top = UIView()
        top.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(top)

        dial.translatesAutoresizingMaskIntoConstraints = false
        top.addSubview(dial)

        timeLabel.font = UIFont(name: "Helvetica-Bold", size: 34)
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.5
        timeLabel.textColor = .black
        timeLabel.text = StopwatchStore.longString(0)

        lapLabel.font = UIFont(name: "Helvetica-Bold", size: 15)
        lapLabel.textColor = UIColor(white: 0.35, alpha: 1)
        lapLabel.adjustsFontSizeToFitWidth = true
        lapLabel.minimumScaleFactor = 0.6

        statusLabel.font = UIFont(name: "Helvetica", size: 12)
        statusLabel.textColor = UIColor(white: 0.5, alpha: 1)

        for l in [timeLabel, lapLabel, statusLabel] {
            l.translatesAutoresizingMaskIntoConstraints = false
            top.addSubview(l)
        }

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor(white: 0.75, alpha: 1)
        view.addSubview(divider)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .white
        tableView.showsVerticalScrollIndicator = true
        view.addSubview(tableView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = UIFont(name: "Helvetica-Bold", size: 14)
        emptyLabel.textColor = UIColor(white: 0.6, alpha: 1)
        emptyLabel.text = "No Laps"
        view.addSubview(emptyLabel)

        footer.translatesAutoresizingMaskIntoConstraints = false
        footerGradient.colors = [UIColor.gradientVeryLightGrey.cgColor, UIColor(white: 0.84, alpha: 1).cgColor]
        footer.layer.addSublayer(footerGradient)
        let footerLine = UIView()
        footerLine.translatesAutoresizingMaskIntoConstraints = false
        footerLine.backgroundColor = UIColor(white: 0.7, alpha: 1)
        footer.addSubview(footerLine)
        for l in [footerLeft, footerRight] {
            l.translatesAutoresizingMaskIntoConstraints = false
            l.font = UIFont(name: "Helvetica-Bold", size: 11)
            l.textColor = UIColor(white: 0.4, alpha: 1)
            footer.addSubview(l)
        }
        view.addSubview(footer)

        // Top section height scales with the screen; the dial is a little taller than wide (crown on top).
        let topHeight = top.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.42)
        topHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: view.topAnchor),
            top.leftAnchor.constraint(equalTo: view.leftAnchor),
            top.rightAnchor.constraint(equalTo: view.rightAnchor),
            topHeight,
            top.heightAnchor.constraint(lessThanOrEqualToConstant: 150),

            dial.leftAnchor.constraint(equalTo: top.leftAnchor, constant: 12),
            dial.topAnchor.constraint(equalTo: top.topAnchor, constant: 6),
            dial.bottomAnchor.constraint(equalTo: top.bottomAnchor, constant: -6),
            dial.widthAnchor.constraint(equalTo: dial.heightAnchor, multiplier: 1 / 1.18),

            timeLabel.leftAnchor.constraint(equalTo: dial.rightAnchor, constant: 14),
            timeLabel.rightAnchor.constraint(lessThanOrEqualTo: top.rightAnchor, constant: -10),
            timeLabel.centerYAnchor.constraint(equalTo: top.centerYAnchor, constant: -4),

            lapLabel.leftAnchor.constraint(equalTo: timeLabel.leftAnchor, constant: 2),
            lapLabel.rightAnchor.constraint(lessThanOrEqualTo: top.rightAnchor, constant: -10),
            lapLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 2),

            statusLabel.leftAnchor.constraint(equalTo: timeLabel.leftAnchor, constant: 2),
            statusLabel.bottomAnchor.constraint(equalTo: timeLabel.topAnchor, constant: -2),

            divider.topAnchor.constraint(equalTo: top.bottomAnchor),
            divider.leftAnchor.constraint(equalTo: view.leftAnchor),
            divider.rightAnchor.constraint(equalTo: view.rightAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            tableView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),

            footer.leftAnchor.constraint(equalTo: view.leftAnchor),
            footer.rightAnchor.constraint(equalTo: view.rightAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 20),
            footerLine.topAnchor.constraint(equalTo: footer.topAnchor),
            footerLine.leftAnchor.constraint(equalTo: footer.leftAnchor),
            footerLine.rightAnchor.constraint(equalTo: footer.rightAnchor),
            footerLine.heightAnchor.constraint(equalToConstant: 1),
            footerLeft.leftAnchor.constraint(equalTo: footer.leftAnchor, constant: 10),
            footerLeft.centerYAnchor.constraint(equalTo: footer.centerYAnchor, constant: 0.5),
            footerRight.rightAnchor.constraint(equalTo: footer.rightAnchor, constant: -10),
            footerRight.centerYAnchor.constraint(equalTo: footer.centerYAnchor, constant: 0.5),
        ])
    }

    // MARK: Display

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func displayLinkFired() { refreshDisplay() }

    private func refreshDisplay() {
        let now = Date()
        let elapsed = store.elapsed(at: now)
        let timeText = StopwatchStore.longString(elapsed)
        if timeLabel.text != timeText { timeLabel.text = timeText }
        let lapText = elapsed > 0 || store.isRunning
            ? "Lap \(store.laps.count + 1)   \(StopwatchStore.shortString(store.currentLap(at: now)))"
            : "Lap 1   \(StopwatchStore.shortString(0))"
        if lapLabel.text != lapText { lapLabel.text = lapText }
        dial.elapsed = elapsed
    }

    /// Start/stop the display link and update the hint footer for the current state.
    private func updateRunState() {
        let running = store.isRunning
        let hasTime = store.elapsed() > 0
        statusLabel.text = running ? "Running" : (hasTime ? "Stopped" : "Ready")
        footerLeft.text = running ? "❙❙  Stop" : "▶  Start"
        footerRight.text = running ? "Lap" : (hasTime ? "Reset" : "")
        if running {
            startDisplayLink()
        } else {
            stopDisplayLink()
            refreshDisplay()
        }
    }

    private func reloadRows() {
        let laps = store.laps
        if !laps.isEmpty || store.isRunning || store.elapsed() > 0 {
            rows = laps.enumerated().reversed().map {
                Row(title: "Lap \($0.offset + 1)", value: StopwatchStore.shortString($0.element), dim: false)
            }
        } else if let s = store.lastSession {
            // Reset with nothing timed yet: show the last session's log, greyed out.
            rows = [Row(title: "Last: " + Self.logDateFormatter.string(from: s.date),
                        value: StopwatchStore.shortString(s.total), dim: true)]
            rows += s.laps.enumerated().reversed().map {
                Row(title: "Lap \($0.offset + 1)", value: StopwatchStore.shortString($0.element), dim: true)
            }
        } else {
            rows = []
        }
        emptyLabel.isHidden = !rows.isEmpty
        counter = max(0, min(counter, rows.count - 1))
        tableView.reloadData()
        selectCurrent()
    }

    private func selectCurrent() {
        guard !rows.isEmpty else { return }
        let ip = IndexPath(row: counter, section: 0)
        tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
        tableView.scrollToRow(at: ip, at: .none, animated: false)
    }

    // MARK: ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        guard !rows.isEmpty else { return }
        if rotationDirection == .CLOCKWISE {
            guard counter < rows.count - 1 else { return }
            counter += 1
        } else {
            guard counter > 0 else { return }
            counter -= 1
        }
        selectCurrent()
    }

    /// Play/Pause is start/stop on this screen, not music.
    func playPausePressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        if store.isRunning {
            store.stop()
        } else {
            if store.elapsed() == 0 { counter = 0 }
            store.start()
            reloadRows()   // drops the greyed-out log when a new session begins
        }
        refreshDisplay()
        updateRunState()
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        if store.isRunning {
            store.lap()
            // Keep the highlighted lap the same when a new one is inserted at the top.
            if counter > 0 { counter += 1 }
            reloadRows()
        } else if store.elapsed() > 0 {
            store.reset()
            counter = 0
            reloadRows()
        }
        refreshDisplay()
        updateRunState()
    }

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            navigationController?.popViewController(animated: true)
        } else if pressure == .FORCE {
            navigationController?.popToRootViewController(animated: true)
        }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {}
    func previousSongPressed(pressure: ClickWheelTouchPressure) {}
}

extension StopwatchViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 30 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = StopwatchLapCell()
        let row = rows[indexPath.row]
        cell.configure(title: row.title, value: row.value, dim: row.dim)
        cell.selectionStyle = .none
        return cell
    }
}

// MARK: - Lap row

/// CustomTableViewCell (same fonts and selection gradient) with a right-aligned time.
private final class StopwatchLapCell: CustomTableViewCell {
    let valueLabel = UILabel()
    private var dim = false

    override init() {
        super.init()
        accessoryType = .none
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = UIFont(name: "Helvetica-Bold", size: 15)
        valueLabel.textAlignment = .right
        contentView.addSubview(valueLabel)
        valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        valueLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -15).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, value: String, dim: Bool) {
        self.dim = dim
        label.text = title
        valueLabel.text = value
        applyColors()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        applyColors()
    }

    private func applyColors() {
        if isSelected {
            label.textColor = .white
            valueLabel.textColor = .white
        } else {
            label.textColor = dim ? UIColor(white: 0.5, alpha: 1) : .black
            valueLabel.textColor = dim ? UIColor(white: 0.5, alpha: 1) : .black
        }
    }
}

// MARK: - Display link proxy

/// Breaks the CADisplayLink → target retain cycle.
private final class DisplayLinkProxy: NSObject {
    weak var owner: StopwatchViewController?
    init(_ owner: StopwatchViewController) { self.owner = owner }
    @objc func tick() { owner?.displayLinkFired() }
}

// MARK: - Analog dial

/// A small chrome mechanical stopwatch: crown and ring on top, white dial with 60-second
/// markings, a minute subdial, and a red sweep hand driven by `elapsed`.
private final class StopwatchDialView: UIView {
    var elapsed: TimeInterval = 0 { didSet { updateHands() } }

    private let secondHand = CAShapeLayer()
    private let minuteHand = CAShapeLayer()
    private let hubLayer = CAShapeLayer()
    private var lastBuiltSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        minuteHand.fillColor = UIColor(white: 0.12, alpha: 1).cgColor
        secondHand.fillColor = UIColor(red: 0.85, green: 0.1, blue: 0.08, alpha: 1).cgColor
        secondHand.shadowColor = UIColor.black.cgColor
        secondHand.shadowOpacity = 0.3
        secondHand.shadowRadius = 0.8
        secondHand.shadowOffset = CGSize(width: 0.5, height: 0.8)
        hubLayer.fillColor = UIColor(red: 0.7, green: 0.08, blue: 0.06, alpha: 1).cgColor
        hubLayer.strokeColor = UIColor(white: 0.9, alpha: 1).cgColor
        layer.addSublayer(minuteHand)
        layer.addSublayer(secondHand)
        layer.addSublayer(hubLayer)
    }

    // Geometry: the case circle fills the width at the bottom; the crown sits above it.
    private var caseRadius: CGFloat { min(bounds.width, bounds.height / 1.18) / 2 - 1 }
    private var pivot: CGPoint { CGPoint(x: bounds.midX, y: bounds.maxY - caseRadius - 1) }
    private var faceRadius: CGFloat { caseRadius * 0.86 }
    private var subdialCenter: CGPoint { CGPoint(x: pivot.x, y: pivot.y + faceRadius * 0.38) }
    private var subdialRadius: CGFloat { faceRadius * 0.24 }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastBuiltSize, bounds.width > 0 else { return }
        lastBuiltSize = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let r = faceRadius
        // Hands are built pointing up around their own pivot, then positioned and rotated.
        let sw = max(1, r * 0.035)
        let sp = UIBezierPath()
        sp.move(to: CGPoint(x: -sw / 2, y: r * 0.2))
        sp.addLine(to: CGPoint(x: -sw * 0.3, y: -r * 0.92))
        sp.addLine(to: CGPoint(x: sw * 0.3, y: -r * 0.92))
        sp.addLine(to: CGPoint(x: sw / 2, y: r * 0.2))
        sp.close()
        secondHand.path = sp.cgPath
        secondHand.frame = CGRect(origin: pivot, size: .zero)

        let mr = subdialRadius
        let mw = max(1, mr * 0.14)
        minuteHand.path = UIBezierPath(roundedRect: CGRect(x: -mw / 2, y: -mr * 0.85, width: mw, height: mr * 0.95),
                                       cornerRadius: mw / 2).cgPath
        minuteHand.frame = CGRect(origin: subdialCenter, size: .zero)

        let hub = max(2, r * 0.07)
        hubLayer.lineWidth = max(0.5, hub * 0.25)
        hubLayer.path = UIBezierPath(ovalIn: CGRect(x: pivot.x - hub, y: pivot.y - hub, width: hub * 2, height: hub * 2)).cgPath
        hubLayer.frame = bounds

        CATransaction.commit()
        setNeedsDisplay()
        updateHands()
    }

    private func updateHands() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let seconds = elapsed.truncatingRemainder(dividingBy: 60)
        secondHand.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(seconds / 60) * 2 * .pi))
        let minutes = (elapsed / 60).truncatingRemainder(dividingBy: 30)
        minuteHand.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(minutes / 30) * 2 * .pi))
        CATransaction.commit()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), caseRadius > 4 else { return }
        let c = pivot, R = caseRadius, r = faceRadius
        let space = CGColorSpaceCreateDeviceRGB()
        let chrome = [UIColor(white: 0.97, alpha: 1), UIColor(white: 0.62, alpha: 1),
                      UIColor(white: 0.88, alpha: 1), UIColor(white: 0.45, alpha: 1)].map { $0.cgColor } as CFArray
        let chromeGradient = CGGradient(colorsSpace: space, colors: chrome, locations: [0, 0.45, 0.6, 1])!

        // Crown: ring loop, stem, knurled button.
        let ringR = R * 0.2
        let ringC = CGPoint(x: c.x, y: c.y - R - R * 0.22 - ringR * 0.5)
        ctx.saveGState()
        ctx.setLineWidth(max(1.5, R * 0.07))
        ctx.setStrokeColor(UIColor(white: 0.55, alpha: 1).cgColor)
        ctx.strokeEllipse(in: CGRect(x: ringC.x - ringR, y: ringC.y - ringR, width: ringR * 2, height: ringR * 2))
        ctx.setLineWidth(max(0.5, R * 0.025))
        ctx.setStrokeColor(UIColor(white: 0.95, alpha: 1).cgColor)
        ctx.strokeEllipse(in: CGRect(x: ringC.x - ringR, y: ringC.y - ringR, width: ringR * 2, height: ringR * 2).insetBy(dx: -R * 0.01, dy: -R * 0.01))
        ctx.restoreGState()

        func chromeFill(_ path: UIBezierPath, from: CGPoint, to: CGPoint) {
            ctx.saveGState()
            ctx.addPath(path.cgPath)
            ctx.clip()
            ctx.drawLinearGradient(chromeGradient, start: from, end: to, options: [])
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(path.cgPath)
            ctx.setStrokeColor(UIColor(white: 0.35, alpha: 1).cgColor)
            ctx.setLineWidth(0.75)
            ctx.strokePath()
            ctx.restoreGState()
        }

        let stemW = R * 0.16
        let stem = UIBezierPath(rect: CGRect(x: c.x - stemW / 2, y: c.y - R - R * 0.14, width: stemW, height: R * 0.2))
        chromeFill(stem, from: CGPoint(x: c.x - stemW / 2, y: 0), to: CGPoint(x: c.x + stemW / 2, y: 0))
        let btnW = R * 0.34, btnH = R * 0.16
        let btnRect = CGRect(x: c.x - btnW / 2, y: c.y - R - R * 0.22 - btnH * 0.6, width: btnW, height: btnH)
        let btn = UIBezierPath(roundedRect: btnRect, cornerRadius: btnH * 0.3)
        chromeFill(btn, from: CGPoint(x: btnRect.minX, y: 0), to: CGPoint(x: btnRect.maxX, y: 0))
        // Knurling on the button.
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(white: 0.4, alpha: 0.6).cgColor)
        ctx.setLineWidth(0.5)
        var x = btnRect.minX + btnW * 0.12
        while x < btnRect.maxX - btnW * 0.1 {
            ctx.move(to: CGPoint(x: x, y: btnRect.minY + 1.5))
            ctx.addLine(to: CGPoint(x: x, y: btnRect.maxY - 1.5))
            x += max(1.5, btnW / 9)
        }
        ctx.strokePath()
        ctx.restoreGState()

        // Chrome case with a soft drop shadow.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor(white: 0, alpha: 0.35).cgColor)
        ctx.setFillColor(UIColor(white: 0.6, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
        ctx.restoreGState()
        let casePath = UIBezierPath(ovalIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
        chromeFill(casePath, from: CGPoint(x: c.x - R, y: c.y - R), to: CGPoint(x: c.x + R, y: c.y + R))

        // Inner bevel, then white face.
        let bevel = UIBezierPath(ovalIn: CGRect(x: c.x - r - 1.5, y: c.y - r - 1.5, width: (r + 1.5) * 2, height: (r + 1.5) * 2))
        chromeFill(bevel, from: CGPoint(x: c.x + r, y: c.y + r), to: CGPoint(x: c.x - r, y: c.y - r))
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.clip()
        let faceColors = [UIColor.white.cgColor, UIColor(white: 0.9, alpha: 1).cgColor] as CFArray
        let faceGradient = CGGradient(colorsSpace: space, colors: faceColors, locations: [0.6, 1])!
        ctx.drawRadialGradient(faceGradient, startCenter: CGPoint(x: c.x, y: c.y - r * 0.2), startRadius: 0,
                               endCenter: c, endRadius: r, options: .drawsAfterEndLocation)
        ctx.restoreGState()

        // 60 second markings, heavier every 5, numerals every 10 when there's room.
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(white: 0.1, alpha: 1).cgColor)
        ctx.setLineCap(.butt)
        for i in 0..<60 {
            let a = CGFloat(i) / 60 * 2 * .pi - .pi / 2
            let major = i % 5 == 0
            let inner = r * (major ? 0.8 : 0.88)
            ctx.setLineWidth(major ? max(1, r * 0.035) : max(0.5, r * 0.015))
            ctx.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
            ctx.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.96, y: c.y + sin(a) * r * 0.96))
            ctx.strokePath()
        }
        ctx.restoreGState()
        if r >= 34 {
            let font = UIFont(name: "Helvetica-Bold", size: max(6, r * 0.14))!
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(white: 0.15, alpha: 1)]
            for n in stride(from: 10, through: 60, by: 10) {
                let a = CGFloat(n) / 60 * 2 * .pi - .pi / 2
                let s = "\(n)" as NSString
                let size = s.size(withAttributes: attrs)
                let p = CGPoint(x: c.x + cos(a) * r * 0.64, y: c.y + sin(a) * r * 0.64)
                s.draw(at: CGPoint(x: p.x - size.width / 2, y: p.y - size.height / 2), withAttributes: attrs)
            }
        }

        // Minute subdial (30-minute counter).
        let sc = subdialCenter, sr = subdialRadius
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(white: 0.45, alpha: 1).cgColor)
        ctx.setLineWidth(0.6)
        ctx.strokeEllipse(in: CGRect(x: sc.x - sr, y: sc.y - sr, width: sr * 2, height: sr * 2))
        for i in 0..<6 {
            let a = CGFloat(i) / 6 * 2 * .pi - .pi / 2
            ctx.move(to: CGPoint(x: sc.x + cos(a) * sr * 0.7, y: sc.y + sin(a) * sr * 0.7))
            ctx.addLine(to: CGPoint(x: sc.x + cos(a) * sr, y: sc.y + sin(a) * sr))
        }
        ctx.strokePath()
        ctx.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor)
        let pin = max(1, sr * 0.15)
        ctx.fillEllipse(in: CGRect(x: sc.x - pin, y: sc.y - pin, width: pin * 2, height: pin * 2))
        ctx.restoreGState()

        // Glass highlight across the top of the face.
        ctx.saveGState()
        let glass = UIBezierPath(ovalIn: CGRect(x: c.x - r * 0.8, y: c.y - r * 0.95, width: r * 1.6, height: r * 0.9))
        ctx.addPath(glass.cgPath)
        ctx.clip()
        let glassColors = [UIColor(white: 1, alpha: 0.35).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
        let glassGradient = CGGradient(colorsSpace: space, colors: glassColors, locations: [0, 1])!
        ctx.drawLinearGradient(glassGradient, start: CGPoint(x: c.x, y: c.y - r), end: CGPoint(x: c.x, y: c.y - r * 0.05), options: [])
        ctx.restoreGState()
    }
}
