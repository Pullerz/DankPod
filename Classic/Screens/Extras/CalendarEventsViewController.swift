//
//  CalendarEventsViewController.swift
//  Classic
//
//  One day's events as an iPod list ("9:00 AM  Meeting", all-day first), and the
//  event card shown when one is chosen.
//

import UIKit
import EventKit

class CalendarEventsViewController: UIViewController, ClickWheelProtocol {
    private let store: EKEventStore
    private let calendars: [EKCalendar]?
    private let day: Date
    private var events: [EKEvent] = []
    private var counter = 0

    private let tableView = UITableView()
    private let emptyView = PIMMessageView()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    init(store: EKEventStore, calendars: [EKCalendar]?, day: Date) {
        self.store = store
        self.calendars = calendars
        self.day = Calendar.current.startOfDay(for: day)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .white
        view.addSubview(tableView)

        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.set(title: "No Events", message: nil)
        view.addSubview(emptyView)

        for v in [tableView, emptyView] as [UIView] {
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: view.topAnchor),
                v.leftAnchor.constraint(equalTo: view.leftAnchor),
                v.rightAnchor.constraint(equalTo: view.rightAnchor),
                v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = Self.titleFormatter.string(from: day)
        loadEvents()
    }

    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
    }

    private func loadEvents() {
        let predicate = store.predicateForEvents(withStart: day, end: dayEnd, calendars: calendars)
        events = store.events(matching: predicate).sorted { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            if a.startDate != b.startDate { return a.startDate < b.startDate }
            return (a.title ?? "").localizedCaseInsensitiveCompare(b.title ?? "") == .orderedAscending
        }
        counter = max(0, min(counter, events.count - 1))
        tableView.isHidden = events.isEmpty
        emptyView.isHidden = !events.isEmpty
        tableView.reloadData()
        tableView.layoutIfNeeded()
        pimSelectRow(tableView, counter)
    }

    private func rowText(_ event: EKEvent) -> String {
        let title = (event.title ?? "").isEmpty ? "Untitled" : event.title!
        let time: String
        if event.isAllDay || (event.startDate <= day && event.endDate >= dayEnd) {
            time = "All Day"
        } else if event.startDate < day {
            time = Self.timeFormatter.string(from: day)
        } else {
            time = Self.timeFormatter.string(from: event.startDate)
        }
        return "\(time)  \(title)"
    }

    // MARK: Click wheel

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        guard !events.isEmpty else { return }
        if rotationDirection == .CLOCKWISE {
            if counter < events.count - 1 { counter += 1; pimSelectRow(tableView, counter) }
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
        guard pressure == .NORMAL, counter < events.count else { return }
        navigationController?.pushViewController(CalendarEventDetailViewController(event: events[counter]), animated: true)
    }
}

extension CalendarEventsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { events.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = rowText(events[indexPath.row])
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 30 }
}

// MARK: - Event card

final class CalendarEventDetailViewController: UIViewController, ClickWheelProtocol {
    private let event: EKEvent
    private let card = PIMCardView()

    init(event: EKEvent) {
        self.event = event
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: view.topAnchor),
            card.leftAnchor.constraint(equalTo: view.leftAnchor),
            card.rightAnchor.constraint(equalTo: view.rightAnchor),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        build()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Event"
    }

    private func build() {
        let cal = Calendar.current
        let title = (event.title ?? "").isEmpty ? "Untitled" : event.title!
        card.addTitle(title)
        if let c = event.calendar {
            card.addSubtitle(c.title, dotColor: UIColor(cgColor: c.cgColor))
        }
        card.addSeparator()

        let start: Date = event.startDate
        // All-day end dates sit at 23:59:59 of the last day; timed events end exclusively.
        let lastInstant: Date = event.endDate > start ? event.endDate.addingTimeInterval(-1) : start
        let singleDay = cal.isDate(start, inSameDayAs: lastInstant)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none

        if event.isAllDay {
            if singleDay {
                card.addField(label: "date", value: dateFormatter.string(from: start))
            } else {
                let f = DateIntervalFormatter()
                f.dateStyle = .medium
                f.timeStyle = .none
                card.addField(label: "date", value: f.string(from: start, to: lastInstant))
            }
            card.addField(label: "time", value: "All Day")
        } else if singleDay {
            card.addField(label: "date", value: dateFormatter.string(from: start))
            let f = DateIntervalFormatter()
            f.dateStyle = .none
            f.timeStyle = .short
            card.addField(label: "time", value: f.string(from: start, to: event.endDate))
        } else {
            card.addField(label: "starts", value: DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .short))
            card.addField(label: "ends", value: DateFormatter.localizedString(from: event.endDate, dateStyle: .medium, timeStyle: .short))
        }

        if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            card.addField(label: "location", value: location)
        }
        if let url = event.url {
            card.addField(label: "url", value: url.absoluteString)
        }
        if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            card.addSeparator()
            card.addHeading("Notes")
            card.addBody(notes)
        }
    }

    // MARK: Click wheel

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        card.scroll(rotationDirection)
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

    func centerPressed(pressure: ClickWheelTouchPressure) {}
}
