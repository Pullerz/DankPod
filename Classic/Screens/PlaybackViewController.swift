//
//  PlaybackViewController.swift
//  Classic
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import MediaPlayer
import AVFoundation

class PlaybackViewController: UIViewController, ClickWheelProtocol {

    var songs: [MPMediaItem]!
    var isPaused: Bool = false
    var startingIndex = -1
    var timer: Timer!
    var volumeTimer: Timer?
    let progressBar = UIProgressView(progressViewStyle: .default)
    let volumeBar = UIProgressView(progressViewStyle: .default)
    let trackNumber = UILabel()
    var lastTrackIndex: Int!
    var albumArt: UIImageView!
    let timeRemaining = UILabel()
    let timeElapsed: UILabel = UILabel()
    var hasSetupUI = false

    let songName = UILabel()
    let artistName = UILabel()
    let albumName = UILabel()


    let highVolume = UIImageView(image: #imageLiteral(resourceName: "fullVolume"))
    let lowVolume = UIImageView(image: #imageLiteral(resourceName: "lowVolume"))

    var lastIndex: Int = 0
    var comingFromHome = false
    var isShuffled = false
    var skipQueueSetup = false

    // MARK: - Center-button modes (iPod classic: Volume → Scrubber → Rating → Lyrics)

    enum NowPlayingMode {
        case volume
        case scrubber
        case rating
        case lyrics
    }

    private(set) var mode: NowPlayingMode = .volume
    /// Leaves Scrubber/Rating and returns to the default (Volume) mode after a few idle seconds.
    private var modeIdleTimer: Timer?
    private let modeIdleTimeout: TimeInterval = 3.0

    // Scrubber
    private let scrubDiamond = ScrubberDiamondView()
    private var diamondCenterX: NSLayoutConstraint?
    /// Pending scrub target while the wheel is turning; nil when not scrubbing.
    private var scrubPosition: TimeInterval?
    private var lastScrubTickTime: CFTimeInterval = 0
    private var scrubSeekTimer: Timer?

    // Rating
    private let ratingStack = UIStackView()
    private var ratingMarks: [UILabel] = []

    // Lyrics
    private let lyricsContainer = UIView()
    private let lyricsArt = UIImageView()
    private let lyricsTextView = UITextView()

    /// Returns the song at the given index, or nil if out of bounds
    private func songAtIndex(_ index: Int) -> MPMediaItem? {
        guard index >= 0 && index < songs.count else { return nil }
        return songs[index]
    }

    /// Returns the best available item for display: either from the songs array
    /// at the current playing index, or the nowPlayingItem directly from the player
    private var currentDisplayItem: MPMediaItem? {
        let index = AppDelegate.music.musicPlayer.indexOfNowPlayingItem
        return songAtIndex(index) ?? AppDelegate.music.musicPlayer.nowPlayingItem
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    override func viewWillAppear(_ animated: Bool) {
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Now Playing"
        if !skipQueueSetup {
            AppDelegate.music.musicPlayer.setQueue(with: MPMediaItemCollection(items: songs))
        }


        if startingIndex != -1 {
            AppDelegate.music.musicPlayer.nowPlayingItem = songs[startingIndex]
            lastIndex = startingIndex
            startingIndex = -1
        }
        if !comingFromHome {
            AppDelegate.music.musicPlayer.play()
            AppDelegate.baseVC.setPlaybackIcon(state: .playing)
        }
        timer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(self.fireTimer), userInfo: nil, repeats: true)

        if isShuffled {
            AppDelegate.baseVC.shuffleIcon.isHidden = false
        } else if !comingFromHome {
            AppDelegate.baseVC.shuffleIcon.isHidden = true
        }

        setupUI()
        updateUI()
    }

    override func viewWillDisappear(_ animated: Bool) {
        timer.invalidate()
        volumeTimer?.invalidate()
        volumeTimer = nil
        // Apply any pending scrub, then reset to the default mode for next time.
        commitScrub()
        setMode(.volume, animated: false)
    }

    func setupUI() {
        if !hasSetupUI {
            self.view.backgroundColor = .white
            trackNumber.translatesAutoresizingMaskIntoConstraints = false
            trackNumber.font = UIFont(name: "HelveticaNeue-Medium", size: 18)
            trackNumber.textColor = .black
            let displayItem = currentDisplayItem
            trackNumber.text = "\(AppDelegate.music.musicPlayer.indexOfNowPlayingItem + 1) of \(songs.count)"

            albumArt = UIImageView(image: displayItem?.artwork?.image(at: CGSize(width: 300, height: 300)))
            albumArt.contentMode = .scaleAspectFill
            albumArt.translatesAutoresizingMaskIntoConstraints = false
            albumArt.clipsToBounds = true

            progressBar.translatesAutoresizingMaskIntoConstraints = false


            timeElapsed.translatesAutoresizingMaskIntoConstraints = false
            timeElapsed.font = UIFont(name: "HelveticaNeue-Medium", size: 18)
            timeElapsed.text = "0:00"

            timeRemaining.translatesAutoresizingMaskIntoConstraints = false
            timeRemaining.font = UIFont(name: "HelveticaNeue-Medium", size: 18)
            timeRemaining.text = "0:00"
            timeRemaining.textAlignment = .right

            let horizontalStack = UIStackView(arrangedSubviews: [timeElapsed, timeRemaining])
            horizontalStack.translatesAutoresizingMaskIntoConstraints = false
            horizontalStack.axis = .horizontal
            horizontalStack.alignment = .leading
            horizontalStack.distribution = .fill

            let stackPadding: CGFloat = 20
            let stackView = UIStackView(arrangedSubviews: [trackNumber, albumArt, progressBar, horizontalStack])
            stackView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(stackView)
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: stackPadding).isActive = true
            stackView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: stackPadding).isActive = true
            stackView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -stackPadding).isActive = true
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -stackPadding).isActive = true
            stackView.axis = .vertical
            stackView.alignment = .leading
            stackView.distribution = .equalSpacing

