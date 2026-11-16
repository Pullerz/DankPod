//
//  CalendarsViewController.swift
//  Classic
//
//  Extras › Calendars. Read-only view of the iPhone's calendars (EventKit), drawn
//  the way the iPod classic did: a calendar list, then a month grid, then a day's
//  events, then an event card.
//

import UIKit
import EventKit

// MARK: - Shared iPod message screen (used by Calendars and Contacts)

/// A centred, iPod-style message: bold title over a smaller grey explanation.
final class PIMMessageView: UIView {
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()

    init() {
        super.init(frame: .zero)
        backgroundColor = .white

        titleLabel.font = UIFont(name: "Helvetica-Bold", size: 17)
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        bodyLabel.font = UIFont(name: "Helvetica-Bold", size: 13)
        bodyLabel.textColor = UIColor(white: 0.45, alpha: 1)
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func set(title: String, message: String?) {
        titleLabel.text = title
        bodyLabel.text = message
        bodyLabel.isHidden = (message ?? "").isEmpty
    }
}

/// Selects `row` in an iPod list and keeps it on screen.
func pimSelectRow(_ tableView: UITableView, _ row: Int) {
    guard row >= 0, row < tableView.numberOfRows(inSection: 0) else { return }
    let ip = IndexPath(row: row, section: 0)
    tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
    tableView.scrollToRow(at: ip, at: .none, animated: false)
}

// MARK: - Calendar list

class CalendarsViewController: UIViewController, ClickWheelProtocol {
    /// One store for the whole Calendars feature.
    static let eventStore = EKEventStore()

    private enum State { case loading, denied, ready }

    private let tableView = UITableView()
    private let messageView = PIMMessageView()
    private var calendars: [EKCalendar] = []
    private var counter = 0
    private var state: State = .loading

    private var store: EKEventStore { CalendarsViewController.eventStore }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .white
        view.addSubview(tableView)

        messageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageView)

        for v in [tableView, messageView] as [UIView] {
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: view.topAnchor),
                v.leftAnchor.constraint(equalTo: view.leftAnchor),
                v.rightAnchor.constraint(equalTo: view.rightAnchor),
                v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        apply(.loading)
        checkAccess()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Calendars"
        if state == .ready {
            reloadCalendars()
        } else if state == .denied {
            // The user may have changed the permission in Settings meanwhile.
            checkAccess()
        }
    }

    // MARK: Access

    private func checkAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            apply(.ready)
        case .notDetermined:
            apply(.loading)
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.apply(granted ? .ready : .denied)
                }
            }
        default:
            apply(.denied)
        }
    }

    private func apply(_ newState: State) {
        state = newState
        switch newState {
        case .loading:
            tableView.isHidden = true
            messageView.isHidden = false
            messageView.set(title: "Calendars", message: "Loading…")
        case .denied:
            tableView.isHidden = true
            messageView.isHidden = false
            messageView.set(title: "Calendars Unavailable",
                            message: "To see your calendars here, allow Classic Full Access in Settings › Privacy & Security › Calendars.")
        case .ready:
            tableView.isHidden = false
            messageView.isHidden = true
            reloadCalendars()
        }
    }

    private func reloadCalendars() {
        calendars = store.calendars(for: .event).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        counter = min(counter, calendars.count) // row 0 is "All Calendars"
        tableView.reloadData()
        tableView.layoutIfNeeded()
        pimSelectRow(tableView, counter)
    }

    // MARK: Click wheel

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        guard state == .ready else { return }
        let count = calendars.count + 1
        if rotationDirection == .CLOCKWISE {
            if counter < count - 1 { counter += 1; pimSelectRow(tableView, counter) }
        } else {
            if counter > 0 { counter -= 1; pimSelectRow(tableView, counter) }
        }
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL { AppDelegate.music.playPause() }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {}
    func previousSongPressed(pressure: ClickWheelTouchPressure) {}

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            navigationController?.popViewController(animated: true)
        } else if pressure == .FORCE {
            navigationController?.popToRootViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, state == .ready else { return }
        let month: CalendarMonthViewController
        if counter == 0 || counter - 1 >= calendars.count {
            month = CalendarMonthViewController(store: store, calendars: nil, title: "All Calendars")
        } else {
            let cal = calendars[counter - 1]
            month = CalendarMonthViewController(store: store, calendars: [cal], title: cal.title)
        }
        navigationController?.pushViewController(month, animated: true)
    }
}

