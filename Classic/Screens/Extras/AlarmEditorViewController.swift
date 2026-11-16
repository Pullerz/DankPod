//
//  AlarmEditorViewController.swift
//  Classic
//
//  iPod settings-style editor for one alarm, plus the time setter and the
//  delete confirmation. Every change is saved to AlarmStore immediately.
//

import UIKit

class AlarmEditorViewController: UIViewController, ClickWheelProtocol {

    private enum Row: CaseIterable {
        case enabled, time, repeatRule, alert, label, delete

        var title: String {
            switch self {
            case .enabled: return "Alarm"
            case .time: return "Time"
            case .repeatRule: return "Repeat"
            case .alert: return "Alerts"
            case .label: return "Label"
            case .delete: return "Delete Alarm"
            }
        }
    }

    private let alarmID: UUID
    private let rows = Row.allCases
    private let tableView = UITableView()
    private var counter = 0
    private var hasSetupUI = false

    private var alarm: Alarm? { AlarmStore.shared.alarm(id: alarmID) }

    init(alarmID: UUID) {
        self.alarmID = alarmID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Alarm"
        reload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The alarm may have been deleted elsewhere; nothing to edit.
        if alarm == nil { navigationController?.popViewController(animated: true) }
    }

    private func setupUI() {
        guard !hasSetupUI else { return }
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
        hasSetupUI = true
    }

    private func reload() {
        tableView.reloadData()
        guard counter < tableView.numberOfRows(inSection: 0) else { return }   // alarm deleted
        let ip = IndexPath(row: counter, section: 0)
        tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
        tableView.scrollToRow(at: ip, at: .none, animated: false)
    }

    private func value(for row: Row, alarm: Alarm) -> String {
        switch row {
        case .enabled: return alarm.enabled ? "On" : "Off"
        case .time: return alarm.timeString
        case .repeatRule:
            return alarm.repeatRule == .weekly ? "Weekly (\(alarm.repeatSummary.dropLast()))" : alarm.repeatRule.title
        case .alert: return alarm.alert.title
        case .label: return alarm.label
        case .delete: return ""
        }
    }

    private func modify(_ change: (inout Alarm) -> Void) {
        guard var a = alarm else { return }
        change(&a)
        AlarmStore.shared.update(a)
        reload()
    }

    // MARK: ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if rotationDirection == .CLOCKWISE {
            guard counter < rows.count - 1 else { return }
            counter += 1
        } else {
            guard counter > 0 else { return }
            counter -= 1
        }
        let ip = IndexPath(row: counter, section: 0)
        tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
        tableView.scrollToRow(at: ip, at: .none, animated: false)
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
        guard pressure == .NORMAL, let current = alarm, rows.indices.contains(counter) else { return }
        switch rows[counter] {
        case .enabled:
            modify { $0.enabled.toggle() }
        case .time:
            let setter = AlarmTimeSetterViewController(hour: current.hour, minute: current.minute)
            setter.onSave = { [weak self] hour, minute in
                self?.modify { $0.hour = hour; $0.minute = minute }
            }
            navigationController?.pushViewController(setter, animated: true)
        case .repeatRule:
            modify { a in
                let all = AlarmRepeat.allCases
                let idx = all.firstIndex(of: a.repeatRule) ?? 0
                a.repeatRule = all[(idx + 1) % all.count]
                if a.repeatRule == .weekly {
                    let next = AlarmStore.nextDate(hour: a.hour, minute: a.minute)
                    a.weekday = Calendar.current.component(.weekday, from: next)
                }
            }
        case .alert:
            modify { $0.alert = $0.alert == .beep ? .none : .beep }
        case .label:
            modify { a in
                let presets = Alarm.labelPresets
                let idx = presets.firstIndex(of: a.label) ?? -1
                a.label = presets[(idx + 1) % presets.count]
            }
        case .delete:
            navigationController?.pushViewController(AlarmDeleteConfirmViewController(alarmID: alarmID), animated: true)
        }
    }
}

extension AlarmEditorViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        alarm == nil ? 0 : rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        let cell = CustomSettingsTableViewCell()
        cell.selectionStyle = .none
        cell.label.text = row.title
        // Inline rows (center changes the value) have no chevron, like iPod Settings.
        cell.showChevron = (row == .time || row == .delete)
        if let alarm = alarm { cell.valueLabel.text = value(for: row, alarm: alarm) }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        30
    }
}

// MARK: - Time setter

/// One boxed field of the time setter (hour, minute or AM/PM).
private final class TimeFieldView: UIView {
    let label = UILabel()
    private let gradient = CAGradientLayer()

    var isActive = false { didSet { updateAppearance() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.insertSublayer(gradient, at: 0)
        gradient.cornerRadius = 6
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        label.font = GameStyle.font(bounds.height * 0.55)
    }

    private func updateAppearance() {
        if isActive {
            gradient.colors = [UIColor.gradientLightBlue.cgColor, UIColor.gradientDarkBlue.cgColor]
            layer.borderColor = UIColor.gradientDarkBlue.cgColor
            label.textColor = .white
        } else {
            gradient.colors = [UIColor.white.cgColor, UIColor(white: 0.88, alpha: 1).cgColor]
            layer.borderColor = UIColor(white: 0.65, alpha: 1).cgColor
            label.textColor = .black
        }
    }
}

/// iPod "Date & Time"-style setter: hour : minute AM/PM. The wheel changes the
/// highlighted field, center advances, and center on the last field saves.
/// Menu backs out without saving.
final class AlarmTimeSetterViewController: UIViewController, ClickWheelProtocol {
    var onSave: ((Int, Int) -> Void)?

