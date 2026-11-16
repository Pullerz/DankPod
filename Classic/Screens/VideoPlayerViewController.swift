//
//  VideoPlayerViewController.swift
//  Classic
//

import UIKit
import MediaPlayer
import AVFoundation

/// Full-screen iPod-style video player.
/// Controls: Play/Pause toggles, wheel = volume (or scrubs in scrub mode), Next/Previous = ±30s,
/// Center toggles scrub mode, Menu stops and returns to the list.
class VideoPlayerViewController: UIViewController, ClickWheelProtocol {
    let item: MPMediaItem

    private var player: AVPlayer?
    private let playerLayer = AVPlayerLayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var hasSetupUI = false

    // Overlay
    private let overlay = UIView()
    private let topBar = UIView()
    private let topGradient = CAGradientLayer()
    private let bottomBar = UIView()
    private let bottomGradient = CAGradientLayer()
    private let titleLabel = UILabel()
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let volumeBar = UIProgressView(progressViewStyle: .default)
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let lowVolume = UIImageView(image: #imageLiteral(resourceName: "lowVolume"))
    private let highVolume = UIImageView(image: #imageLiteral(resourceName: "fullVolume"))
    private let scrubDiamond = ScrubberDiamondView()
    private var diamondCenterX: NSLayoutConstraint?
    private var errorView: UIView?

    private var overlayHideTimer: Timer?
    private var volumeHideTimer: Timer?
    private var scrubSeekTimer: Timer?
    private var scrubIdleTimer: Timer?

    private var isScrubbing = false
    private var scrubPosition: TimeInterval?
    private var lastScrubTickTime: CFTimeInterval = 0
    private var isShowingVolume = false

    init(item: MPMediaItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = item.title ?? "Videos"
        setupUI()
        if player == nil && errorView == nil {
            startPlayback()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = view.bounds
        topGradient.frame = topBar.bounds
        bottomGradient.frame = bottomBar.bounds
        CATransaction.commit()
        updateDiamondPosition()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        tearDown()
    }

    deinit {
        // Safety net in case the controller goes away without a disappear.
        if let timeObserver = timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver = endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    private func tearDown() {
        overlayHideTimer?.invalidate(); overlayHideTimer = nil
        volumeHideTimer?.invalidate(); volumeHideTimer = nil
        scrubSeekTimer?.invalidate(); scrubSeekTimer = nil
        scrubIdleTimer?.invalidate(); scrubIdleTimer = nil
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        let hadPlayer = player != nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerLayer.player = nil
        player = nil
        if hadPlayer {
            // Hand the session back: a lingering non-mixable .playback category would make the
            // next click sound (which restarts the audio engine) interrupt the user's music.
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            // A video that ends on its own pops without going through menuPressed.
            AppDelegate.baseVC.setPlaybackIcon(state: .paused)
        }
        isScrubbing = false
        scrubPosition = nil
    }

    // MARK: - UI

    private func setupUI() {
        guard !hasSetupUI else { return }
        hasSetupUI = true
        view.backgroundColor = .black
        view.clipsToBounds = true

        playerLayer.videoGravity = .resizeAspect   // letterboxed
        playerLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(playerLayer)

        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        pin(overlay, to: view)

        // Top: title on a dark glossy gradient.
        topBar.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(topBar)
        topBar.topAnchor.constraint(equalTo: overlay.topAnchor).isActive = true
        topBar.leftAnchor.constraint(equalTo: overlay.leftAnchor).isActive = true
        topBar.rightAnchor.constraint(equalTo: overlay.rightAnchor).isActive = true
        topBar.heightAnchor.constraint(equalToConstant: 36).isActive = true
        topGradient.colors = [UIColor(white: 0, alpha: 0.85).cgColor, UIColor(white: 0, alpha: 0.45).cgColor]
        topBar.layer.addSublayer(topGradient)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont(name: "Helvetica-Bold", size: 15)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = item.title ?? "Untitled"
        topBar.addSubview(titleLabel)
        titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor).isActive = true
        titleLabel.leftAnchor.constraint(equalTo: topBar.leftAnchor, constant: 12).isActive = true
        titleLabel.rightAnchor.constraint(equalTo: topBar.rightAnchor, constant: -12).isActive = true

        // Bottom: progress / volume bar with times.
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(bottomBar)
        bottomBar.bottomAnchor.constraint(equalTo: overlay.bottomAnchor).isActive = true
        bottomBar.leftAnchor.constraint(equalTo: overlay.leftAnchor).isActive = true
        bottomBar.rightAnchor.constraint(equalTo: overlay.rightAnchor).isActive = true
        bottomBar.heightAnchor.constraint(equalToConstant: 56).isActive = true
        bottomGradient.colors = [UIColor(white: 0, alpha: 0.45).cgColor, UIColor(white: 0, alpha: 0.85).cgColor]
        bottomBar.layer.addSublayer(bottomGradient)

        for bar in [progressBar, volumeBar] {
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.progressImage = #imageLiteral(resourceName: "progress").resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1), resizingMode: .tile)
            bar.trackImage = #imageLiteral(resourceName: "track").resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1), resizingMode: .tile)
            bar.layer.shadowColor = UIColor.black.cgColor
            bar.layer.shadowOpacity = 0.25
            bar.layer.shadowOffset = CGSize(width: 0, height: 2)
            bottomBar.addSubview(bar)
            bar.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 8).isActive = true
            bar.leftAnchor.constraint(equalTo: bottomBar.leftAnchor, constant: 16).isActive = true
            bar.rightAnchor.constraint(equalTo: bottomBar.rightAnchor, constant: -16).isActive = true
            bar.heightAnchor.constraint(equalToConstant: 16).isActive = true
        }
        progressBar.setProgress(0, animated: false)
        volumeBar.alpha = 0

        for label in [elapsedLabel, remainingLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = UIFont(name: "Helvetica-Bold", size: 13)
            label.textColor = .white
            label.text = "0:00"
            bottomBar.addSubview(label)
            label.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 6).isActive = true
        }
        elapsedLabel.leftAnchor.constraint(equalTo: progressBar.leftAnchor).isActive = true
        remainingLabel.rightAnchor.constraint(equalTo: progressBar.rightAnchor).isActive = true
        remainingLabel.textAlignment = .right
        remainingLabel.text = "-0:00"

        for icon in [lowVolume, highVolume] {
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.alpha = 0
            bottomBar.addSubview(icon)
            icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
            icon.centerYAnchor.constraint(equalTo: elapsedLabel.centerYAnchor).isActive = true
        }
        lowVolume.leftAnchor.constraint(equalTo: progressBar.leftAnchor).isActive = true
        highVolume.rightAnchor.constraint(equalTo: progressBar.rightAnchor).isActive = true

        scrubDiamond.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(scrubDiamond)
        scrubDiamond.widthAnchor.constraint(equalToConstant: 14).isActive = true
        scrubDiamond.heightAnchor.constraint(equalToConstant: 14).isActive = true
        scrubDiamond.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor).isActive = true
        let cx = scrubDiamond.centerXAnchor.constraint(equalTo: progressBar.leftAnchor)
        cx.isActive = true
        diamondCenterX = cx
        scrubDiamond.alpha = 0
    }

