//
//  NoteReaderViewController.swift
//  Classic
//
//  Shows one note as on the iPod Notes reader: the click wheel scrolls the text,
//  Next/Previous page through it, and the center button opens an action list.
//

import UIKit

class NoteReaderViewController: UIViewController, ClickWheelProtocol, UITextViewDelegate {

    private(set) var note: Note
    /// Called when the note is renamed by an edit, so the list can follow it.
    var onNoteChanged: ((Note) -> Void)?

    private let textView = UITextView()
    private let indicatorTrack = UIView()
    private let indicatorThumb = UIView()
    private let thumbGradient = CAGradientLayer()
    private var hasSetupUI = false
    private var noteText: String = ""

    private let bodyFont = UIFont(name: "Helvetica", size: 15) ?? .systemFont(ofSize: 15)
    private let titleFont = UIFont(name: "Helvetica-Bold", size: 15) ?? .boldSystemFont(ofSize: 15)
    private var lineStep: CGFloat { ceil(bodyFont.lineHeight) }

    /// Where wheel scrolling is heading; accumulates ticks during animation.
    private var targetOffsetY: CGFloat = 0

    // Action list overlay
    private enum ActionMode { case none, actions, confirmDelete }
    private var actionMode: ActionMode = .none
    private let actionList = NoteActionListView()

    init(note: Note) {
        self.note = note
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = note.title
        loadText()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hideActionList(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        clampOffset()
        updateIndicator()
    }

    // MARK: - UI

    private func setupUI() {
        guard !hasSetupUI else { return }
        view.backgroundColor = .white

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.backgroundColor = .white
        textView.textColor = .black
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.alwaysBounceVertical = false
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 14, right: 18)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leftAnchor.constraint(equalTo: view.leftAnchor),
            textView.rightAnchor.constraint(equalTo: view.rightAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Slim iPod-style scroll indicator: an outlined track with a glossy blue thumb.
        indicatorTrack.backgroundColor = UIColor(white: 0.93, alpha: 1)
        indicatorTrack.layer.borderColor = UIColor(white: 0.55, alpha: 1).cgColor
        indicatorTrack.layer.borderWidth = 0.5
        indicatorTrack.layer.cornerRadius = 3
        indicatorTrack.clipsToBounds = true
        indicatorTrack.isUserInteractionEnabled = false
        view.addSubview(indicatorTrack)

        thumbGradient.colors = [UIColor.gradientLightBlue.cgColor, UIColor.gradientDarkBlue.cgColor]
        thumbGradient.startPoint = CGPoint(x: 0, y: 0.5)
        thumbGradient.endPoint = CGPoint(x: 1, y: 0.5)
        indicatorThumb.layer.addSublayer(thumbGradient)
        indicatorThumb.layer.cornerRadius = 3
        indicatorThumb.clipsToBounds = true
        indicatorTrack.addSubview(indicatorThumb)

        actionList.isHidden = true
        actionList.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionList)
        NSLayoutConstraint.activate([
            actionList.topAnchor.constraint(equalTo: view.topAnchor),
            actionList.leftAnchor.constraint(equalTo: view.leftAnchor),
            actionList.rightAnchor.constraint(equalTo: view.rightAnchor),
            actionList.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        actionList.onTapRow = { [weak self] row in
            self?.actionList.selectedIndex = row
            self?.performSelectedAction()
        }
        actionList.onTapOutside = { [weak self] in self?.hideActionList(animated: true) }

        hasSetupUI = true
    }

    private func loadText() {
        if let text = NotesStore.read(note) {
            noteText = text
        } else {
            noteText = ""
        }
        textView.attributedText = attributedText(for: noteText, title: note.title)
        view.layoutIfNeeded()
        targetOffsetY = textView.contentOffset.y
        clampOffset()
        updateIndicator()
    }

    /// Title in bold at the top, body below. If the text already starts with the
    /// title line, that line is shown in bold instead of repeating the title.
    private func attributedText(for text: String, title: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        para.paragraphSpacing = 2
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.black, .paragraphStyle: para]
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor.black, .paragraphStyle: para]

        let result = NSMutableAttributedString()
        var lines = text.components(separatedBy: .newlines)
        // Drop leading blank lines.
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        if let first = lines.first, NotesStore.sanitise(first) == title {
            result.append(NSAttributedString(string: first.trimmingCharacters(in: .whitespaces), attributes: titleAttrs))
            lines.removeFirst()
            let body = lines.joined(separator: "\n")
            if !body.isEmpty {
                result.append(NSAttributedString(string: "\n" + body, attributes: bodyAttrs))
            }
        } else {
            result.append(NSAttributedString(string: title, attributes: titleAttrs))
            let body = lines.joined(separator: "\n")
            result.append(NSAttributedString(string: "\n\n" + (body.isEmpty ? "" : body), attributes: bodyAttrs))
        }
        return result
    }