    private var hour12: Int        // 1...12
    private var minute: Int        // 0...59
    private var isPM: Bool
    private var field = 0          // 0 hour, 1 minute, 2 AM/PM

    private let hourField = TimeFieldView()
    private let minuteField = TimeFieldView()
    private let ampmField = TimeFieldView()
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()

    init(hour: Int, minute: Int) {
        self.hour12 = hour % 12 == 0 ? 12 : hour % 12
        self.minute = minute
        self.isPM = hour >= 12
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        titleLabel.text = "Alarm Time"
        titleLabel.font = GameStyle.font(15)
        titleLabel.textAlignment = .center
        hintLabel.text = "Scroll to adjust. Press center to continue."
        hintLabel.font = GameStyle.lightFont(12)
        hintLabel.textColor = UIColor(white: 0.4, alpha: 1)
        hintLabel.textAlignment = .center
        hintLabel.adjustsFontSizeToFitWidth = true

        let colon = UILabel()
        colon.text = ":"
        colon.font = GameStyle.font(30)
        colon.textAlignment = .center

        let row = UIStackView(arrangedSubviews: [hourField, colon, minuteField, ampmField])
        row.axis = .horizontal
        row.alignment = .fill
        row.spacing = 6
        row.setCustomSpacing(14, after: minuteField)
        row.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, hintLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        view.addSubview(row)

        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            row.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.26),
            hourField.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.18),
            minuteField.widthAnchor.constraint(equalTo: hourField.widthAnchor),
            ampmField.widthAnchor.constraint(equalTo: hourField.widthAnchor),
            colon.widthAnchor.constraint(equalToConstant: 10),

            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            titleLabel.bottomAnchor.constraint(equalTo: row.topAnchor, constant: -16),

            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            hintLabel.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 16),
        ])
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Time"
    }

    private func refresh() {
        hourField.label.text = "\(hour12)"
        minuteField.label.text = String(format: "%02d", minute)
        ampmField.label.text = isPM ? "PM" : "AM"
        hourField.isActive = field == 0
        minuteField.isActive = field == 1
        ampmField.isActive = field == 2
    }

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        let step = rotationDirection == .CLOCKWISE ? 1 : -1
        switch field {
        case 0: hour12 = ((hour12 - 1 + step) % 12 + 12) % 12 + 1
        case 1: minute = ((minute + step) % 60 + 60) % 60
        default: isPM.toggle()
        }
        refresh()
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL { AppDelegate.music.playPause() }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL, field < 2 { field += 1; refresh() }
    }

    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL, field > 0 { field -= 1; refresh() }
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
        if field < 2 {
            field += 1
            refresh()
        } else {
            let hour24 = (hour12 % 12) + (isPM ? 12 : 0)
            onSave?(hour24, minute)
            navigationController?.popViewController(animated: true)
        }
    }
}

// MARK: - Delete confirmation

/// iPod-style confirm list: "Cancel" / "Delete Alarm".
final class AlarmDeleteConfirmViewController: UIViewController, ClickWheelProtocol {
    private let alarmID: UUID
    private let options = ["Cancel", "Delete Alarm"]
    private let tableView = UITableView()
    private let promptLabel = UILabel()
    private var counter = 0

    init(alarmID: UUID) {
        self.alarmID = alarmID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        promptLabel.font = GameStyle.font(14)
        promptLabel.textColor = UIColor(white: 0.25, alpha: 1)
        promptLabel.textAlignment = .center
        promptLabel.numberOfLines = 2
        if let alarm = AlarmStore.shared.alarm(id: alarmID) {
            promptLabel.text = "Delete the \(alarm.timeString) alarm?"
        } else {
            promptLabel.text = "Delete this alarm?"
        }
        view.addSubview(promptLabel)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.isScrollEnabled = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            promptLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            promptLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            promptLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
            tableView.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 12),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Delete Alarm"
        tableView.reloadData()
        tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
    }

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        let next = counter + (rotationDirection == .CLOCKWISE ? 1 : -1)
        guard options.indices.contains(next) else { return }
        counter = next
        tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
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
        guard counter == 1 else {
            navigationController?.popViewController(animated: true)
            return
        }
        AlarmStore.shared.deleteAlarm(id: alarmID)
        guard let nav = navigationController else { return }
        // Return to the Alarms list, skipping the now-empty editor.
        if let list = nav.viewControllers.last(where: { $0 is AlarmsViewController }) {
            nav.popToViewController(list, animated: true)
        } else {
            nav.popViewController(animated: true)
        }
    }
}

extension AlarmDeleteConfirmViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = options[indexPath.row]
        cell.accessoryType = .none
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        30
    }
}
