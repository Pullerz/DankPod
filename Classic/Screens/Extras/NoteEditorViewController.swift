//
//  NoteEditorViewController.swift
//  Classic
//
//  Creates or edits a note with the iPhone keyboard. The click wheel is hidden
//  while typing (like Search), so Cancel/Save live in a slim silver toolbar.
//

import UIKit

class NoteEditorViewController: UIViewController, ClickWheelProtocol {

    /// The note being edited, or nil to create a new one.
    var editingNote: Note?
    /// Called with the saved (possibly renamed / newly created) note before popping.
    var onSave: ((Note) -> Void)?

    private let toolbar = UIView()
    private let toolbarGradient = CAGradientLayer()
    private let cancelButton = UIButton(type: .custom)
    private let saveButton = UIButton(type: .custom)
    private let textView = UITextView()
    private var originalText: String = ""
    private var hasSetupUI = false
    private var isFinishing = false

    private let toolbarHeight: CGFloat = 32

    override func viewDidLoad() {
        super.viewDidLoad()
        if let note = editingNote {
            originalText = NotesStore.read(note) ?? ""
        }
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = editingNote == nil ? "New Note" : "Edit Note"
        AppDelegate.baseVC.setClickWheelHidden(true, animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        textView.resignFirstResponder()
        AppDelegate.baseVC.setClickWheelHidden(false, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        toolbarGradient.frame = toolbar.bounds
        CATransaction.commit()
    }

    // MARK: - UI

    private func setupUI() {
        guard !hasSetupUI else { return }
        view.backgroundColor = .white

        // Glossy silver bar, like the iPod title bar.
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbarGradient.colors = [UIColor(white: 0.99, alpha: 1).cgColor,
                                  UIColor(white: 0.90, alpha: 1).cgColor,
                                  UIColor(white: 0.80, alpha: 1).cgColor,
                                  UIColor(white: 0.74, alpha: 1).cgColor]
        toolbarGradient.locations = [0, 0.5, 0.51, 1]
        toolbar.layer.addSublayer(toolbarGradient)
        toolbar.layer.shadowColor = UIColor.black.cgColor
        toolbar.layer.shadowOpacity = 0.35
        toolbar.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        toolbar.layer.shadowRadius = 0.5
        view.addSubview(toolbar)

        let bottomLine = UIView()
        bottomLine.translatesAutoresizingMaskIntoConstraints = false
        bottomLine.backgroundColor = UIColor(white: 0.55, alpha: 1)
        toolbar.addSubview(bottomLine)

        styleButton(cancelButton, title: "Cancel", primary: false)
        styleButton(saveButton, title: "Save", primary: true)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        toolbar.addSubview(cancelButton)
        toolbar.addSubview(saveButton)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = UIFont(name: "Helvetica", size: 15)
        textView.textColor = .black
        textView.backgroundColor = .white
        textView.tintColor = UIColor.gradientDarkBlue
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.autocapitalizationType = .sentences
        textView.text = originalText
        view.insertSubview(textView, belowSubview: toolbar)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leftAnchor.constraint(equalTo: view.leftAnchor),
            toolbar.rightAnchor.constraint(equalTo: view.rightAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: toolbarHeight),

            bottomLine.leftAnchor.constraint(equalTo: toolbar.leftAnchor),
            bottomLine.rightAnchor.constraint(equalTo: toolbar.rightAnchor),
            bottomLine.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            bottomLine.heightAnchor.constraint(equalToConstant: 0.5),

            cancelButton.leftAnchor.constraint(equalTo: toolbar.leftAnchor, constant: 8),
            cancelButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            cancelButton.heightAnchor.constraint(equalToConstant: 22),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            saveButton.rightAnchor.constraint(equalTo: toolbar.rightAnchor, constant: -8),
            saveButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            saveButton.heightAnchor.constraint(equalToConstant: 22),
            saveButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            textView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            textView.leftAnchor.constraint(equalTo: view.leftAnchor),
            textView.rightAnchor.constraint(equalTo: view.rightAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hasSetupUI = true
    }

    /// Small rounded glossy button: silver for Cancel, iPod blue for Save.
    private func styleButton(_ button: UIButton, title: String, primary: Bool) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont(name: "Helvetica-Bold", size: 12)
        button.setTitleColor(primary ? .white : .black, for: .normal)
        button.setTitleColor(primary ? UIColor(white: 1, alpha: 0.6) : .darkGray, for: .highlighted)
        if primary {
            button.titleLabel?.shadowOffset = CGSize(width: 0, height: -0.5)
            button.setTitleShadowColor(UIColor(white: 0, alpha: 0.35), for: .normal)
        }
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        button.layer.cornerRadius = 5
        button.layer.borderWidth = 0.5
        button.layer.borderColor = (primary ? UIColor(red: 30/255, green: 60/255, blue: 120/255, alpha: 1)
                                            : UIColor(white: 0.45, alpha: 1)).cgColor
        button.clipsToBounds = true

        let top = primary ? UIColor.gradientLightBlue : UIColor(white: 1.0, alpha: 1)
        let bottom = primary ? UIColor.gradientDarkBlue : UIColor(white: 0.80, alpha: 1)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 22)).image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 22), options: [])
            }
            // Specular band on the top half.
            UIColor(white: 1, alpha: 0.25).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 11))
        }
        button.setBackgroundImage(image.resizableImage(withCapInsets: .zero, resizingMode: .stretch), for: .normal)
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        finish()
    }

    @objc private func saveTapped() {
        guard !isFinishing else { return }
        let text = textView.text ?? ""
        if let note = editingNote {
            if text != originalText, let saved = NotesStore.update(note, oldText: originalText, newText: text) {
                onSave?(saved)
            }
        } else if let created = NotesStore.create(text: text) {
            onSave?(created)
        }
        // Empty new note → just discard.
        finish()
    }

    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        textView.resignFirstResponder()
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Keyboard

    @objc private func keyboardWillChange(_ note: Notification) {
        guard isViewLoaded, view.window != nil,
              let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let kbInView = textView.convert(endFrame, from: nil)
        let overlap = max(0, textView.bounds.maxY - kbInView.minY)
        setBottomInset(overlap)
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        setBottomInset(0)
    }

    private func setBottomInset(_ inset: CGFloat) {
        textView.contentInset.bottom = inset
        textView.verticalScrollIndicatorInsets.bottom = inset
        if textView.isFirstResponder, let range = textView.selectedTextRange {
            let caret = textView.caretRect(for: range.end)
            textView.scrollRectToVisible(caret.insetBy(dx: 0, dy: -8), animated: false)
        }
    }

    // MARK: - ClickWheelProtocol (the wheel is hidden while editing)

    func clickWheelDidRotate(rotationDirection: RotationDirection) {}

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {}

    func previousSongPressed(pressure: ClickWheelTouchPressure) {}

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            finish()
        } else if pressure == .FORCE {
            textView.resignFirstResponder()
            navigationController?.popToRootViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {}
}
