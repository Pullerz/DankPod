//
//  ClocksViewController.swift
//  Classic
//

import UIKit

/// Extras ▸ Clock — the 5G iPod world clock list.
class ClocksViewController: UIViewController, ClickWheelProtocol {
    let tableView = UITableView()
    var counter: Int = 0
    private var hasSetupUI = false
    private var tickTimer: Timer?

    static let rowHeight: CGFloat = 46

    private var clocks: [WorldClock] { WorldClockStore.shared.clocks }
    private var rowCount: Int { clocks.count + 1 }   // + "New Clock"

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Clock"
        counter = max(0, min(counter, rowCount - 1))
        tableView.reloadData()
        selectCurrent(scroll: true)
        startTicking()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func setupUI() {
        guard !hasSetupUI else { return }
        hasSetupUI = true
        view.backgroundColor = .white
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .white
    }

    private func selectCurrent(scroll: Bool) {
        guard rowCount > 0 else { return }
        let ip = IndexPath(row: counter, section: 0)
        tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
        if scroll { tableView.scrollToRow(at: ip, at: .none, animated: false) }
    }

    // MARK: Ticking

    private func startTicking() {
        tickTimer?.invalidate()
        refreshVisibleRows()
        // Fire on whole-second boundaries so all clocks flip together.
        let next = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 1)
        let timer = Timer(fire: next, interval: 1, repeats: true) { [weak self] _ in
            self?.refreshVisibleRows()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func refreshVisibleRows() {
        let now = Date()
        for case let cell as ClockRowCell in tableView.visibleCells {
            cell.refresh(at: now)
        }
    }

    // MARK: ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if rotationDirection == .CLOCKWISE {
            guard counter < rowCount - 1 else { return }
            counter += 1
        } else {
            guard counter > 0 else { return }
            counter -= 1
        }
        selectCurrent(scroll: true)
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
        guard pressure == .NORMAL else { return }
        if counter < clocks.count {
            navigationController?.pushViewController(ClockDetailViewController(index: counter), animated: true)
        } else {
            navigationController?.pushViewController(ClockCityPickerViewController(mode: .add), animated: true)
        }
    }
}

extension ClocksViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rowCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = ClockRowCell()
        cell.selectionStyle = .none
        if indexPath.row < clocks.count {
            cell.configure(clock: clocks[indexPath.row])
        } else {
            cell.configureNewClock()
        }
        cell.refresh(at: Date())
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        ClocksViewController.rowHeight
    }
}

// MARK: - Row

/// A rich two-line clock row built on CustomTableViewCell so the selection gradient,
/// chevron and fonts match every other iPod list.
final class ClockRowCell: CustomTableViewCell {
    let clockView = AnalogClockView()
    private let timeLabel = UILabel()
    private let cityLabel = UILabel()
    private let weekdayLabel = UILabel()
    private let dateLabel = UILabel()
    private let newClockLabel = UILabel()
    private var clock: WorldClock?

    override init() {
        super.init()
        label.isHidden = true

        clockView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(clockView)

        timeLabel.font = UIFont(name: "Helvetica-Bold", size: 15)
        cityLabel.font = UIFont(name: "Helvetica-Bold", size: 11)
        weekdayLabel.font = UIFont(name: "Helvetica-Bold", size: 12)
        dateLabel.font = UIFont(name: "Helvetica", size: 11)
        newClockLabel.font = UIFont(name: "Helvetica-Bold", size: 15)
        newClockLabel.text = "New Clock"
        weekdayLabel.textAlignment = .right
        dateLabel.textAlignment = .right
        for l in [cityLabel, weekdayLabel, dateLabel] {
            l.lineBreakMode = .byTruncatingTail
        }

        let left = UIStackView(arrangedSubviews: [timeLabel, cityLabel])
        left.axis = .vertical
        left.spacing = 1
        let right = UIStackView(arrangedSubviews: [weekdayLabel, dateLabel])
        right.axis = .vertical
        right.alignment = .trailing
        right.spacing = 2
        for v in [left, right, newClockLabel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }
        right.setContentCompressionResistancePriority(.required, for: .horizontal)
        right.setContentHuggingPriority(.required, for: .horizontal)
        weekdayLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            clockView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 8),
            clockView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            clockView.widthAnchor.constraint(equalToConstant: 38),
            clockView.heightAnchor.constraint(equalToConstant: 38),

            left.leftAnchor.constraint(equalTo: clockView.rightAnchor, constant: 8),
            left.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            left.rightAnchor.constraint(lessThanOrEqualTo: right.leftAnchor, constant: -6),

            right.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -4),
            right.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            newClockLabel.leftAnchor.constraint(equalTo: clockView.rightAnchor, constant: 8),
            newClockLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            newClockLabel.rightAnchor.constraint(lessThanOrEqualTo: contentView.rightAnchor, constant: -4),
        ])
        applyColors(selected: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(clock: WorldClock) {
        self.clock = clock
        clockView.faceStyle = .automatic
        clockView.timeZone = clock.timeZone
        cityLabel.text = clock.city
        newClockLabel.isHidden = true
        [timeLabel, cityLabel, weekdayLabel, dateLabel].forEach { $0.isHidden = false }
    }

    func configureNewClock() {
        clock = nil
        clockView.faceStyle = .placeholder
        newClockLabel.isHidden = false
        [timeLabel, cityLabel, weekdayLabel, dateLabel].forEach { $0.isHidden = true }
    }

    func refresh(at date: Date) {
        guard let clock = clock else { return }
        let tz = clock.timeZone
        timeLabel.text = WorldClockStore.timeString(date, in: tz)
        weekdayLabel.text = WorldClockStore.weekdayString(date, in: tz)
        dateLabel.text = WorldClockStore.shortDateString(date, in: tz)
        clockView.update(to: date)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        applyColors(selected: selected)
    }

    private func applyColors(selected: Bool) {
        let primary: UIColor = selected ? .white : .black
        let secondary: UIColor = selected ? UIColor(white: 1, alpha: 0.92) : UIColor(white: 0.3, alpha: 1)
        timeLabel.textColor = primary
        weekdayLabel.textColor = primary
        newClockLabel.textColor = primary
        cityLabel.textColor = secondary
        dateLabel.textColor = secondary
    }
}
