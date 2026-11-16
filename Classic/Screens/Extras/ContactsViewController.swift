//
//  ContactsViewController.swift
//  Classic
//
//  Extras › Contacts. Read-only, alphabetical iPod list of the iPhone's contacts,
//  with the iPod's big-letter fast scrolling when the wheel is spun quickly.
//

import UIKit
import Contacts

class ContactsViewController: UIViewController, ClickWheelProtocol {
    static let contactStore = CNContactStore()

    private struct Entry {
        let identifier: String
        let name: String
        let sortKey: String
        let letter: String
    }

    private enum State { case loading, denied, ready }

    private let tableView = UITableView()
    private let messageView = PIMMessageView()
    private let letterOverlay = UIView()
    private let letterLabel = UILabel()

    private var entries: [Entry] = []
    /// Index of the first row of each letter group, in list order.
    private var letterStarts: [Int] = []
    private var counter = 0
    private var state: State = .loading
    private var loadGeneration = 0

    // Fast-scroll tracking.
    private var tickTimes: [CFTimeInterval] = []
    private var lastJump: CFTimeInterval = 0
    private var overlayTimer: Timer?
    private static let fastWindow: CFTimeInterval = 0.15
    private static let fastTickCount = 4
    private static let jumpInterval: CFTimeInterval = 0.1

    private var store: CNContactStore { ContactsViewController.contactStore }

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

        // The iPod's translucent alphabet-scroll letter.
        letterOverlay.translatesAutoresizingMaskIntoConstraints = false
        letterOverlay.backgroundColor = UIColor(white: 0.1, alpha: 0.62)
        letterOverlay.layer.cornerRadius = 14
        letterOverlay.layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
        letterOverlay.layer.borderWidth = 1
        letterOverlay.isUserInteractionEnabled = false
        letterOverlay.alpha = 0
        let shine = PIMOverlayShine()
        shine.translatesAutoresizingMaskIntoConstraints = false
        letterOverlay.addSubview(shine)
        letterLabel.translatesAutoresizingMaskIntoConstraints = false
        letterLabel.font = UIFont(name: "Helvetica-Bold", size: 64)
        letterLabel.textColor = .white
        letterLabel.textAlignment = .center
        letterLabel.adjustsFontSizeToFitWidth = true
        letterLabel.minimumScaleFactor = 0.5
        letterLabel.shadowColor = UIColor(white: 0, alpha: 0.5)
        letterLabel.shadowOffset = CGSize(width: 0, height: -1)
        letterOverlay.addSubview(letterLabel)
        view.addSubview(letterOverlay)
        NSLayoutConstraint.activate([
            letterOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            letterOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            letterOverlay.widthAnchor.constraint(equalToConstant: 96),
            letterOverlay.heightAnchor.constraint(equalToConstant: 96),
            letterLabel.centerXAnchor.constraint(equalTo: letterOverlay.centerXAnchor),
            letterLabel.centerYAnchor.constraint(equalTo: letterOverlay.centerYAnchor),
            letterLabel.widthAnchor.constraint(equalTo: letterOverlay.widthAnchor, constant: -12),
            shine.topAnchor.constraint(equalTo: letterOverlay.topAnchor),
            shine.leftAnchor.constraint(equalTo: letterOverlay.leftAnchor),
            shine.rightAnchor.constraint(equalTo: letterOverlay.rightAnchor),
            shine.heightAnchor.constraint(equalTo: letterOverlay.heightAnchor, multiplier: 0.5),
        ])

        apply(.loading)
        checkAccess()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Contacts"
        if state == .ready {
            pimSelectRow(tableView, counter)
        } else if state == .denied {
            checkAccess()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        overlayTimer?.invalidate()
        overlayTimer = nil
        letterOverlay.layer.removeAllAnimations()
        letterOverlay.alpha = 0
        tickTimes.removeAll()
    }

    // MARK: Access & loading

