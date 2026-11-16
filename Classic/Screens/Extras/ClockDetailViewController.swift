//
//  ClockDetailViewController.swift
//  Classic
//

import UIKit

/// Full-screen world clock (iPod classic style): a big analog clock with a sweeping
/// second hand over a deep-blue world grid. Wheel / next / prev cycle clocks; center
/// opens the action list (Change City / Delete / Cancel).
class ClockDetailViewController: UIViewController, ClickWheelProtocol {

    var index: Int

    private let backgroundView = WorldGridBackgroundView()
    private let contentView = UIView()
    private let clockView = AnalogClockView()
    private let cityLabel = UILabel()
    private let timeLabel = UILabel()
    private let dateLabel = UILabel()
    private let dotsView = UIStackView()

    private var displayLink: CADisplayLink?
    private var lastLabelSecond: Int = -1
    private var hasSetupUI = false

    // Action overlay
    private enum OverlayState { case none, actions, confirmDelete }
    private var overlayState: OverlayState = .none
    private var overlayItems: [String] = []
    private var overlayCounter = 0
    private var overlayView: ClockActionOverlayView?

    private var store: WorldClockStore { WorldClockStore.shared }
    private var clock: WorldClock? { store.clocks.indices.contains(index) ? store.clocks[index] : nil }

    init(index: Int) {
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        index = max(0, min(index, store.clocks.count - 1))
        dismissOverlay()
        showClock()
        startDisplayLink()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        displayLink?.invalidate()
        displayLink = nil
        syncListSelection()
    }

    private func setupUI() {
        guard !hasSetupUI else { return }
        hasSetupUI = true
        view.clipsToBounds = true
        view.backgroundColor = UIColor(red: 10/255, green: 34/255, blue: 86/255, alpha: 1)

        backgroundView.frame = view.bounds
        backgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backgroundView)

        contentView.frame = view.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(contentView)

        clockView.faceStyle = .automatic
        clockView.showsSecondHand = true
        contentView.addSubview(clockView)

        cityLabel.font = UIFont(name: "Helvetica-Bold", size: 22)
        timeLabel.font = UIFont(name: "Helvetica-Bold", size: 30)
        dateLabel.font = UIFont(name: "Helvetica-Bold", size: 12)
        cityLabel.textColor = .white
        timeLabel.textColor = .white
        dateLabel.textColor = UIColor(red: 0.78, green: 0.87, blue: 1, alpha: 1)
        dateLabel.numberOfLines = 2
        for l in [cityLabel, timeLabel, dateLabel] {
            l.adjustsFontSizeToFitWidth = true
            l.minimumScaleFactor = 0.6
            l.layer.shadowColor = UIColor.black.cgColor
            l.layer.shadowOpacity = 0.55
            l.layer.shadowRadius = 1.5
            l.layer.shadowOffset = CGSize(width: 0, height: 1)
            contentView.addSubview(l)
        }

        dotsView.axis = .horizontal
        dotsView.spacing = 6
        dotsView.alignment = .center
        view.addSubview(dotsView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        let side = floor(min(b.height * 0.74, b.width * 0.46))
        clockView.frame = CGRect(x: floor(b.width * 0.05), y: floor((b.height - side) / 2) - 4, width: side, height: side)

        let textX = clockView.frame.maxX + 14
        let textW = max(40, b.width - textX - 14)
        let midY = clockView.frame.midY
        cityLabel.frame = CGRect(x: textX, y: midY - 52, width: textW, height: 28)
        timeLabel.frame = CGRect(x: textX, y: midY - 22, width: textW, height: 36)
        dateLabel.frame = CGRect(x: textX, y: midY + 18, width: textW, height: 34)

        let dotsSize = dotsView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        dotsView.frame = CGRect(x: (b.width - dotsSize.width) / 2, y: b.height - 16, width: dotsSize.width, height: 8)
        overlayView?.frame = b
    }

    // MARK: Content

    private func showClock() {
        guard let clock = clock else { return }
        AppDelegate.baseVC.navBarTitle = clock.city
        clockView.timeZone = clock.timeZone
        cityLabel.text = clock.city
        lastLabelSecond = -1
        tick()
        rebuildDots()
    }

    private func rebuildDots() {
        dotsView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let count = store.clocks.count
        dotsView.isHidden = count < 2
        for i in 0..<count {
            let d = UIView()
            d.translatesAutoresizingMaskIntoConstraints = false
            d.widthAnchor.constraint(equalToConstant: 6).isActive = true
            d.heightAnchor.constraint(equalToConstant: 6).isActive = true
            d.layer.cornerRadius = 3
            d.backgroundColor = UIColor(white: 1, alpha: i == index ? 0.95 : 0.3)
            dotsView.addArrangedSubview(d)
        }
        view.setNeedsLayout()
    }

