//
//  AlarmStore.swift
//  Classic
//
//  Alarms + Sleep Timer model, persistence, local-notification scheduling,
//  and the in-app "Alarm" screen shown when an alarm fires in the foreground.
//

import UIKit
import UserNotifications
import AVFoundation

// MARK: - Model

enum AlarmRepeat: String, Codable, CaseIterable {
    case once, everyDay, weekdays, weekends, weekly

    var title: String {
        switch self {
        case .once: return "Once"
        case .everyDay: return "Every Day"
        case .weekdays: return "Weekdays"
        case .weekends: return "Weekends"
        case .weekly: return "Weekly"
        }
    }
}

enum AlarmAlert: String, Codable, CaseIterable {
    case beep, none

    var title: String { self == .beep ? "Beep" : "None" }
}

struct Alarm: Codable, Equatable {
    var id: UUID = UUID()
    var enabled: Bool = true
    var hour: Int = 7          // 0...23
    var minute: Int = 0        // 0...59
    var repeatRule: AlarmRepeat = .once
    var alert: AlarmAlert = .beep
    var label: String = "Alarm"
    /// Calendar weekday (1 = Sunday ... 7 = Saturday) used by `.weekly`.
    var weekday: Int = Calendar.current.component(.weekday, from: Date())
    /// The concrete fire date for a `.once` alarm (nil when off / repeating).
    var onceFireDate: Date?

    static let labelPresets = ["Alarm", "Wake Up", "Work", "School", "Gym", "Medication", "Meeting", "Nap"]

    var timeString: String { Alarm.timeString(hour: hour, minute: minute) }

    static func timeString(hour: Int, minute: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h12, minute, hour < 12 ? "AM" : "PM")
    }

    /// Short repeat description for the Alarms list ("Weekdays", "Tuesdays"...).
    var repeatSummary: String {
        if repeatRule == .weekly {
            let symbols = Calendar.current.weekdaySymbols
            let idx = max(0, min(symbols.count - 1, weekday - 1))
            return symbols[idx] + "s"
        }
        return repeatRule.title
    }
}

// MARK: - Store

final class AlarmStore: NSObject {
    static let shared = AlarmStore()

    /// Posted on the main queue whenever alarms or the sleep timer change.
    static let didChangeNotification = Notification.Name("classic.alarms.didChange")

    private enum Keys {
        static let list = "classic.alarms.list"
        static let sleepFireDate = "classic.alarms.sleepTimerFireDate"
        static let sleepMinutes = "classic.alarms.sleepTimerMinutes"
    }

    private static let requestPrefix = "classic.alarm."

    private let defaults = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()

    private(set) var alarms: [Alarm] = []

    private var activated = false
    private var sleepTimer: Timer?
    private weak var alertScreen: AlarmAlertViewController?

    private override init() {
        super.init()
        load()
    }

    // MARK: Launch