    private func pin(_ subview: UIView, to container: UIView) {
        subview.topAnchor.constraint(equalTo: container.topAnchor).isActive = true
        subview.leftAnchor.constraint(equalTo: container.leftAnchor).isActive = true
        subview.rightAnchor.constraint(equalTo: container.rightAnchor).isActive = true
        subview.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
    }

    /// iPod-style message for items that can't be played (DRM-protected or cloud-only: nil assetURL).
    private func showUnplayable() {
        overlay.isHidden = true
        let message = makePodEmptyStateView(title: "This video can't be played",
                                            subtitle: "It may be protected or not downloaded to this device.")
        message.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(message)
        pin(message, to: view)
        errorView = message
    }

    // MARK: - Playback

    private func startPlayback() {
        guard let url = item.assetURL else {
            showUnplayable()
            return
        }

        // Video takes over the audio: stop the system music player.
        if AppDelegate.music.musicPlayer.playbackState == .playing {
            AppDelegate.music.musicPlayer.pause()
        }
        AppDelegate.baseVC.setPlaybackIcon(state: .playing)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let player = AVPlayer(url: url)
        self.player = player
        playerLayer.player = player

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                      queue: .main) { [weak self] _ in
            self?.updateProgress()
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: player.currentItem,
                                                             queue: .main) { [weak self] _ in
            // Like the iPod, return to the list when the video finishes.
            self?.navigationController?.popViewController(animated: true)
        }