    private func checkAccess() {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            loadContacts()
        case .notDetermined:
            apply(.loading)
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if granted { self.loadContacts() } else { self.apply(.denied) }
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
            messageView.set(title: "Contacts", message: "Loading…")
        case .denied:
            tableView.isHidden = true
            messageView.isHidden = false
            messageView.set(title: "Contacts Unavailable",
                            message: "To see your contacts here, allow Classic access in Settings › Privacy & Security › Contacts.")
        case .ready:
            if entries.isEmpty {
                tableView.isHidden = true
                messageView.isHidden = false
                messageView.set(title: "No Contacts", message: nil)
            } else {
                tableView.isHidden = false
                messageView.isHidden = true
            }
            tableView.reloadData()
            tableView.layoutIfNeeded()
            pimSelectRow(tableView, counter)
        }
    }

    /// Fetches only what the list needs (name keys) and sorts by last name, off the main thread.
    private func loadContacts() {
        if entries.isEmpty { apply(.loading) }
        loadGeneration += 1
        let generation = loadGeneration
        let store = self.store
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let keys: [CNKeyDescriptor] = [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactOrganizationNameKey as CNKeyDescriptor,
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            let formatter = CNContactFormatter()
            formatter.style = .fullName
            var result: [Entry] = []
            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    var name = formatter.string(from: contact)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let org = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if name.isEmpty { name = org }
                    if name.isEmpty { name = "No Name" }
                    let family = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let given = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let sortKey: String
                    if !family.isEmpty {
                        sortKey = given.isEmpty ? family : "\(family) \(given)"
                    } else if !given.isEmpty {
                        sortKey = given
                    } else {
                        sortKey = name
                    }
                    result.append(Entry(identifier: contact.identifier, name: name,
                                        sortKey: sortKey, letter: Self.letter(for: sortKey)))
                }
            } catch {
                result = []
            }
            result.sort { a, b in
                // "#" (numbers/symbols) go to the end, as on the iPod.
                let aHash = a.letter == "#", bHash = b.letter == "#"
                if aHash != bHash { return bHash }
                let c = a.sortKey.localizedStandardCompare(b.sortKey)
                if c != .orderedSame { return c == .orderedAscending }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            DispatchQueue.main.async {
                guard let self = self, generation == self.loadGeneration else { return }
                self.entries = result
                self.letterStarts = Self.letterStarts(for: result)
                self.counter = max(0, min(self.counter, result.count - 1))
                self.apply(.ready)
            }
        }
    }

    private static func letter(for key: String) -> String {
        guard let first = key.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).first,
              first.isLetter else { return "#" }
        return String(first).uppercased()
    }

    private static func letterStarts(for entries: [Entry]) -> [Int] {
        var starts: [Int] = []
        var last: String?
        for (i, e) in entries.enumerated() where e.letter != last {
            starts.append(i)
            last = e.letter
        }
        return starts
    }

    // MARK: Fast scrolling

    /// Index into `letterStarts` of the group containing `row`.
    private func groupIndex(of row: Int) -> Int {
        var g = 0
        for (i, start) in letterStarts.enumerated() where start <= row { g = i }
        return g
    }

    private func jumpLetter(_ direction: RotationDirection) {
        guard !letterStarts.isEmpty else { return }
        let g = groupIndex(of: counter)
        if direction == .CLOCKWISE {
            if g + 1 < letterStarts.count { counter = letterStarts[g + 1] }
        } else {
            if counter > letterStarts[g] {
                counter = letterStarts[g]
            } else if g > 0 {
                counter = letterStarts[g - 1]
            }
        }
    }

    private func showOverlay() {
        guard counter < entries.count else { return }
        letterLabel.text = entries[counter].letter
        if letterOverlay.alpha < 1 {
            letterOverlay.layer.removeAllAnimations()
            UIView.animate(withDuration: 0.1) { self.letterOverlay.alpha = 1 }
        }
        overlayTimer?.invalidate()
        overlayTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.overlayTimer = nil
            UIView.animate(withDuration: 0.25) { self.letterOverlay.alpha = 0 }
        }
    }

    // MARK: Click wheel

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        guard state == .ready, !entries.isEmpty else { return }
        let now = CACurrentMediaTime()
        tickTimes.append(now)
        tickTimes.removeAll { now - $0 > Self.fastWindow }

        let fast = tickTimes.count >= Self.fastTickCount && letterStarts.count > 1
        if fast {
            if now - lastJump >= Self.jumpInterval {
                jumpLetter(rotationDirection)
                lastJump = now
                pimSelectRow(tableView, counter)
            }
            showOverlay()
            return
        }

        if rotationDirection == .CLOCKWISE {
            if counter < entries.count - 1 { counter += 1 }
        } else {
            if counter > 0 { counter -= 1 }
        }
        pimSelectRow(tableView, counter)
        // While the letter is still showing, keep it in step with the selection.
        if overlayTimer != nil { showOverlay() }
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
        guard pressure == .NORMAL, state == .ready, counter < entries.count else { return }
        let e = entries[counter]
        let vc = ContactDetailViewController(identifier: e.identifier, name: e.name, store: store)
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension ContactsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        state == .ready ? entries.count : 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = entries[indexPath.row].name
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 30 }
}

/// The glossy top-half highlight on the letter overlay.
private final class PIMOverlayShine: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let g = layer as! CAGradientLayer
        g.colors = [UIColor(white: 1, alpha: 0.28).cgColor, UIColor(white: 1, alpha: 0.06).cgColor]
        g.startPoint = CGPoint(x: 0.5, y: 0)
        g.endPoint = CGPoint(x: 0.5, y: 1)
        g.cornerRadius = 14
        g.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