    /// Called once from `application(_:didFinishLaunchingWithOptions:)`.
    /// Installs the notification-center delegate (needed for foreground alarms),
    /// reconciles fired "Once" alarms, and restores a running sleep timer.
    func activate() {
        guard !activated else { return }
        activated = true
        center.delegate = self
        reconcile()
        restoreSleepTimer()
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func appWillEnterForeground() {
        reconcile()
        restoreSleepTimer()
    }

    // MARK: Persistence

    private func load() {
        if let data = defaults.data(forKey: Keys.list),
           let decoded = try? JSONDecoder().decode([Alarm].self, from: data) {
            alarms = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(alarms) {
            defaults.set(data, forKey: Keys.list)
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: AlarmStore.didChangeNotification, object: nil)
    }

    // MARK: Queries

    func alarm(id: UUID) -> Alarm? { alarms.first { $0.id == id } }

    /// Alarms in display order (by time of day).
    var sortedAlarms: [Alarm] {
        alarms.sorted { ($0.hour, $0.minute, $0.id.uuidString) < ($1.hour, $1.minute, $1.id.uuidString) }
    }

    // MARK: Mutation

    /// Creates a new enabled alarm set to the next whole hour.
    @discardableResult
    func createAlarm() -> Alarm {
        var alarm = Alarm()
        let now = Date()
        let cal = Calendar.current
        alarm.hour = (cal.component(.hour, from: now) + 1) % 24
        alarm.minute = 0
        alarm.weekday = cal.component(.weekday, from: now)
        alarms.append(alarm)
        update(alarm)
        return self.alarm(id: alarm.id) ?? alarm
    }

    /// Saves an alarm and reschedules its notifications. Changes save immediately.
    func update(_ newValue: Alarm) {
        guard let idx = alarms.firstIndex(where: { $0.id == newValue.id }) else { return }
        var alarm = newValue
        if alarm.enabled && alarm.repeatRule == .once {
            let cal = Calendar.current
            let stale = alarm.onceFireDate.map { date in
                date <= Date()
                    || cal.component(.hour, from: date) != alarm.hour
                    || cal.component(.minute, from: date) != alarm.minute
            } ?? true
            if stale { alarm.onceFireDate = AlarmStore.nextDate(hour: alarm.hour, minute: alarm.minute) }
        } else {
            alarm.onceFireDate = nil
        }
        alarms[idx] = alarm
        save()
        notifyChange()
        if alarm.enabled {
            ensureAuthorization { [weak self] in self?.schedule(alarm) }
        } else {
            unschedule(alarm.id)
        }
    }

    func deleteAlarm(id: UUID) {
        alarms.removeAll { $0.id == id }
        save()
        unschedule(id)
        notifyChange()
    }

    // MARK: Scheduling

    static func nextDate(hour: Int, minute: Int, after date: Date = Date()) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return Calendar.current.nextDate(after: date, matching: comps, matchingPolicy: .nextTime) ?? date
    }

    private static func requestIDs(for id: UUID) -> [String] {
        // At most 5 triggers per alarm (Weekdays).
        (0..<7).map { "\(requestPrefix)\(id.uuidString).\($0)" }
    }

    private static func alarmID(fromRequestID identifier: String) -> UUID? {
        guard identifier.hasPrefix(requestPrefix) else { return nil }
        let rest = identifier.dropFirst(requestPrefix.count)
        guard let uuid = rest.split(separator: ".").first else { return nil }
        return UUID(uuidString: String(uuid))
    }

    /// Asks for notification permission the first time an alarm is enabled.
    private func ensureAuthorization(then work: @escaping () -> Void) {
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                self?.center.requestAuthorization(options: [.alert, .sound]) { _, _ in
                    DispatchQueue.main.async(execute: work)
                }
            default:
                DispatchQueue.main.async(execute: work)
            }
        }
    }

    private func triggers(for alarm: Alarm) -> [UNCalendarNotificationTrigger] {
        func comps(weekday: Int?) -> DateComponents {
            var c = DateComponents()
            c.hour = alarm.hour
            c.minute = alarm.minute
            c.weekday = weekday
            return c
        }
        switch alarm.repeatRule {
        case .once:
            guard let date = alarm.onceFireDate else { return [] }
            let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            return [UNCalendarNotificationTrigger(dateMatching: c, repeats: false)]
        case .everyDay:
            return [UNCalendarNotificationTrigger(dateMatching: comps(weekday: nil), repeats: true)]
        case .weekdays:
            return (2...6).map { UNCalendarNotificationTrigger(dateMatching: comps(weekday: $0), repeats: true) }
        case .weekends:
            return [1, 7].map { UNCalendarNotificationTrigger(dateMatching: comps(weekday: $0), repeats: true) }
        case .weekly:
            return [UNCalendarNotificationTrigger(dateMatching: comps(weekday: alarm.weekday), repeats: true)]
        }
    }

    private func schedule(_ alarm: Alarm) {
        unschedule(alarm.id)
        // Re-read: the alarm may have changed while authorization was pending.
        guard let current = self.alarm(id: alarm.id), current.enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Alarm"
        content.body = "\(current.label) – \(current.timeString)"
        // Critical sounds need a special entitlement, so use the default sound.
        content.sound = current.alert == .beep ? .default : nil
        let ids = AlarmStore.requestIDs(for: current.id)
        for (i, trigger) in triggers(for: current).enumerated() {
            center.add(UNNotificationRequest(identifier: ids[i], content: content, trigger: trigger))
        }
    }

    private func unschedule(_ id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: AlarmStore.requestIDs(for: id))
    }

    /// Disables "Once" alarms that have already fired (delivered, or past with
    /// nothing pending), then re-registers every enabled alarm.
    func reconcile() {
        center.getPendingNotificationRequests { [weak self] pending in
            self?.center.getDeliveredNotifications { delivered in
                let pendingIDs = Set(pending.compactMap { AlarmStore.alarmID(fromRequestID: $0.identifier) })
                let deliveredIDs = Set(delivered.compactMap { AlarmStore.alarmID(fromRequestID: $0.request.identifier) })
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let now = Date()
                    var changed = false
                    for i in self.alarms.indices where self.alarms[i].enabled && self.alarms[i].repeatRule == .once {
                        let a = self.alarms[i]
                        let fired = a.onceFireDate.map { $0 <= now } ?? true
                        let wasDelivered = deliveredIDs.contains(a.id) && !pendingIDs.contains(a.id)
                        if fired || wasDelivered {
                            self.alarms[i].enabled = false
                            self.alarms[i].onceFireDate = nil
                            changed = true
                        }
                    }
                    // Drop requests for alarms that no longer exist.
                    let known = Set(self.alarms.map { $0.id })
                    let orphans = pending.filter {
                        guard let id = AlarmStore.alarmID(fromRequestID: $0.identifier) else { return false }
                        return !known.contains(id)
                    }.map { $0.identifier }
                    if !orphans.isEmpty { self.center.removePendingNotificationRequests(withIdentifiers: orphans) }
                    if changed {
                        self.save()
                        self.notifyChange()
                    }
                    for a in self.alarms {
                        if a.enabled { self.schedule(a) } else { self.unschedule(a.id) }
                    }
                }
            }
        }
    }

    // MARK: Firing (foreground)

    fileprivate func alarmFired(id: UUID) {
        guard let alarm = alarm(id: id) else { return }
        if alarm.repeatRule == .once {
            var off = alarm
            off.enabled = false
            update(off)
        }
        presentAlertScreen(for: alarm)
    }

    /// Pushes the full-screen iPod "Alarm" card. Returns false if the iPod UI isn't up yet.
    @discardableResult
    fileprivate func presentAlertScreen(for alarm: Alarm) -> Bool {
        if let screen = alertScreen, screen.navigationController != nil, !screen.dismissed {
            screen.configure(with: alarm)
            return true
        }
        guard let nav = AppDelegate.baseVC?.navController else { return false }
        let screen = AlarmAlertViewController(alarm: alarm)
        alertScreen = screen
        nav.pushViewController(screen, animated: true)
        return true
    }

    // MARK: Sleep Timer
    //
    // NOTE: The sleep timer is a plain in-process Timer. iOS suspends apps in the
    // background, so it only fires while the app is running (in the foreground,
    // or kept alive in the background). If it expired while suspended, it is
    // cleared when the app returns without pausing music.

    static let sleepTimerOptions: [Int] = [0, 15, 30, 60, 90, 120]   // minutes, 0 = Off

    var sleepTimerFireDate: Date? {
        guard let date = defaults.object(forKey: Keys.sleepFireDate) as? Date, date > Date() else { return nil }
        return date
    }

    /// The chosen duration for the running timer (0 when off).
    var sleepTimerMinutes: Int {
        sleepTimerFireDate == nil ? 0 : defaults.integer(forKey: Keys.sleepMinutes)
    }

    /// "Off" or the time remaining, e.g. "23 min".
    var sleepTimerSummary: String {
        guard let date = sleepTimerFireDate else { return "Off" }
        let mins = Int(ceil(date.timeIntervalSinceNow / 60))
        return "\(max(1, mins)) min"
    }

    func setSleepTimer(minutes: Int) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        if minutes <= 0 {
            defaults.removeObject(forKey: Keys.sleepFireDate)
            defaults.set(0, forKey: Keys.sleepMinutes)
        } else {
            let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
            defaults.set(date, forKey: Keys.sleepFireDate)
            defaults.set(minutes, forKey: Keys.sleepMinutes)
            startSleepTimer(fireAt: date)
        }
        notifyChange()
    }

    private func restoreSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        if let date = sleepTimerFireDate {
            startSleepTimer(fireAt: date)
        } else if defaults.object(forKey: Keys.sleepFireDate) != nil {
            defaults.removeObject(forKey: Keys.sleepFireDate)
            defaults.set(0, forKey: Keys.sleepMinutes)
            notifyChange()
        }
    }

    private func startSleepTimer(fireAt date: Date) {
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            self?.sleepTimerExpired()
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    private func sleepTimerExpired() {
        sleepTimer = nil
        defaults.removeObject(forKey: Keys.sleepFireDate)
        defaults.set(0, forKey: Keys.sleepMinutes)
        AppDelegate.music?.musicPlayer.pause()
        notifyChange()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AlarmStore: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard let id = AlarmStore.alarmID(fromRequestID: notification.request.identifier) else {
            completionHandler([.banner, .list, .sound])
            return
        }
        DispatchQueue.main.async {
            if AppDelegate.baseVC?.navController != nil {
                // The in-app Alarm screen replaces the system banner.
                self.alarmFired(id: id)
                completionHandler([])
            } else {
                completionHandler([.banner, .list, .sound])
                self.reconcile()
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.reconcile()
            completionHandler()
        }
    }
}

// MARK: - Beep tone

/// Synthesises a classic four-pip alarm beep into a PCM buffer and loops it.
final class AlarmBeepPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var previousCategory: AVAudioSession.Category?
    private var previousOptions: AVAudioSession.CategoryOptions = []
    private(set) var isPlaying = false

    private static func makeBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(sampleRate * 1.0)   // 1 s loop
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let freq = 2048.0, beepLen = 0.08, cycle = 0.14, ramp = 0.004
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let pip = Int(t / cycle)
            let local = t - Double(pip) * cycle
            var sample: Float = 0
            if pip < 4 && local < beepLen {
                let env = min(1, local / ramp, (beepLen - local) / ramp)
                sample = Float(sin(2 * .pi * freq * t) * 0.45 * env)
            }
            channel[i] = sample
        }
        return buffer
    }

    func start() {
        guard !isPlaying else { return }
        let session = AVAudioSession.sharedInstance()
        previousCategory = session.category
        previousOptions = session.categoryOptions
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AlarmBeepPlayer.makeBuffer(format: format) else { return }
        if node.engine == nil { engine.attach(node) }
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            restoreSession()
            return
        }
        node.scheduleBuffer(buffer, at: nil, options: .loops)
        node.play()
        isPlaying = true
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        node.stop()
        engine.stop()
        restoreSession()
    }

    private func restoreSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        if let cat = previousCategory {
            try? session.setCategory(cat, options: previousOptions)
        }
    }

    deinit { stop() }
}