    // MARK: - Scrolling

    private var maxOffsetY: CGFloat {
        max(0, textView.contentSize.height - textView.bounds.height)
    }

    private func clampOffset() {
        let y = min(max(textView.contentOffset.y, 0), maxOffsetY)
        if y != textView.contentOffset.y {
            textView.contentOffset = CGPoint(x: 0, y: y)
        }
        targetOffsetY = min(max(targetOffsetY, 0), maxOffsetY)
    }

    private func scroll(by delta: CGFloat, duration: TimeInterval) {
        let newTarget = min(max(targetOffsetY + delta, 0), maxOffsetY)
        guard newTarget != targetOffsetY else { return }
        targetOffsetY = newTarget
        UIView.animate(withDuration: duration, delay: 0,
                       options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]) {
            self.textView.contentOffset = CGPoint(x: 0, y: newTarget)
            self.updateIndicator()
        }
    }

    private func updateIndicator() {
        let viewH = view.bounds.height
        let contentH = textView.contentSize.height
        let scrollable = contentH > viewH + 1
        indicatorTrack.isHidden = !scrollable
        guard scrollable, viewH > 0 else { return }

        let trackW: CGFloat = 6
        let inset: CGFloat = 4
        indicatorTrack.frame = CGRect(x: view.bounds.width - trackW - 4, y: inset,
                                      width: trackW, height: viewH - inset * 2)
        let trackH = indicatorTrack.bounds.height
        let thumbH = max(16, trackH * viewH / contentH)
        let progress = maxOffsetY > 0 ? min(max(textView.contentOffset.y / maxOffsetY, 0), 1) : 0
        let thumbY = (trackH - thumbH) * progress
        indicatorThumb.frame = CGRect(x: 0, y: thumbY, width: trackW, height: thumbH)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        thumbGradient.frame = indicatorThumb.bounds
        CATransaction.commit()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Touch scrolling (the wheel is the primary input, but keep them in sync).
        if scrollView.isTracking || scrollView.isDecelerating {
            targetOffsetY = scrollView.contentOffset.y
            updateIndicator()
        }
    }

    // MARK: - Action list

    private func showActions() {
        actionMode = .actions
        actionList.configure(title: note.title, items: ["Edit", "Delete", "Cancel"], selected: 0)
        actionList.show(animated: true)
    }

    private func showDeleteConfirm() {
        actionMode = .confirmDelete
        actionList.configure(title: "Delete this note?", items: ["Delete Note", "Cancel"], selected: 1)
    }

    private func hideActionList(animated: Bool) {
        guard actionMode != .none else { return }
        actionMode = .none
        actionList.hide(animated: animated)
    }

    private func performSelectedAction() {
        let item = actionList.selectedItem
        switch actionMode {
        case .none:
            break
        case .actions:
            switch item {
            case "Edit":
                hideActionList(animated: false)
                openEditor()
            case "Delete":
                showDeleteConfirm()
            default:
                hideActionList(animated: true)
            }
        case .confirmDelete:
            if item == "Delete Note" {
                hideActionList(animated: false)
                NotesStore.delete(note)
                navigationController?.popViewController(animated: true)
            } else {
                hideActionList(animated: true)
            }
        }
    }

    private func openEditor() {
        let editor = NoteEditorViewController()
        editor.editingNote = note
        editor.onSave = { [weak self] updated in
            guard let self = self else { return }
            if updated != self.note {
                self.note = updated
                self.onNoteChanged?(updated)
            }
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    // MARK: - ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if actionMode != .none {
            actionList.move(by: rotationDirection == .CLOCKWISE ? 1 : -1)
            return
        }
        scroll(by: rotationDirection == .CLOCKWISE ? lineStep : -lineStep, duration: 0.12)
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, actionMode == .none else { return }
        scroll(by: max(lineStep, textView.bounds.height - lineStep * 2), duration: 0.25)
    }

    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, actionMode == .none else { return }
        scroll(by: -max(lineStep, textView.bounds.height - lineStep * 2), duration: 0.25)
    }

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            if actionMode != .none {
                hideActionList(animated: true)
            } else {
                navigationController?.popViewController(animated: true)
            }
        } else if pressure == .FORCE {
            navigationController?.popToRootViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL else { return }
        if actionMode == .none {
            showActions()
        } else {
            performSelectedAction()
        }
    }
}