            albumArt.heightAnchor.constraint(equalTo: self.view.heightAnchor, multiplier: 0.45).isActive = true
            albumArt.widthAnchor.constraint(equalTo: self.view.heightAnchor, multiplier: 0.45).isActive = true


            progressBar.widthAnchor.constraint(equalTo: stackView.widthAnchor, multiplier: 1).isActive = true
            progressBar.heightAnchor.constraint(equalToConstant: 30).isActive = true
            progressBar.progressImage = #imageLiteral(resourceName: "progress").resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1), resizingMode: .tile)
            progressBar.trackImage = #imageLiteral(resourceName: "track").resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1), resizingMode: .tile)
            progressBar.setProgress(0, animated: true)
            horizontalStack.widthAnchor.constraint(equalTo: progressBar.widthAnchor, multiplier: 1).isActive = true
            progressBar.layer.shadowColor = UIColor.black.cgColor
            progressBar.layer.shadowOpacity = 0.25
            progressBar.layer.shadowOffset = CGSize(width: 0, height: 2)


            songName.translatesAutoresizingMaskIntoConstraints = false
            songName.font = UIFont(name: "HelveticaNeue-Medium", size: 18)
            songName.text = displayItem?.title ?? ""

            artistName.translatesAutoresizingMaskIntoConstraints = false
            artistName.font = UIFont(name: "HelveticaNeue-Medium", size: 18)
            artistName.text = displayItem?.artist ?? ""

            albumName.translatesAutoresizingMaskIntoConstraints = false
            albumName.font = UIFont(name: "HelveticaNeue-Medium", size: 18)
            albumName.text = displayItem?.albumTitle ?? ""

