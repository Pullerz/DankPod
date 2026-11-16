//
//  AlarmsViewController.swift
//  Classic
//
//  Extras › Alarms: "Create Alarm", one row per alarm, then "Sleep Timer".
//

import UIKit

/// iPod list row for one alarm: time on the left, label/repeat summary on the
/// right and a small bell when the alarm is on.
final class AlarmRowCell: CustomTableViewCell {
    let detailLabel = UILabel()
    let bell = AlarmBellView()

    override init() {
        super.init()
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = UIFont(name: "Helvetica-Bold", size: 12)
        detailLabel.textColor = UIColor(white: 0.4, alpha: 1)
        detailLabel.textAlignment = .right
        detailLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(detailLabel)

        bell.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bell)

        NSLayoutConstraint.activate([
            bell.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -4),
            bell.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            bell.widthAnchor.constraint(equalToConstant: 13),
            bell.heightAnchor.constraint(equalToConstant: 13),
            detailLabel.rightAnchor.constraint(equalTo: bell.leftAnchor, constant: -6),
            detailLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            detailLabel.leftAnchor.constraint(greaterThanOrEqualTo: contentView.leftAnchor, constant: 110),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with alarm: Alarm) {
        label.text = alarm.timeString
        detailLabel.text = alarm.enabled ? "\(alarm.label) · \(alarm.repeatSummary)" : "\(alarm.label) · Off"
        bell.isHidden = !alarm.enabled
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        detailLabel.textColor = selected ? .white : UIColor(white: 0.4, alpha: 1)
        bell.color = selected ? .white : .black
    }
}

class AlarmsViewController: UIViewController, ClickWheelProtocol {

    private enum Row {
        case create
        case alarm(Alarm)
        case sleepTimer
    }

    private let tableView = UITableView()
    private var rows: [Row] = []
    private var counter = 0
    private var hasSetupUI = false
    private var refreshTimer: Timer?
    private var observer: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Alarms"
        reload()
        observer = NotificationCenter.default.addObserver(forName: AlarmStore.didChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
        // Keep the Sleep Timer's remaining time fresh while visible.
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshSleepRow()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
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
        // Keep the same alarm highlighted if editing its time re-sorted the list.
        var selectedID: UUID?
        if rows.indices.contains(counter), case .alarm(let a) = rows[counter] { selectedID = a.id }
        rows = [.create] + AlarmStore.shared.sortedAlarms.map { .alarm($0) } + [.sleepTimer]
        if let id = selectedID, let idx = rows.firstIndex(where: {
            if case .alarm(let a) = $0 { return a.id == id }; return false
        }) {
            counter = idx
        }
        counter = max(0, min(counter, rows.count - 1))
        tableView.reloadData()
        tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
        tableView.scrollToRow(at: IndexPath(row: counter, section: 0), at: .none, animated: false)
    }

    private func refreshSleepRow() {
        guard let idx = rows.lastIndex(where: { if case .sleepTimer = $0 { return true }; return false }),
              let cell = tableView.cellForRow(at: IndexPath(row: idx, section: 0)) as? CustomSettingsTableViewCell
        else { return }
        cell.valueLabel.text = AlarmStore.shared.sleepTimerSummary
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
        guard pressure == .NORMAL, rows.indices.contains(counter) else { return }
        switch rows[counter] {
        case .create:
            let alarm = AlarmStore.shared.createAlarm()
            // Leave the new alarm's row selected when coming back.
            if let idx = AlarmStore.shared.sortedAlarms.firstIndex(where: { $0.id == alarm.id }) {
                counter = idx + 1
            }
            navigationController?.pushViewController(AlarmEditorViewController(alarmID: alarm.id), animated: true)
        case .alarm(let alarm):
            navigationController?.pushViewController(AlarmEditorViewController(alarmID: alarm.id), animated: true)
        case .sleepTimer:
            let options = AlarmStore.sleepTimerOptions
            let picker = SettingsPickerViewController()
            picker.pickerTitle = "Sleep Timer"
            picker.options = options.map { $0 == 0 ? "Off" : "\($0) Minutes" }
            picker.selectedIndex = options.firstIndex(of: AlarmStore.shared.sleepTimerMinutes) ?? 0
            picker.onSelect = { index in
                guard options.indices.contains(index) else { return }
                AlarmStore.shared.setSleepTimer(minutes: options[index])
            }
            navigationController?.pushViewController(picker, animated: true)
        }
    }
}

extension AlarmsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch rows[indexPath.row] {
        case .create:
            let cell = CustomTableViewCell()
            cell.label.text = "Create Alarm"
            cell.selectionStyle = .none
            return cell
        case .alarm(let alarm):
            let cell = AlarmRowCell()
            cell.configure(with: alarm)
            cell.selectionStyle = .none
            return cell
        case .sleepTimer:
            let cell = CustomSettingsTableViewCell()
            cell.label.text = "Sleep Timer"
            cell.valueLabel.text = AlarmStore.shared.sleepTimerSummary
            cell.selectionStyle = .none
            return cell
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        30
    }
}