extension CalendarsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        state == .ready ? calendars.count + 1 : 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = PIMCalendarCell()
        if indexPath.row == 0 {
            cell.label.text = "All Calendars"
            cell.dotColor = nil
        } else {
            let cal = calendars[indexPath.row - 1]
            cell.label.text = cal.title
            cell.dotColor = UIColor(cgColor: cal.cgColor)
        }
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 30 }
}

/// iPod list row with a small glossy dot in the calendar's colour before the name.
private final class PIMCalendarCell: CustomTableViewCell {
    private let dot = UIView()
    private let shine = CAGradientLayer()

    var dotColor: UIColor? {
        didSet {
            dot.isHidden = dotColor == nil
            dot.backgroundColor = dotColor
        }
    }

    override init() {
        super.init()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.layer.cornerRadius = 5
        dot.layer.borderWidth = 0.5
        dot.layer.borderColor = UIColor(white: 0, alpha: 0.35).cgColor
        dot.clipsToBounds = true
        shine.colors = [UIColor(white: 1, alpha: 0.6).cgColor, UIColor(white: 1, alpha: 0).cgColor]
        shine.startPoint = CGPoint(x: 0.5, y: 0)
        shine.endPoint = CGPoint(x: 0.5, y: 0.7)
        shine.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        dot.layer.addSublayer(shine)
        contentView.addSubview(dot)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
            dot.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            dot.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 13),
        ])
        // Shift the name right to make room for the dot (all rows, so names line up).
        for c in contentView.constraints where (c.firstItem as? UILabel) === label && c.firstAttribute == .left {
            c.constant = 30
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        dot.layer.borderColor = (selected ? UIColor(white: 1, alpha: 0.8) : UIColor(white: 0, alpha: 0.35)).cgColor
    }
}

// MARK: - Month view

final class CalendarMonthViewController: UIViewController, ClickWheelProtocol {
    private let store: EKEventStore
    private let calendars: [EKCalendar]?
    private let titleText: String
    private let grid = PIMMonthGridView()
    private var cal: Calendar { Calendar.current }
    private var selectedDate: Date
    private var fetchGeneration = 0

    init(store: EKEventStore, calendars: [EKCalendar]?, title: String) {
        self.store = store
        self.calendars = calendars
        self.titleText = title
        self.selectedDate = Calendar.current.startOfDay(for: Date())
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        grid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor),
            grid.leftAnchor.constraint(equalTo: view.leftAnchor),
            grid.rightAnchor.constraint(equalTo: view.rightAnchor),
            grid.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        grid.selectedDate = selectedDate
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = titleText
        grid.today = cal.startOfDay(for: Date())
        grid.selectedDate = selectedDate
        loadMarkers()
    }

    private func select(_ date: Date) {
        let day = cal.startOfDay(for: date)
        let monthChanged = !cal.isDate(day, equalTo: selectedDate, toGranularity: .month)
        selectedDate = day
        if monthChanged { grid.eventDays = [] }
        grid.selectedDate = day
        if monthChanged { loadMarkers() }
    }

    /// Finds which days of the displayed month have events (off the main thread).
    private func loadMarkers() {
        guard let month = cal.dateInterval(of: .month, for: selectedDate) else { return }
        fetchGeneration += 1
        let generation = fetchGeneration
        let store = self.store
        let calendars = self.calendars
        let calendar = cal
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let predicate = store.predicateForEvents(withStart: month.start, end: month.end, calendars: calendars)
            var days = Set<Int>()
            for event in store.events(matching: predicate) {
                guard let start = event.startDate, let end = event.endDate else { continue }
                // Treat the end as exclusive so an event ending at midnight doesn't mark the next day.
                let lastInstant = end > start ? end.addingTimeInterval(-1) : start
                var day = calendar.startOfDay(for: max(start, month.start))
                let stop = min(lastInstant, month.end.addingTimeInterval(-1))
                while day <= stop {
                    days.insert(calendar.component(.day, from: day))
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
            DispatchQueue.main.async {
                guard let self = self, generation == self.fetchGeneration else { return }
                self.grid.eventDays = days
            }
        }
    }

    // MARK: Click wheel

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        let delta = rotationDirection == .CLOCKWISE ? 1 : -1
        if let d = cal.date(byAdding: .day, value: delta, to: selectedDate) { select(d) }
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL { AppDelegate.music.playPause() }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        if let d = cal.date(byAdding: .month, value: 1, to: selectedDate) { select(d) }
    }

    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        if let d = cal.date(byAdding: .month, value: -1, to: selectedDate) { select(d) }
    }

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            navigationController?.popViewController(animated: true)
        } else if pressure == .FORCE {
            navigationController?.popToRootViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        let vc = CalendarEventsViewController(store: store, calendars: calendars, day: selectedDate)
        navigationController?.pushViewController(vc, animated: true)
    }
}