            let metaStack = UIStackView(arrangedSubviews: [songName, artistName, albumName])
            metaStack.axis = .vertical
            metaStack.alignment = .leading
            metaStack.distribution = .equalCentering
            metaStack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(metaStack)
            metaStack.leftAnchor.constraint(equalTo: albumArt.rightAnchor, constant: stackPadding).isActive = true
            metaStack.topAnchor.constraint(equalTo: albumArt.topAnchor, constant: 15).isActive = true
            metaStack.bottomAnchor.constraint(equalTo: albumArt.bottomAnchor, constant: -15).isActive = true
            metaStack.rightAnchor.constraint(equalTo: progressBar.rightAnchor).isActive = true
            hasSetupUI = true

            volumeBar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(volumeBar)
            volumeBar.topAnchor.constraint(equalTo: progressBar.topAnchor).isActive = true
            volumeBar.leftAnchor.constraint(equalTo: progressBar.leftAnchor).isActive = true
            volumeBar.rightAnchor.constraint(equalTo: progressBar.rightAnchor).isActive = true
            volumeBar.bottomAnchor.constraint(equalTo: progressBar.bottomAnchor).isActive = true
            volumeBar.progressImage = #imageLiteral(resourceName: "progress").resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1), resizingMode: .tile)
            volumeBar.trackImage = #imageLiteral(resourceName: "track").resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 1, bottom: 0, right: 1), resizingMode: .tile)
            volumeBar.setProgress(Float(getVolumeLevelAsPercentage()), animated: false)
            volumeBar.layer.shadowColor = UIColor.black.cgColor
            volumeBar.layer.shadowOpacity = 0.25
            volumeBar.layer.shadowOffset = CGSize(width: 0, height: 2)
            volumeBar.alpha = 0

            lowVolume.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(lowVolume)
            lowVolume.leftAnchor.constraint(equalTo: timeElapsed.leftAnchor).isActive = true
            lowVolume.centerYAnchor.constraint(equalTo: timeElapsed.centerYAnchor).isActive = true
            lowVolume.widthAnchor.constraint(equalToConstant: 25).isActive = true
            lowVolume.heightAnchor.constraint(equalToConstant: 25).isActive = true
            lowVolume.alpha = 0

            highVolume.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(highVolume)
            highVolume.rightAnchor.constraint(equalTo: timeRemaining.rightAnchor).isActive = true
            highVolume.centerYAnchor.constraint(equalTo: timeRemaining.centerYAnchor).isActive = true
            highVolume.widthAnchor.constraint(equalToConstant: 25).isActive = true
            highVolume.heightAnchor.constraint(equalToConstant: 25).isActive = true
            highVolume.alpha = 0