// MARK: - Bell icon

/// Hand-drawn iPod alarm bell. `color` fills the bell; `glossy` adds a 2007-style sheen.
final class AlarmBellView: UIView {
    var color: UIColor = .black { didSet { setNeedsDisplay() } }
    var glossy = false { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func bellPath(in r: CGRect) -> UIBezierPath {
        let w = r.width, h = r.height
        let x = r.minX, y = r.minY
        let p = UIBezierPath()
        // Knob on top
        p.append(UIBezierPath(ovalIn: CGRect(x: x + w * 0.43, y: y, width: w * 0.14, height: h * 0.13)))
        // Bell body
        let body = UIBezierPath()
        body.move(to: CGPoint(x: x + w * 0.04, y: y + h * 0.80))
        body.addQuadCurve(to: CGPoint(x: x + w * 0.20, y: y + h * 0.58), controlPoint: CGPoint(x: x + w * 0.18, y: y + h * 0.72))
        body.addCurve(to: CGPoint(x: x + w * 0.50, y: y + h * 0.10),
                      controlPoint1: CGPoint(x: x + w * 0.20, y: y + h * 0.25),
                      controlPoint2: CGPoint(x: x + w * 0.32, y: y + h * 0.10))
        body.addCurve(to: CGPoint(x: x + w * 0.80, y: y + h * 0.58),
                      controlPoint1: CGPoint(x: x + w * 0.68, y: y + h * 0.10),
                      controlPoint2: CGPoint(x: x + w * 0.80, y: y + h * 0.25))
        body.addQuadCurve(to: CGPoint(x: x + w * 0.96, y: y + h * 0.80), controlPoint: CGPoint(x: x + w * 0.82, y: y + h * 0.72))
        body.close()
        p.append(body)
        // Clapper
        p.append(UIBezierPath(ovalIn: CGRect(x: x + w * 0.38, y: y + h * 0.80, width: w * 0.24, height: h * 0.18)))
        return p
    }

    override func draw(_ rect: CGRect) {
        let inset = bounds.insetBy(dx: bounds.width * 0.02, dy: bounds.height * 0.02)
        let path = AlarmBellView.bellPath(in: inset)
        color.setFill()
        path.fill()
        guard glossy, let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        path.addClip()
        let colors = [UIColor(white: 1, alpha: 0.55).cgColor, UIColor(white: 1, alpha: 0.05).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: inset.minY),
                                   end: CGPoint(x: 0, y: inset.midY), options: [])
        }
        ctx.restoreGState()
        UIColor(white: 0, alpha: 0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

// MARK: - In-app Alarm screen

/// Full-screen iPod "Alarm" card pushed when an alarm fires while the app is open.
/// Beeps until the center button (or Menu) is pressed.
final class AlarmAlertViewController: UIViewController, ClickWheelProtocol {
    private var alarm: Alarm
    private let beeper = AlarmBeepPlayer()
    private let card = UIView()
    private let cardGradient = CAGradientLayer()
    private let bell = AlarmBellView()
    private let timeLabel = UILabel()
    private let nameLabel = UILabel()
    private let hintLabel = UILabel()
    private(set) var dismissed = false

    init(alarm: Alarm) {
        self.alarm = alarm
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with alarm: Alarm) {
        self.alarm = alarm
        guard isViewLoaded else { return }
        timeLabel.text = alarm.timeString
        nameLabel.text = alarm.label
        if alarm.alert == .beep { beeper.start() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 10
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(white: 0.62, alpha: 1).cgColor
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.25
        card.layer.shadowRadius = 4
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        cardGradient.colors = [UIColor.white.cgColor, UIColor(white: 0.86, alpha: 1).cgColor]
        cardGradient.cornerRadius = 10
        card.layer.insertSublayer(cardGradient, at: 0)
        view.addSubview(card)

        bell.translatesAutoresizingMaskIntoConstraints = false
        bell.color = UIColor(red: 0.18, green: 0.42, blue: 0.80, alpha: 1)
        bell.glossy = true

        timeLabel.font = GameStyle.font(40)
        timeLabel.textAlignment = .center
        timeLabel.adjustsFontSizeToFitWidth = true
        nameLabel.font = GameStyle.font(17)
        nameLabel.textAlignment = .center
        nameLabel.textColor = UIColor(white: 0.2, alpha: 1)
        hintLabel.font = GameStyle.lightFont(12)
        hintLabel.textAlignment = .center
        hintLabel.textColor = UIColor(white: 0.4, alpha: 1)
        hintLabel.text = "Press center to dismiss"

        let stack = UIStackView(arrangedSubviews: [bell, timeLabel, nameLabel, hintLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.setCustomSpacing(10, after: nameLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.78),
            card.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            bell.widthAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.22),
            bell.heightAnchor.constraint(equalTo: bell.widthAnchor),
        ])
        timeLabel.text = alarm.timeString
        nameLabel.text = alarm.label
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardGradient.frame = card.bounds
        CATransaction.commit()
        card.layer.shadowPath = UIBezierPath(roundedRect: card.bounds, cornerRadius: 10).cgPath
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Alarm"
        if !dismissed && alarm.alert == .beep { beeper.start() }
        startRinging()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        beeper.stop()
        bell.layer.removeAllAnimations()
    }

    private func startRinging() {
        bell.layer.removeAllAnimations()
        let wobble = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wobble.values = [0, 0.3, -0.3, 0.25, -0.25, 0, 0]
        wobble.keyTimes = [0, 0.1, 0.2, 0.3, 0.4, 0.5, 1]
        wobble.duration = 1.0
        wobble.repeatCount = .infinity
        bell.layer.add(wobble, forKey: "ring")
    }

    private func dismissAlarm() {
        guard !dismissed else { return }
        dismissed = true
        beeper.stop()
        bell.layer.removeAllAnimations()
        if navigationController?.topViewController === self {
            navigationController?.popViewController(animated: true)
        } else if let nav = navigationController {
            nav.viewControllers.removeAll { $0 === self }
        }
    }

    // MARK: ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {}

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL { AppDelegate.music.playPause() }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {}
    func previousSongPressed(pressure: ClickWheelTouchPressure) {}

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL || pressure == .FORCE { dismissAlarm() }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL { dismissAlarm() }
    }
}