    private func startDisplayLink() {
        displayLink?.invalidate()
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func tick() {
        guard let clock = clock else { return }
        let now = Date()
        clockView.update(to: now)
        let second = Int(now.timeIntervalSince1970)
        if second != lastLabelSecond {
            lastLabelSecond = second
            let tz = clock.timeZone
            timeLabel.text = WorldClockStore.timeString(now, in: tz)
            dateLabel.text = WorldClockStore.fullDateString(now, in: tz)
        }
    }

    private func cycle(by delta: Int) {
        let count = store.clocks.count
        guard count > 1 else { return }
        index = ((index + delta) % count + count) % count
        UIView.transition(with: contentView, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction], animations: {
            self.showClock()
        })
    }

    /// Keep the list's selection on whichever clock we ended up viewing.
    private func syncListSelection() {
        guard let list = navigationController?.viewControllers.last(where: { $0 is ClocksViewController }) as? ClocksViewController else { return }
        list.counter = max(0, min(index, store.clocks.count - 1))
    }

    // MARK: Action overlay

    private func presentActions() {
        overlayState = .actions
        overlayItems = store.canDelete ? ["Change City", "Delete", "Cancel"] : ["Change City", "Cancel"]
        overlayCounter = 0
        showOverlay(title: clock?.city ?? "Clock")
    }

    private func presentDeleteConfirm() {
        overlayState = .confirmDelete
        overlayItems = ["Delete", "Cancel"]
        overlayCounter = 1   // default to the safe choice
        showOverlay(title: "Delete \(clock?.city ?? "Clock")?")
    }

    private func showOverlay(title: String) {
        let animate = overlayView == nil
        overlayView?.removeFromSuperview()
        let overlay = ClockActionOverlayView(frame: view.bounds, title: title, items: overlayItems)
        overlay.select(overlayCounter)
        view.addSubview(overlay)
        overlayView = overlay
        if animate {
            overlay.alpha = 0
            UIView.animate(withDuration: 0.15) { overlay.alpha = 1 }
        }
    }

    private func dismissOverlay() {
        overlayState = .none
        guard let overlay = overlayView else { return }
        overlayView = nil
        UIView.animate(withDuration: 0.15, animations: { overlay.alpha = 0 }) { _ in overlay.removeFromSuperview() }
    }

    private func performOverlayAction() {
        guard overlayItems.indices.contains(overlayCounter) else { return }
        let item = overlayItems[overlayCounter]
        switch (overlayState, item) {
        case (.actions, "Change City"):
            dismissOverlay()
            navigationController?.pushViewController(ClockCityPickerViewController(mode: .replace(index: index)), animated: true)
        case (.actions, "Delete"):
            presentDeleteConfirm()
        case (.confirmDelete, "Delete"):
            dismissOverlay()
            if store.remove(at: index) {
                index = min(index, store.clocks.count - 1)
                UIView.transition(with: contentView, duration: 0.25, options: .transitionCrossDissolve, animations: {
                    self.showClock()
                })
            }
        default:
            dismissOverlay()
        }
    }

    // MARK: ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if overlayState != .none {
            if rotationDirection == .CLOCKWISE {
                overlayCounter = min(overlayCounter + 1, overlayItems.count - 1)
            } else {
                overlayCounter = max(overlayCounter - 1, 0)
            }
            overlayView?.select(overlayCounter)
            return
        }
        cycle(by: rotationDirection == .CLOCKWISE ? 1 : -1)
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL { AppDelegate.music.playPause() }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, overlayState == .none else { return }
        cycle(by: 1)
    }

    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, overlayState == .none else { return }
        cycle(by: -1)
    }

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            if overlayState != .none {
                dismissOverlay()
            } else {
                navigationController?.popViewController(animated: true)
            }
        } else if pressure == .FORCE {
            navigationController?.popToRootViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        if overlayState == .none {
            presentActions()
        } else {
            performOverlayAction()
        }
    }
}

// MARK: - Display link proxy (avoids the CADisplayLink → target retain cycle)

private final class DisplayLinkProxy: NSObject {
    weak var target: ClockDetailViewController?
    init(_ target: ClockDetailViewController) { self.target = target; super.init() }
    @objc func step(_ link: CADisplayLink) {
        if let target = target {
            target.tick()
        } else {
            link.invalidate()
        }
    }
}

// MARK: - Action list overlay

/// A dimmed backdrop with a small iPod list panel (header + CustomTableViewCell rows).
private final class ClockActionOverlayView: UIView, UITableViewDataSource, UITableViewDelegate {
    private let items: [String]
    private let tableView = UITableView()
    private let rowHeight: CGFloat = 30
    private let headerHeight: CGFloat = 26