            setupModeViews()
        }

    }

    /// Builds the extra views used by the Scrubber, Rating and Lyrics modes. All start hidden.
    private func setupModeViews() {
        // Scrubber diamond rides on the progress bar.
        scrubDiamond.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrubDiamond)
        scrubDiamond.widthAnchor.constraint(equalToConstant: 16).isActive = true
        scrubDiamond.heightAnchor.constraint(equalToConstant: 16).isActive = true
        scrubDiamond.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor).isActive = true
        let cx = scrubDiamond.centerXAnchor.constraint(equalTo: progressBar.leftAnchor)
        cx.isActive = true
        diamondCenterX = cx
        scrubDiamond.alpha = 0

        // Rating: five marks (★ for a set star, • for an empty one) where the progress bar sits.
        ratingStack.translatesAutoresizingMaskIntoConstraints = false
        ratingStack.axis = .horizontal
        ratingStack.alignment = .center
        ratingStack.distribution = .equalSpacing
        ratingStack.spacing = 10
        for _ in 0..<5 {
            let mark = UILabel()
            mark.font = UIFont(name: "Helvetica-Bold", size: 24)
            mark.textAlignment = .center
            mark.textColor = .black
            mark.text = "•"
            mark.layer.shadowColor = UIColor.black.cgColor
            mark.layer.shadowOpacity = 0.2
            mark.layer.shadowRadius = 1
            mark.layer.shadowOffset = CGSize(width: 0, height: 1)
            mark.widthAnchor.constraint(equalToConstant: 24).isActive = true
            ratingMarks.append(mark)
            ratingStack.addArrangedSubview(mark)
        }
        view.addSubview(ratingStack)
        ratingStack.centerXAnchor.constraint(equalTo: progressBar.centerXAnchor).isActive = true
        ratingStack.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor).isActive = true
        ratingStack.alpha = 0

        // Lyrics: full-screen overlay on dimmed album art.
        lyricsContainer.translatesAutoresizingMaskIntoConstraints = false
        lyricsContainer.backgroundColor = .black
        lyricsContainer.clipsToBounds = true
        view.addSubview(lyricsContainer)
        lyricsContainer.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        lyricsContainer.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        lyricsContainer.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        lyricsContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        lyricsArt.translatesAutoresizingMaskIntoConstraints = false
        lyricsArt.contentMode = .scaleAspectFill
        lyricsArt.clipsToBounds = true
        lyricsArt.alpha = 0.3
        lyricsContainer.addSubview(lyricsArt)
        lyricsArt.topAnchor.constraint(equalTo: lyricsContainer.topAnchor).isActive = true
        lyricsArt.leftAnchor.constraint(equalTo: lyricsContainer.leftAnchor).isActive = true
        lyricsArt.rightAnchor.constraint(equalTo: lyricsContainer.rightAnchor).isActive = true
        lyricsArt.bottomAnchor.constraint(equalTo: lyricsContainer.bottomAnchor).isActive = true

        lyricsTextView.translatesAutoresizingMaskIntoConstraints = false
        lyricsTextView.backgroundColor = .clear
        lyricsTextView.isEditable = false
        lyricsTextView.isSelectable = false
        lyricsTextView.isScrollEnabled = true
        lyricsTextView.showsVerticalScrollIndicator = true
        lyricsTextView.indicatorStyle = .white
        lyricsTextView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        lyricsTextView.layer.shadowColor = UIColor.black.cgColor
        lyricsTextView.layer.shadowOpacity = 0.8
        lyricsTextView.layer.shadowRadius = 1
        lyricsTextView.layer.shadowOffset = CGSize(width: 0, height: 1)
        lyricsContainer.addSubview(lyricsTextView)
        lyricsTextView.topAnchor.constraint(equalTo: lyricsContainer.topAnchor).isActive = true
        lyricsTextView.leftAnchor.constraint(equalTo: lyricsContainer.leftAnchor).isActive = true
        lyricsTextView.rightAnchor.constraint(equalTo: lyricsContainer.rightAnchor).isActive = true
        lyricsTextView.bottomAnchor.constraint(equalTo: lyricsContainer.bottomAnchor).isActive = true
        lyricsContainer.alpha = 0
    }

    func updateUI() {
        let displayItem = currentDisplayItem
        trackNumber.text = "\(AppDelegate.music.musicPlayer.indexOfNowPlayingItem + 1) of \(songs.count)"
        albumArt.image = displayItem?.artwork?.image(at: CGSize(width: 300, height: 300))
        songName.text = displayItem?.title ?? ""
        artistName.text = displayItem?.artist ?? ""
        albumName.text = displayItem?.albumTitle ?? ""
        refreshModeForCurrentTrack()
    }

    @objc func fireTimer() {
        guard let nowPlaying = AppDelegate.music.musicPlayer.nowPlayingItem else { return }

        let duration = nowPlaying.playbackDuration
        guard duration > 0 else { return }

        // While scrubbing, the display follows the pending scrub position rather than the player.
        let isScrubbing = scrubPosition != nil
        let current = scrubPosition ?? AppDelegate.music.musicPlayer.currentPlaybackTime
        progressBar.setProgress(Float(current / duration), animated: !isScrubbing)
        updateDiamondPosition()
        let (_,m1,s1) = secondsToHoursMinutesSeconds(seconds: Int(current))
        let (_,m2,s2) = secondsToHoursMinutesSeconds(seconds: Int(duration - current))
        let elapsedSeconds: String = (s1 < 10) ? "0\(s1)" : String(s1)
        let remainingSeconds: String = (s2 < 10) ? "0\(s2)" : String(s2)
        timeElapsed.text = "\(m1):\(elapsedSeconds)"
        timeRemaining.text = "\(m2):\(remainingSeconds)"
        if lastTrackIndex == nil {
            lastTrackIndex = AppDelegate.music.musicPlayer.indexOfNowPlayingItem
        }
        if AppDelegate.music.musicPlayer.indexOfNowPlayingItem != lastTrackIndex {
            updateUI()
            lastTrackIndex = AppDelegate.music.musicPlayer.indexOfNowPlayingItem
        }
    }


    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        switch mode {
        case .volume:
            adjustVolume(rotationDirection: rotationDirection)
        case .scrubber:
            scrub(rotationDirection: rotationDirection)
        case .rating:
            adjustRating(rotationDirection: rotationDirection)
        case .lyrics:
            scrollLyrics(rotationDirection: rotationDirection)
        }
    }

    /// Default (Volume mode) wheel behaviour.
    private func adjustVolume(rotationDirection: RotationDirection) {
        if volumeTimer != nil {
            volumeTimer?.invalidate()
        }
        UIView.animate(withDuration: 0.2) {
            self.progressBar.alpha = 0
            self.timeElapsed.alpha = 0
            self.timeRemaining.alpha = 0
            self.volumeBar.alpha = 1
            self.lowVolume.alpha = 1
            self.highVolume.alpha = 1
        }
        let limit = SettingsStore.shared.volumeLimit
        if (rotationDirection == .CLOCKWISE) {
            let newVolume = min(volumeBar.progress + 0.1, limit)
            volumeBar.setProgress(newVolume, animated: true)
        } else {
            volumeBar.setProgress(volumeBar.progress - 0.1, animated: true)
        }

        AppDelegate.music.setVolume(volumeBar.progress)

        volumeTimer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(self.hideVolume), userInfo: nil, repeats: false)

    }

    @objc func hideVolume() {
        volumeTimer = nil
        applyModeVisibility(animated: true)
    }

    // MARK: - Mode switching

    /// Shows/hides the bottom-area views for the current mode.
    private func applyModeVisibility(animated: Bool) {
        let changes = {
            let showsBar = self.mode == .volume || self.mode == .scrubber || self.mode == .lyrics
            self.progressBar.alpha = showsBar ? 1 : 0
            self.timeElapsed.alpha = showsBar ? 1 : 0
            self.timeRemaining.alpha = showsBar ? 1 : 0
            self.volumeBar.alpha = 0
            self.lowVolume.alpha = 0
            self.highVolume.alpha = 0
            self.scrubDiamond.alpha = self.mode == .scrubber ? 1 : 0
            self.ratingStack.alpha = self.mode == .rating ? 1 : 0
            self.lyricsContainer.alpha = self.mode == .lyrics ? 1 : 0
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            changes()
        }
    }

    private func setMode(_ newMode: NowPlayingMode, animated: Bool = true) {
        if mode == .scrubber && newMode != .scrubber {
            commitScrub()
        }
        volumeTimer?.invalidate()
        volumeTimer = nil
        modeIdleTimer?.invalidate()
        modeIdleTimer = nil
        mode = newMode
        guard hasSetupUI else { return }
        switch newMode {
        case .volume:
            break
        case .scrubber:
            lastScrubTickTime = 0
            updateDiamondPosition()
            restartModeIdleTimer()
        case .rating:
            updateRatingMarks()
            restartModeIdleTimer()
        case .lyrics:
            loadLyrics()
        }
        applyModeVisibility(animated: animated)
    }

    /// Center cycles Volume → Scrubber → Rating → Lyrics (only when the track has lyrics) → Volume.
    private func advanceMode() {
        switch mode {
        case .volume:
            setMode(currentDisplayItem == nil ? .volume : .scrubber)
        case .scrubber:
            setMode(.rating)
        case .rating:
            setMode(currentLyrics() != nil ? .lyrics : .volume)
        case .lyrics:
            setMode(.volume)
        }
    }

    /// Scrubber and Rating fall back to the default mode after `modeIdleTimeout` seconds without input.
    private func restartModeIdleTimer() {
        modeIdleTimer?.invalidate()
        modeIdleTimer = Timer.scheduledTimer(withTimeInterval: modeIdleTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.modeIdleTimer = nil
            self.setMode(.volume)
        }
    }

    /// Keeps the current mode valid when the track changes.
    private func refreshModeForCurrentTrack() {
        guard hasSetupUI else { return }
        switch mode {
        case .volume:
            break
        case .scrubber:
            // A pending scrub belongs to the previous track — drop it.
            scrubSeekTimer?.invalidate()
            scrubSeekTimer = nil
            scrubPosition = nil
        case .rating:
            updateRatingMarks()
        case .lyrics:
            if currentLyrics() != nil {
                loadLyrics()
            } else {
                setMode(.volume)
            }
        }
    }

    // MARK: - Scrubber

    private func scrub(rotationDirection: RotationDirection) {
        guard let item = AppDelegate.music.musicPlayer.nowPlayingItem, item.playbackDuration > 0 else { return }
        let duration = item.playbackDuration

        // ~2s per tick, accelerating when the wheel spins quickly.
        let now = CACurrentMediaTime()
        let interval = lastScrubTickTime > 0 ? now - lastScrubTickTime : 1
        lastScrubTickTime = now
        let acceleration = min(max(0.12 / max(interval, 0.001), 1), 8)
        let step = 2.0 * acceleration

        let base = scrubPosition ?? AppDelegate.music.musicPlayer.currentPlaybackTime
        let delta = rotationDirection == .CLOCKWISE ? step : -step
        scrubPosition = min(max(base + delta, 0), max(duration - 1, 0))
        fireTimer()

        // Seek once the wheel has been still for a moment.
        scrubSeekTimer?.invalidate()
        scrubSeekTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.commitScrub()
        }
        restartModeIdleTimer()
    }

    /// Applies any pending scrub position to the player.
    private func commitScrub() {
        scrubSeekTimer?.invalidate()
        scrubSeekTimer = nil
        guard let target = scrubPosition else { return }
        scrubPosition = nil
        AppDelegate.music.musicPlayer.currentPlaybackTime = target
    }

    private func updateDiamondPosition() {
        guard let cx = diamondCenterX else { return }
        cx.constant = CGFloat(progressBar.progress) * progressBar.bounds.width
    }

    // MARK: - Rating

    // MPMediaItem.rating is read-only in the public MediaPlayer API (there is no supported way to write a
    // rating back to the library), so ratings set here are stored locally in UserDefaults, keyed by the
    // item's persistentID. The library's own rating is shown until the user sets one locally.
    private static let localRatingsKey = "classic.playback.localRatings"

    private func rating(for item: MPMediaItem) -> Int {
        let ratings = UserDefaults.standard.dictionary(forKey: Self.localRatingsKey) as? [String: Int] ?? [:]
        if let local = ratings[String(item.persistentID)] {
            return min(max(local, 0), 5)
        }
        return min(max(item.rating, 0), 5)
    }

    private func setRating(_ value: Int, for item: MPMediaItem) {
        var ratings = UserDefaults.standard.dictionary(forKey: Self.localRatingsKey) as? [String: Int] ?? [:]
        ratings[String(item.persistentID)] = min(max(value, 0), 5)
        UserDefaults.standard.set(ratings, forKey: Self.localRatingsKey)
    }

    private func adjustRating(rotationDirection: RotationDirection) {
        restartModeIdleTimer()
        guard let item = currentDisplayItem else { return }
        let current = rating(for: item)
        let newValue = rotationDirection == .CLOCKWISE ? min(current + 1, 5) : max(current - 1, 0)
        if newValue != current {
            setRating(newValue, for: item)
        }
        updateRatingMarks()
    }

    private func updateRatingMarks() {
        let stars = currentDisplayItem.map { rating(for: $0) } ?? 0
        for (index, mark) in ratingMarks.enumerated() {
            let filled = index < stars
            mark.text = filled ? "★" : "•"
            mark.textColor = filled ? .black : UIColor(white: 0.45, alpha: 1)
        }
    }

    // MARK: - Lyrics

    private func currentLyrics() -> String? {
        guard let lyrics = currentDisplayItem?.lyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lyrics.isEmpty else { return nil }
        return lyrics
    }

    private func loadLyrics() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 3
        lyricsTextView.attributedText = NSAttributedString(string: currentLyrics() ?? "", attributes: [
            .font: UIFont(name: "Helvetica-Bold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph
        ])
        lyricsArt.image = currentDisplayItem?.artwork?.image(at: CGSize(width: 600, height: 600))
        lyricsTextView.setContentOffset(.zero, animated: false)
    }

    private func scrollLyrics(rotationDirection: RotationDirection) {
        let step: CGFloat = 24
        let maxOffset = max(lyricsTextView.contentSize.height + lyricsTextView.adjustedContentInset.bottom - lyricsTextView.bounds.height, 0)
        var y = lyricsTextView.contentOffset.y + (rotationDirection == .CLOCKWISE ? step : -step)
        y = min(max(y, 0), maxOffset)
        lyricsTextView.setContentOffset(CGPoint(x: 0, y: y), animated: true)
    }

    // MARK: - Buttons

    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if (pressure == .NORMAL) {
            AppDelegate.music.playPause()
        }
    }

    func nextSongPressed(pressure: ClickWheelTouchPressure) {
        if (pressure == .NORMAL) {
            AppDelegate.music.musicPlayer.skipToNextItem()
            updateUI()
            if AppDelegate.music.musicPlayer.indexOfNowPlayingItem == lastIndex {
                self.navigationController?.popViewController(animated: true)
            } else {
                lastIndex = AppDelegate.music.musicPlayer.indexOfNowPlayingItem
            }
        } else if (pressure == .FORCE) {
            AppDelegate.music.musicPlayer.beginSeekingForward()
            updateUI()
        } else if (pressure == .FORCE_ENDED) {
            AppDelegate.music.musicPlayer.endSeeking()
            updateUI()
        }
    }

    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        if (pressure == .NORMAL) {
            AppDelegate.music.musicPlayer.skipToPreviousItem()
            updateUI()
            lastIndex = AppDelegate.music.musicPlayer.indexOfNowPlayingItem
        } else if (pressure == .FORCE) {
            AppDelegate.music.musicPlayer.beginSeekingBackward()
            updateUI()
        } else if (pressure == .FORCE_ENDED) {
            AppDelegate.music.musicPlayer.endSeeking()
            updateUI()
        }
    }

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if (pressure == .NORMAL) {
            self.navigationController?.popViewController(animated: true)
        } else if (pressure == .FORCE) {
            self.navigationController?.popToRootViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        guard pressure == .NORMAL, hasSetupUI else { return }
        advanceMode()
    }

    func getVolumeLevelAsPercentage() -> Float {
        return AVAudioSession.sharedInstance().outputVolume
    }


}

/// The iPod scrubber handle: a small glossy diamond drawn with Core Graphics.
final class ScrubberDiamondView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 1.5
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let b = bounds.insetBy(dx: 1, dy: 1)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: b.midX, y: b.minY))
        path.addLine(to: CGPoint(x: b.maxX, y: b.midY))
        path.addLine(to: CGPoint(x: b.midX, y: b.maxY))
        path.addLine(to: CGPoint(x: b.minX, y: b.midY))
        path.close()

        ctx.saveGState()
        path.addClip()
        let colors = [UIColor(white: 0.97, alpha: 1).cgColor,
                      UIColor(white: 0.70, alpha: 1).cgColor,
                      UIColor(white: 0.45, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: b.midX, y: b.minY), end: CGPoint(x: b.midX, y: b.maxY), options: [])
        }
        ctx.restoreGState()

        UIColor(white: 0.2, alpha: 1).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