// MARK: - iPod-style overlay action list

/// A dimmed overlay with a small rounded panel: a silver header and a list of
/// CustomTableViewCell rows driven by the click wheel.
final class NoteActionListView: UIView, UITableViewDataSource, UITableViewDelegate {

    var onTapRow: ((Int) -> Void)?
    var onTapOutside: (() -> Void)?

    private(set) var items: [String] = []
    var selectedIndex: Int = 0 {
        didSet { selectCurrent() }
    }
    var selectedItem: String? {
        (selectedIndex >= 0 && selectedIndex < items.count) ? items[selectedIndex] : nil
    }

    private let dim = UIView()
    private let panel = UIView()
    private let header = UIView()
    private let headerGradient = CAGradientLayer()
    private let titleLabel = UILabel()
    private let table = UITableView()
    private var tableHeight: NSLayoutConstraint!

    private let rowHeight: CGFloat = 30
    private let headerHeight: CGFloat = 26

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = .clear

        dim.backgroundColor = UIColor(white: 0, alpha: 0.35)
        dim.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dim)
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapped)))

        // Shadow host + clipped panel.
        let shadowHost = UIView()
        shadowHost.translatesAutoresizingMaskIntoConstraints = false
        shadowHost.layer.shadowColor = UIColor.black.cgColor
        shadowHost.layer.shadowOpacity = 0.45
        shadowHost.layer.shadowRadius = 6
        shadowHost.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(shadowHost)

        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = .white
        panel.layer.cornerRadius = 8
        panel.layer.borderWidth = 1
        panel.layer.borderColor = UIColor(white: 0.45, alpha: 1).cgColor
        panel.clipsToBounds = true
        shadowHost.addSubview(panel)

        header.translatesAutoresizingMaskIntoConstraints = false
        headerGradient.colors = [UIColor(white: 0.98, alpha: 1).cgColor,
                                 UIColor(white: 0.86, alpha: 1).cgColor,
                                 UIColor(white: 0.76, alpha: 1).cgColor]
        headerGradient.locations = [0, 0.5, 1]
        header.layer.addSublayer(headerGradient)
        let headerLine = UIView()
        headerLine.translatesAutoresizingMaskIntoConstraints = false
        headerLine.backgroundColor = UIColor(white: 0.5, alpha: 1)
        header.addSubview(headerLine)
        panel.addSubview(header)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont(name: "Helvetica-Bold", size: 14)
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        header.addSubview(titleLabel)

        table.translatesAutoresizingMaskIntoConstraints = false
        table.separatorStyle = .none
        table.isScrollEnabled = false
        table.dataSource = self
        table.delegate = self
        panel.addSubview(table)

        tableHeight = table.heightAnchor.constraint(equalToConstant: rowHeight * 3)
        NSLayoutConstraint.activate([
            dim.topAnchor.constraint(equalTo: topAnchor),
            dim.leftAnchor.constraint(equalTo: leftAnchor),
            dim.rightAnchor.constraint(equalTo: rightAnchor),
            dim.bottomAnchor.constraint(equalTo: bottomAnchor),

            shadowHost.centerXAnchor.constraint(equalTo: centerXAnchor),
            shadowHost.centerYAnchor.constraint(equalTo: centerYAnchor),
            shadowHost.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.72),

            panel.topAnchor.constraint(equalTo: shadowHost.topAnchor),
            panel.leftAnchor.constraint(equalTo: shadowHost.leftAnchor),
            panel.rightAnchor.constraint(equalTo: shadowHost.rightAnchor),
            panel.bottomAnchor.constraint(equalTo: shadowHost.bottomAnchor),

            header.topAnchor.constraint(equalTo: panel.topAnchor),
            header.leftAnchor.constraint(equalTo: panel.leftAnchor),
            header.rightAnchor.constraint(equalTo: panel.rightAnchor),
            header.heightAnchor.constraint(equalToConstant: headerHeight),

            headerLine.leftAnchor.constraint(equalTo: header.leftAnchor),
            headerLine.rightAnchor.constraint(equalTo: header.rightAnchor),
            headerLine.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            headerLine.heightAnchor.constraint(equalToConstant: 0.5),

            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.leftAnchor.constraint(equalTo: header.leftAnchor, constant: 10),
            titleLabel.rightAnchor.constraint(equalTo: header.rightAnchor, constant: -10),

            table.topAnchor.constraint(equalTo: header.bottomAnchor),
            table.leftAnchor.constraint(equalTo: panel.leftAnchor),
            table.rightAnchor.constraint(equalTo: panel.rightAnchor),
            table.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            tableHeight,
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        headerGradient.frame = header.bounds
        CATransaction.commit()
        if let host = panel.superview {
            host.layer.shadowPath = UIBezierPath(roundedRect: host.bounds, cornerRadius: 8).cgPath
        }
    }

    func configure(title: String, items: [String], selected: Int) {
        titleLabel.text = title
        self.items = items
        tableHeight.constant = rowHeight * CGFloat(items.count)
        table.reloadData()
        layoutIfNeeded()
        selectedIndex = max(0, min(selected, items.count - 1))
    }

    func move(by delta: Int) {
        let next = selectedIndex + delta
        guard next >= 0, next < items.count else { return }
        selectedIndex = next
    }

    private func selectCurrent() {
        guard selectedIndex >= 0, selectedIndex < table.numberOfRows(inSection: 0) else { return }
        table.selectRow(at: IndexPath(row: selectedIndex, section: 0), animated: false, scrollPosition: .none)
    }

    private var visibilityToken = 0

    func show(animated: Bool) {
        visibilityToken += 1
        superview?.bringSubviewToFront(self)
        isHidden = false
        guard animated else { alpha = 1; return }
        alpha = 0
        panel.superview?.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.18) {
            self.alpha = 1
            self.panel.superview?.transform = .identity
        }
    }

    func hide(animated: Bool) {
        visibilityToken += 1
        let token = visibilityToken
        guard animated else {
            isHidden = true
            alpha = 1
            return
        }
        UIView.animate(withDuration: 0.15, animations: {
            self.alpha = 0
        }, completion: { _ in
            guard token == self.visibilityToken else { return }
            self.isHidden = true
            self.alpha = 1
        })
    }

    @objc private func dimTapped() {
        onTapOutside?()
    }

    // MARK: Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.accessoryType = .none
        cell.selectionStyle = .none
        cell.label.text = items[indexPath.row]
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return rowHeight
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onTapRow?(indexPath.row)
    }
}