/// The iPod month grid: silver month header, weekday initials, day cells.
final class PIMMonthGridView: UIView {
    var selectedDate = Date() { didSet { setNeedsDisplay() } }
    var today = Calendar.current.startOfDay(for: Date()) { didSet { setNeedsDisplay() } }
    /// Day-of-month numbers in the selected month that have events.
    var eventDays = Set<Int>() { didSet { if eventDays != oldValue { setNeedsDisplay() } } }

    private let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        contentMode = .redraw
        isOpaque = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cal = Calendar.current
        let b = bounds
        let scale = window?.screen.scale ?? traitCollection.displayScale
        let hair = 1 / max(scale, 1)
        let headerH: CGFloat = 26
        let weekH: CGFloat = 18
        let space = CGColorSpaceCreateDeviceRGB()

        UIColor.white.setFill()
        ctx.fill(b)

        // Header: silver gloss bar with the month name.
        let headerRect = CGRect(x: 0, y: 0, width: b.width, height: headerH)
        if let g = CGGradient(colorsSpace: space,
                              colors: [UIColor(white: 0.97, alpha: 1).cgColor,
                                       UIColor(white: 0.86, alpha: 1).cgColor,
                                       UIColor(white: 0.78, alpha: 1).cgColor] as CFArray,
                              locations: [0, 0.5, 1]) {
            ctx.saveGState()
            ctx.clip(to: headerRect)
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: headerH), options: [])
            ctx.restoreGState()
        }
        UIColor(white: 0.55, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: headerH - hair, width: b.width, height: hair))
        drawCentered(headerFormatter.string(from: selectedDate),
                     in: headerRect,
                     font: UIFont(name: "Helvetica-Bold", size: 15)!,
                     color: .black,
                     shadow: UIColor(white: 1, alpha: 0.8))

        // Weekday initials.
        let weekRect = CGRect(x: 0, y: headerH, width: b.width, height: weekH)
        UIColor(white: 0.93, alpha: 1).setFill()
        ctx.fill(weekRect)
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let cellW = b.width / 7
        for col in 0..<7 {
            let idx = (cal.firstWeekday - 1 + col) % 7
            let r = CGRect(x: CGFloat(col) * cellW, y: headerH, width: cellW, height: weekH)
            drawCentered(symbols[idx], in: r, font: UIFont(name: "Helvetica-Bold", size: 10)!,
                         color: UIColor(white: 0.35, alpha: 1), shadow: nil)
        }
        UIColor(white: 0.7, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: headerH + weekH - hair, width: b.width, height: hair))

        // Day grid.
        guard let month = cal.dateInterval(of: .month, for: selectedDate),
              let daysInMonth = cal.range(of: .day, in: .month, for: selectedDate)?.count else { return }
        let firstWeekday = cal.component(.weekday, from: month.start)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let rows = Int(ceil(Double(leading + daysInMonth) / 7.0))
        let gridTop = headerH + weekH
        let cellH = (b.height - gridTop) / CGFloat(rows)
        let selectedDay = cal.component(.day, from: selectedDate)
        let todayDay: Int? = cal.isDate(today, equalTo: selectedDate, toGranularity: .month)
            ? cal.component(.day, from: today) : nil
        let numberFont = UIFont(name: "Helvetica-Bold", size: min(15, max(10, cellH * 0.42)))!

        func cellRect(_ i: Int) -> CGRect {
            let col = i % 7, row = i / 7
            let x0 = (CGFloat(col) * cellW).rounded(), x1 = (CGFloat(col + 1) * cellW).rounded()
            let y0 = (gridTop + CGFloat(row) * cellH).rounded(), y1 = (gridTop + CGFloat(row + 1) * cellH).rounded()
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }

        // Fills: out-of-month shading and the selection gradient.
        for i in 0..<(rows * 7) {
            let day = i - leading + 1
            let r = cellRect(i)
            if day < 1 || day > daysInMonth {
                UIColor(white: 0.95, alpha: 1).setFill()
                ctx.fill(r)
            } else if day == selectedDay,
                      let g = CGGradient(colorsSpace: space,
                                         colors: [UIColor.gradientLightBlue.cgColor, UIColor.gradientDarkBlue.cgColor] as CFArray,
                                         locations: [0, 1]) {
                ctx.saveGState()
                ctx.clip(to: r)
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
                ctx.restoreGState()
            }
        }

        // Grid lines.
        UIColor(white: 0.78, alpha: 1).setFill()
        for row in 1..<rows {
            let y = cellRect(row * 7).minY
            ctx.fill(CGRect(x: 0, y: y, width: b.width, height: hair))
        }
        for col in 1..<7 {
            let x = cellRect(col).minX
            ctx.fill(CGRect(x: x, y: gridTop, width: hair, height: b.height - gridTop))
        }

        // Numbers, event flags and today's outline.
        for i in 0..<(rows * 7) {
            let r = cellRect(i)
            let day = i - leading + 1
            let inMonth = day >= 1 && day <= daysInMonth
            let displayDay: Int
            if inMonth {
                displayDay = day
            } else if let d = cal.date(byAdding: .day, value: day - 1, to: month.start) {
                displayDay = cal.component(.day, from: d)
            } else { continue }
            let isSelected = inMonth && day == selectedDay
            let color: UIColor = isSelected ? .white : (inMonth ? .black : UIColor(white: 0.68, alpha: 1))
            drawCentered("\(displayDay)", in: r, font: numberFont, color: color,
                         shadow: isSelected ? UIColor(white: 0, alpha: 0.3) : nil)

            if inMonth && eventDays.contains(day) {
                // The iPod's little red flag in the top-right corner.
                let s = max(6, min(r.width, r.height) * 0.3)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: r.maxX - s, y: r.minY + hair))
                ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY + hair))
                ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY + hair + s))
                ctx.closePath()
                (isSelected ? UIColor(red: 1, green: 0.35, blue: 0.3, alpha: 1)
                            : UIColor(red: 0.85, green: 0.1, blue: 0.08, alpha: 1)).setFill()
                ctx.fillPath()
            }

            if inMonth, let t = todayDay, day == t {
                let outline = r.insetBy(dx: 1.5, dy: 1.5)
                ctx.setLineWidth(2)
                (isSelected ? UIColor.white : UIColor(white: 0.15, alpha: 1)).setStroke()
                ctx.stroke(outline)
            }
        }
    }

    private func drawCentered(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, shadow: UIColor?) {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let shadow = shadow {
            let s = NSShadow()
            s.shadowColor = shadow
            s.shadowOffset = CGSize(width: 0, height: shadow.cgColor.components?.first ?? 0 > 0.5 ? 1 : -1)
            s.shadowBlurRadius = 0
            attrs[.shadow] = s
        }
        let size = (text as NSString).size(withAttributes: attrs)
        let p = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (text as NSString).draw(at: p, withAttributes: attrs)
    }
}
