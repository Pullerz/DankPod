//
//  NotesViewController.swift
//  Classic
//
//  Extras › Notes: list of plain-text notes plus a "New Note" row.
//

import UIKit

class NotesViewController: UIViewController, ClickWheelProtocol {

    private let tableView = UITableView()
    private var notes: [Note] = []
    /// Row 0 is "New Note"; rows 1... are notes.
    private var counter: Int = 0
    private var hasSetupUI = false
    /// Set by the editor after creating a note so the list selects it on return.
    private var pendingSelectionURL: URL?

    private var rowCount: Int { notes.count + 1 }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Notes"
        reloadNotes()
    }

    private func setupUI() {
        guard !hasSetupUI else { return }
        view.backgroundColor = .white
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        tableView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        hasSetupUI = true
    }

    @objc private func appWillEnterForeground() {
        // Files may have been added/removed via the Files app while we were away.
        guard isViewLoaded, view.window != nil, navigationController?.topViewController === self else { return }
        reloadNotes()
    }

    private func reloadNotes() {
        // Remember what was selected so the selection survives a reload.
        let previousURL: URL? = (counter >= 1 && counter - 1 < notes.count) ? notes[counter - 1].url : nil
        notes = NotesStore.allNotes()

        if let url = pendingSelectionURL ?? previousURL,
           let idx = notes.firstIndex(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            counter = idx + 1
        }
        pendingSelectionURL = nil
        counter = max(0, min(counter, rowCount - 1))

        tableView.reloadData()
        selectCurrentRow(scroll: true)
    }

    private func selectCurrentRow(scroll: Bool) {
        guard counter < tableView.numberOfRows(inSection: 0) else { return }
        let ip = IndexPath(row: counter, section: 0)
        tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
        if scroll {
            tableView.scrollToRow(at: ip, at: .none, animated: false)
        }
    }

    // MARK: - ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if rotationDirection == .CLOCKWISE {
            guard counter + 1 < rowCount else { return }
            counter += 1
        } else {
            guard counter > 0 else { return }
            counter -= 1
        }
        selectCurrentRow(scroll: true)
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        }
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
        openRow(counter)
    }

    private func openRow(_ row: Int) {
        if row == 0 {
            let editor = NoteEditorViewController()
            editor.onSave = { [weak self] note in
                self?.pendingSelectionURL = note.url
            }
            navigationController?.pushViewController(editor, animated: true)
        } else if row - 1 < notes.count {
            let reader = NoteReaderViewController(note: notes[row - 1])
            reader.onNoteChanged = { [weak self] note in
                // Keep the selection on a note that was renamed while editing.
                self?.pendingSelectionURL = note.url
            }
            navigationController?.pushViewController(reader, animated: true)
        }
    }
}

extension NotesViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rowCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = indexPath.row == 0 ? "New Note" : notes[indexPath.row - 1].title
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        counter = indexPath.row
        openRow(counter)
    }
}