    init(frame: CGRect, title: String, items: [String]) {
        self.items = items
        super.init(frame: frame)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = UIColor(white: 0, alpha: 0.45)

        let width = min(260, frame.width - 40)
        let height = headerHeight + rowHeight * CGFloat(items.count)
        let panel = UIView(frame: CGRect(x: (frame.width - width) / 2, y: (frame.height - height) / 2, width: width, height: height))
        panel.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        panel.backgroundColor = .white
        panel.layer.cornerRadius = 6
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.5
        panel.layer.shadowRadius = 8
        panel.layer.shadowOffset = CGSize(width: 0, height: 3)
        addSubview(panel)

        let clip = UIView(frame: panel.bounds)
        clip.layer.cornerRadius = 6
        clip.clipsToBounds = true
        clip.layer.borderColor = UIColor(white: 0.45, alpha: 1).cgColor
        clip.layer.borderWidth = 1
        panel.addSubview(clip)

        // Header: the silvery iPod title-bar gradient.
        let header = UIView(frame: CGRect(x: 0, y: 0, width: width, height: headerHeight))
        let g = CAGradientLayer()
        g.frame = header.bounds
        g.colors = [UIColor(white: 0.98, alpha: 1), UIColor(white: 0.78, alpha: 1)].map { $0.cgColor }
        header.layer.addSublayer(g)
        let line = CALayer()
        line.frame = CGRect(x: 0, y: headerHeight - 1, width: width, height: 1)
        line.backgroundColor = UIColor(white: 0.55, alpha: 1).cgColor
        header.layer.addSublayer(line)
        let titleLabel = UILabel(frame: header.bounds.insetBy(dx: 8, dy: 0))
        titleLabel.text = title
        titleLabel.font = UIFont(name: "Helvetica-Bold", size: 13)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .black
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        header.addSubview(titleLabel)
        clip.addSubview(header)

        tableView.frame = CGRect(x: 0, y: headerHeight, width: width, height: rowHeight * CGFloat(items.count))
        tableView.isScrollEnabled = false
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        clip.addSubview(tableView)
        tableView.reloadData()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(_ row: Int) {
        guard items.indices.contains(row) else { return }
        tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = items[indexPath.row]
        cell.accessoryType = .none
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { rowHeight }
}

// MARK: - Background

/// Deep-blue gradient with a faint Mollweide-style world graticule, drawn in code.
private final class WorldGridBackgroundView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
        isOpaque = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let b = bounds
        let space = CGColorSpaceCreateDeviceRGB()

        // Base gradient.
        let base = [UIColor(red: 34/255, green: 84/255, blue: 168/255, alpha: 1),
                    UIColor(red: 14/255, green: 44/255, blue: 110/255, alpha: 1),
                    UIColor(red: 5/255, green: 18/255, blue: 58/255, alpha: 1)]
        if let g = CGGradient(colorsSpace: space, colors: base.map { $0.cgColor } as CFArray, locations: [0, 0.55, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: b.midX, y: b.minY), end: CGPoint(x: b.midX, y: b.maxY), options: [])
        }

        // Mollweide-style oval graticule, a touch wider than the screen.
        let a = b.width * 0.56                    // semi-major
        let bb = min(a / 2, b.height * 0.62)      // semi-minor
        let c = CGPoint(x: b.midX, y: b.midY)
        let oval = CGRect(x: c.x - a, y: c.y - bb, width: a * 2, height: bb * 2)

        // Soft "ocean" glow inside the oval.
        ctx.saveGState()
        ctx.addEllipse(in: oval)
        ctx.clip()
        let glow = [UIColor(red: 0.45, green: 0.7, blue: 1, alpha: 0.16), UIColor(red: 0.45, green: 0.7, blue: 1, alpha: 0.03)]
        if let g = CGGradient(colorsSpace: space, colors: glow.map { $0.cgColor } as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: a, options: [])
        }

        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.11).cgColor)
        ctx.setLineWidth(0.75)
        // Meridians every 30°: concentric half-ellipses.
        for lon in stride(from: 30, through: 150, by: 30) {
            let rx = a * CGFloat(lon) / 180
            ctx.strokeEllipse(in: CGRect(x: c.x - rx, y: c.y - bb, width: rx * 2, height: bb * 2))
        }
        ctx.move(to: CGPoint(x: c.x, y: c.y - bb))
        ctx.addLine(to: CGPoint(x: c.x, y: c.y + bb))
        ctx.strokePath()
        // Parallels every 20°.
        for lat in stride(from: -60, through: 60, by: 20) {
            let y = c.y - bb * CGFloat(sin(Double(lat) * .pi / 180))
            ctx.move(to: CGPoint(x: oval.minX, y: y))
            ctx.addLine(to: CGPoint(x: oval.maxX, y: y))
        }
        ctx.strokePath()
        // Equator, slightly brighter.
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.18).cgColor)
        ctx.move(to: CGPoint(x: oval.minX, y: c.y))
        ctx.addLine(to: CGPoint(x: oval.maxX, y: c.y))
        ctx.strokePath()
        ctx.restoreGState()

        // Oval outline.
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.2).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: oval)

        // Top sheen, like the glossy iPod screens.
        let sheen = [UIColor(white: 1, alpha: 0.14), UIColor(white: 1, alpha: 0)]
        if let g = CGGradient(colorsSpace: space, colors: sheen.map { $0.cgColor } as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: b.midX, y: b.minY), end: CGPoint(x: b.midX, y: b.height * 0.45), options: [])
        }
    }
}
