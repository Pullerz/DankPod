//
//  ContactDetailViewController.swift
//  Classic
//
//  A single contact's card: name and organisation, then phones, emails, addresses
//  and birthday as iPod-style rows. The card scrolls with the wheel.
//

import UIKit
import Contacts

class ContactDetailViewController: UIViewController, ClickWheelProtocol {
    private let identifier: String
    private let fallbackName: String
    private let store: CNContactStore
    private let card = PIMCardView()

    init(identifier: String, name: String, store: CNContactStore) {
        self.identifier = identifier
        self.fallbackName = name
        self.store = store
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
        card.addTitle(fallbackName)
        load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Contacts"
    }

    /// Fetches the detail keys for just this contact, off the main thread.
    private func load() {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
        ]
        let store = self.store
        let identifier = self.identifier
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let contact = try? store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
            DispatchQueue.main.async {
                self?.build(contact)
            }
        }
    }

    private func build(_ contact: CNContact?) {
        card.removeAll()
        guard let contact = contact else {
            card.addTitle(fallbackName)
            card.addSeparator()
            card.addBody("This contact is no longer available.", color: UIColor(white: 0.45, alpha: 1))
            return
        }

        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        card.addTitle(name.isEmpty ? fallbackName : name)
        let orgParts = [contact.jobTitle, contact.organizationName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !orgParts.isEmpty && !(name.isEmpty && orgParts.last == fallbackName && orgParts.count == 1) {
            card.addSubtitle(orgParts.joined(separator: ", "), dotColor: nil)
        }
        card.addSeparator()

        var rows = 0
        for phone in contact.phoneNumbers {
            card.addField(label: Self.labelText(phone.label, fallback: "phone"), value: phone.value.stringValue)
            rows += 1
        }
        for email in contact.emailAddresses {
            card.addField(label: Self.labelText(email.label, fallback: "email"), value: email.value as String)
            rows += 1
        }
        let addressFormatter = CNPostalAddressFormatter()
        addressFormatter.style = .mailingAddress
        for address in contact.postalAddresses {
            let text = addressFormatter.string(from: address.value).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            card.addField(label: Self.labelText(address.label, fallback: "address"), value: text)
            rows += 1
        }
        if let birthday = contact.birthday, let text = Self.birthdayText(birthday) {
            card.addField(label: "birthday", value: text)
            rows += 1
        }
        if rows == 0 {
            card.addBody("No Details", color: UIColor(white: 0.45, alpha: 1))
        }
    }

    private static func labelText(_ label: String?, fallback: String) -> String {
        guard let label = label, !label.isEmpty else { return fallback }
        let text = CNLabeledValue<NSString>.localizedString(forLabel: label).lowercased()
        return text.isEmpty ? fallback : text
    }

    private static func birthdayText(_ components: DateComponents) -> String? {
        var comps = components
        let calendar = comps.calendar ?? Calendar(identifier: .gregorian)
        let hasYear = comps.year != nil && comps.year != NSDateComponentUndefined
        if !hasYear { comps.year = 2000 } // leap year, so Feb 29 works
        comps.calendar = calendar
        guard let date = calendar.date(from: comps) else { return nil }
        let f = DateFormatter()
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate(hasYear ? "MMMM d yyyy" : "MMMM d")
        return f.string(from: date)
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

// MARK: - Shared scrolling info card (Contacts and Calendars)

/// A white iPod "info" page: stacked rows in a scroll view moved by the click wheel,
/// with the iPod's narrow scroll bar on the right when the content overflows.
final class PIMCardView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let track = UIView()
    private let thumb = UIView()
    private let thumbGradient = CAGradientLayer()
    private static let barWidth: CGFloat = 8
    private static let step: CGFloat = 22

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.delegate = self
        addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 7
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let rightInset: CGFloat = 14 + Self.barWidth + 4
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leftAnchor.constraint(equalTo: leftAnchor),
            scrollView.rightAnchor.constraint(equalTo: rightAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 10),
            stack.leftAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leftAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(14 + rightInset)),
        ])

        track.backgroundColor = UIColor(white: 0.97, alpha: 1)
        track.layer.borderColor = UIColor(white: 0.55, alpha: 1).cgColor
        track.layer.borderWidth = 1
        track.isUserInteractionEnabled = false
        addSubview(track)

        thumbGradient.colors = [UIColor.gradientLightBlue.cgColor, UIColor.gradientDarkBlue.cgColor]
        thumbGradient.startPoint = CGPoint(x: 0, y: 0.5)
        thumbGradient.endPoint = CGPoint(x: 1, y: 0.5)
        thumb.layer.addSublayer(thumbGradient)
        thumb.layer.borderColor = UIColor(white: 0, alpha: 0.35).cgColor
        thumb.layer.borderWidth = 0.5
        thumb.isUserInteractionEnabled = false
        track.addSubview(thumb)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Content

    func removeAll() {
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        scrollView.contentOffset = .zero
        setNeedsLayout()
    }

    func addTitle(_ text: String) {
        let l = makeLabel(text, font: UIFont(name: "Helvetica-Bold", size: 18)!, color: .black)
        stack.addArrangedSubview(l)
    }

    func addSubtitle(_ text: String, dotColor: UIColor?) {
        let l = makeLabel(text, font: UIFont(name: "Helvetica-Bold", size: 13)!, color: UIColor(white: 0.4, alpha: 1))
        guard let dotColor = dotColor else { stack.addArrangedSubview(l); return }
        let dot = UIView()
        dot.backgroundColor = dotColor
        dot.layer.cornerRadius = 4.5
        dot.layer.borderWidth = 0.5
        dot.layer.borderColor = UIColor(white: 0, alpha: 0.35).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 9).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 9).isActive = true
        let row = UIStackView(arrangedSubviews: [dot, l])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        stack.addArrangedSubview(row)
    }

    func addSeparator() {
        let line = UIView()
        line.backgroundColor = UIColor(white: 0.8, alpha: 1)
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stack.addArrangedSubview(line)
    }

    /// "mobile   07700 900123" — small grey label column, bold value (multi-line OK).
    func addField(label: String, value: String) {
        let key = makeLabel(label, font: UIFont(name: "Helvetica-Bold", size: 12)!, color: UIColor(white: 0.45, alpha: 1))
        key.numberOfLines = 1
        key.adjustsFontSizeToFitWidth = true
        key.minimumScaleFactor = 0.75
        key.translatesAutoresizingMaskIntoConstraints = false
        key.widthAnchor.constraint(equalToConstant: 66).isActive = true
        let val = makeLabel(value, font: UIFont(name: "Helvetica-Bold", size: 14)!, color: .black)
        let row = UIStackView(arrangedSubviews: [key, val])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .firstBaseline
        stack.addArrangedSubview(row)
    }

    func addHeading(_ text: String) {
        stack.addArrangedSubview(makeLabel(text, font: UIFont(name: "Helvetica-Bold", size: 12)!, color: UIColor(white: 0.45, alpha: 1)))
    }

    func addBody(_ text: String, color: UIColor = .black) {
        stack.addArrangedSubview(makeLabel(text, font: UIFont(name: "Helvetica-Bold", size: 13)!, color: color))
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = font
        l.textColor = color
        l.numberOfLines = 0
        l.lineBreakMode = .byWordWrapping
        return l
    }

    // MARK: Scrolling

    func scroll(_ direction: RotationDirection) {
        layoutIfNeeded()
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        guard maxY > 0 else { return }
        let delta = direction == .CLOCKWISE ? Self.step : -Self.step
        let y = min(max(scrollView.contentOffset.y + delta, 0), maxY)
        scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        updateScrollBar()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateScrollBar()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the offset valid if the content shrank (e.g. after a reload).
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        if scrollView.contentOffset.y > maxY {
            scrollView.contentOffset = CGPoint(x: 0, y: maxY)
        }
        updateScrollBar()
    }

    private func updateScrollBar() {
        let content = scrollView.contentSize.height
        let visible = scrollView.bounds.height
        guard content > visible + 1, visible > 0 else { track.isHidden = true; return }
        track.isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = CGRect(x: bounds.width - Self.barWidth - 5, y: 4, width: Self.barWidth, height: bounds.height - 8)
        let inner = track.bounds.insetBy(dx: 1, dy: 1)
        let h = max(14, inner.height * visible / content)
        let progress = min(max(scrollView.contentOffset.y / (content - visible), 0), 1)
        thumb.frame = CGRect(x: inner.minX, y: inner.minY + (inner.height - h) * progress, width: inner.width, height: h)
        thumbGradient.frame = thumb.bounds
        CATransaction.commit()
    }
}
