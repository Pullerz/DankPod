//
//  ClockCityPickerViewController.swift
//  Classic
//

import UIKit

/// iPod-style two-level picker: regions, then cities (alphabetical).
/// A region-less instance lists regions; selecting one pushes a second instance for its cities.
class ClockCityPickerViewController: UIViewController, ClickWheelProtocol {
    enum Mode {
        case add
        case replace(index: Int)
    }

    let mode: Mode
    let region: ClockRegion?
    let tableView = UITableView()
    var counter = 0
    private var hasSetupUI = false

    private var items: [String] {
        if let region = region { return region.cities.map { $0.name } }
        return WorldClockStore.regions.map { $0.name }
    }

    init(mode: Mode, region: ClockRegion? = nil) {
        self.mode = mode
        self.region = region
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = region?.name ?? "Clock"
        counter = max(0, min(counter, items.count - 1))
        // Size the table first: selecting/scrolling a zero-height table loses the highlight.
        view.layoutIfNeeded()
        tableView.reloadData()
        selectCurrent()
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

    private func selectCurrent() {
        guard !items.isEmpty else { return }
        let ip = IndexPath(row: counter, section: 0)
        tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
        tableView.scrollToRow(at: ip, at: .none, animated: false)
    }

    // MARK: Picking

    private func pick(_ city: ClockCity) {
        let clock = WorldClock(city: city.name, timeZoneID: city.timeZoneID)
        let store = WorldClockStore.shared
        let stack = navigationController?.viewControllers ?? []
        switch mode {
        case .add:
            let newIndex = store.add(clock)
            if let list = stack.last(where: { $0 is ClocksViewController }) as? ClocksViewController {
                list.counter = newIndex
                navigationController?.popToViewController(list, animated: true)
            } else {
                navigationController?.popViewController(animated: true)
            }
        case .replace(let index):
            store.replace(at: index, with: clock)
            if let detail = stack.last(where: { $0 is ClockDetailViewController }) as? ClockDetailViewController {
                detail.index = min(index, store.clocks.count - 1)
                navigationController?.popToViewController(detail, animated: true)
            } else if let list = stack.last(where: { $0 is ClocksViewController }) {
                navigationController?.popToViewController(list, animated: true)
            } else {
                navigationController?.popViewController(animated: true)
            }
        }
    }

    // MARK: ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if rotationDirection == .CLOCKWISE {
            guard counter < items.count - 1 else { return }
            counter += 1
        } else {
            guard counter > 0 else { return }
            counter -= 1
        }
        selectCurrent()
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
        guard pressure == .NORMAL, items.indices.contains(counter) else { return }
        if let region = region {
            pick(region.cities[counter])
        } else {
            let next = ClockCityPickerViewController(mode: mode, region: WorldClockStore.regions[counter])
            navigationController?.pushViewController(next, animated: true)
        }
    }
}

extension ClockCityPickerViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = items[indexPath.row]
        cell.selectionStyle = .none
        if region != nil { cell.accessoryType = .none }   // cities are leaves
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        30
    }
}