        player.play()
        showOverlay()
    }

    private var duration: TimeInterval {
        if let d = player?.currentItem?.duration.seconds, d.isFinite, d > 0 { return d }
        return item.playbackDuration
    }

    private var currentTime: TimeInterval {
        let t = player?.currentTime().seconds ?? 0
        return t.isFinite ? t : 0
    }

    private func updateProgress() {
        let total = duration
        guard total > 0 else { return }
        let time = scrubPosition ?? currentTime
        progressBar.setProgress(Float(time / total), animated: false)
        elapsedLabel.text = formatVideoTime(time)
        remainingLabel.text = "-" + formatVideoTime(max(total - time, 0))
        updateDiamondPosition()
    }

    private func updateDiamondPosition() {
        diamondCenterX?.constant = CGFloat(progressBar.progress) * progressBar.bounds.width
    }

    private func seek(to seconds: TimeInterval) {
        guard let player = player else { return }
        let clamped = min(max(seconds, 0), max(duration - 0.5, 0))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateProgress()
    }

    // MARK: - Overlay

    /// Shows the overlay and schedules it to fade after 3s (it stays while scrubbing).
    private func showOverlay() {
        guard errorView == nil else { return }
        UIView.animate(withDuration: 0.2) { self.overlay.alpha = 1 }
        overlayHideTimer?.invalidate()
        overlayHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.isScrubbing, self.player?.rate ?? 0 > 0 else { return }
            UIView.animate(withDuration: 0.5) { self.overlay.alpha = 0 }
        }
    }

    private func applyBarVisibility() {
        UIView.animate(withDuration: 0.2) {
            let volume = self.isShowingVolume && !self.isScrubbing
            self.progressBar.alpha = volume ? 0 : 1
            self.elapsedLabel.alpha = volume ? 0 : 1
            self.remainingLabel.alpha = volume ? 0 : 1
            self.volumeBar.alpha = volume ? 1 : 0
            self.lowVolume.alpha = volume ? 1 : 0
            self.highVolume.alpha = volume ? 1 : 0
            self.scrubDiamond.alpha = self.isScrubbing ? 1 : 0
        }
    }

    // MARK: - Volume

    private func adjustVolume(_ direction: RotationDirection) {
        if !isShowingVolume {
            volumeBar.setProgress(AVAudioSession.sharedInstance().outputVolume, animated: false)
        }
        isShowingVolume = true
        applyBarVisibility()
        let limit = SettingsStore.shared.volumeLimit
        let newValue = direction == .CLOCKWISE ? min(volumeBar.progress + 0.1, limit) : max(volumeBar.progress - 0.1, 0)
        volumeBar.setProgress(newValue, animated: true)
        AppDelegate.music.setVolume(newValue)
        volumeHideTimer?.invalidate()
        volumeHideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.isShowingVolume = false
            self.applyBarVisibility()
        }
    }

    // MARK: - Scrubbing

    private func setScrubbing(_ on: Bool) {
        if !on { commitScrub() }
        isScrubbing = on
        lastScrubTickTime = 0
        scrubIdleTimer?.invalidate()
        scrubIdleTimer = nil
        if on {
            isShowingVolume = false
            volumeHideTimer?.invalidate()
            restartScrubIdleTimer()
        }
        applyBarVisibility()
        showOverlay()
    }

    private func restartScrubIdleTimer() {
        scrubIdleTimer?.invalidate()
        scrubIdleTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.setScrubbing(false)
        }
    }

    private func scrub(_ direction: RotationDirection) {
        let total = duration
        guard total > 0 else { return }
        let now = CACurrentMediaTime()
        let interval = lastScrubTickTime > 0 ? now - lastScrubTickTime : 1
        lastScrubTickTime = now
        let acceleration = min(max(0.12 / max(interval, 0.001), 1), 8)
        // Longer videos scrub proportionally faster (~2s per tick for a song-length clip).
        let base = max(2.0, total / 150)
        let step = base * acceleration
        let start = scrubPosition ?? currentTime
        scrubPosition = min(max(start + (direction == .CLOCKWISE ? step : -step), 0), max(total - 0.5, 0))
        updateProgress()
        scrubSeekTimer?.invalidate()
        scrubSeekTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.commitScrub()
        }
        restartScrubIdleTimer()
    }

    private func commitScrub() {
        scrubSeekTimer?.invalidate()
        scrubSeekTimer = nil
        guard let target = scrubPosition else { return }
        scrubPosition = nil
        seek(to: target)
    }

    // MARK: - ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        guard player != nil else { return }
        showOverlay()
        if isScrubbing {
            scrub(rotationDirection)
        } else {
            adjustVolume(rotationDirection)
        }
    }

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, let player = player else { return }
        if player.rate > 0 {
            player.pause()
            AppDelegate.baseVC.setPlaybackIcon(state: .paused)
        } else {
            player.play()
            AppDelegate.baseVC.setPlaybackIcon(state: .playing)
        }
        showOverlay()
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, player != nil else { return }
        scrubPosition = nil
        seek(to: currentTime + 30)
        showOverlay()
    }

    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, player != nil else { return }
        scrubPosition = nil
        seek(to: currentTime - 30)
        showOverlay()
    }

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            tearDown()
            AppDelegate.baseVC.setPlaybackIcon(state: .paused)
            navigationController?.popViewController(animated: true)
        } else if pressure == .FORCE {
            tearDown()
            AppDelegate.baseVC.setPlaybackIcon(state: .paused)
            navigationController?.popToRootViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, player != nil else { return }
        setScrubbing(!isScrubbing)
    }
}
