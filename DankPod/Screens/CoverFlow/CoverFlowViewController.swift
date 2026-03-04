//
//  CoverFlowViewController.swift
//  DankPod
//
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import MediaPlayer

class CoverFlowViewController: UIViewController, ClickWheelProtocol {
    
    var albums: [MPMediaItemCollection] = []
    var collectionView: UICollectionView!
    var coverFlowLayout: CoverFlowLayout!
    var currentIndex: Int = 0
    
    let albumTitleLabel = UILabel()
    let artistNameLabel = UILabel()
    let letterOverlay = UILabel()
    let emptyStateLabel = UILabel()
    var letterHideTimer: Timer?
    
    var hasSetupUI = false
    
    // Continuous scrolling state
    var prefersContinuousWheelInput: Bool { true }
    private var scrollPosition: Double = 0
    private var trackedVelocity: Double = 0
    private var isFingerOnWheel = false
    private var needsVisualUpdate = false
    private var lastAppliedOffsetX: CGFloat = -.greatestFiniteMagnitude
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    private let albumsPerRevolution: Double = 10.0
    private let friction: Double = 8.0
    private let maxTrackedVelocity: Double = 30.0
    private let maxInstantVelocity: Double = 50.0
    private let haptics = UISelectionFeedbackGenerator()
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Cover Flow"
        haptics.prepare()
        loadAlbums()
    }
    
    func loadAlbums() {
        albums = AppDelegate.music.getAllAlbums()
        // Sort alphabetically by album title
        albums.sort { a, b in
            let titleA = a.representativeItem?.albumTitle ?? ""
            let titleB = b.representativeItem?.albumTitle ?? ""
            return titleA.localizedCaseInsensitiveCompare(titleB) == .orderedAscending
        }
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        if albums.count > 0 {
            emptyStateLabel.isHidden = true
            scrollPosition = Double(currentIndex)
            scrollToCurrentIndex(animated: false)
            updateAlbumInfo()
            prewarmImageCache()
        } else {
            emptyStateLabel.isHidden = false
            albumTitleLabel.text = ""
            artistNameLabel.text = ""
        }
    }
    
    private static let prewarmQueue = DispatchQueue(label: "com.dankpod.coverflow.prewarm", qos: .utility)
    
    private func prewarmImageCache() {
        let albumsCopy = albums
        Self.prewarmQueue.async {
            for album in albumsCopy {
                autoreleasepool {
                    let key = CoverFlowCell.cacheKey(for: album)
                    if CoverFlowCell.imageCache.object(forKey: key) == nil {
                        CoverFlowCell.generateAndCache(for: album)
                    }
                }
            }
        }
    }
    
    func scrollToCurrentIndex(animated: Bool, duration: TimeInterval = 0.15) {
        let offsetX = coverFlowLayout.contentOffsetForItem(at: currentIndex)
        let targetOffset = CGPoint(x: offsetX, y: 0)
        if animated {
            UIView.animate(withDuration: duration,
                           delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                           animations: {
                self.collectionView.setContentOffset(targetOffset, animated: false)
                self.collectionView.layoutIfNeeded()
                           })
        } else {
            collectionView.setContentOffset(targetOffset, animated: false)
        }
    }
    
    func setupUI() {
        if !hasSetupUI {
            view.backgroundColor = .white
            
            // Cover Flow layout + collection view
            coverFlowLayout = CoverFlowLayout()
            collectionView = UICollectionView(frame: .zero, collectionViewLayout: coverFlowLayout)
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            collectionView.backgroundColor = .white
            collectionView.showsHorizontalScrollIndicator = false
            collectionView.clipsToBounds = false
            collectionView.isScrollEnabled = false
            collectionView.delegate = self
            collectionView.dataSource = self
            collectionView.register(CoverFlowCell.self, forCellWithReuseIdentifier: "CoverFlowCell")
            view.addSubview(collectionView)
            
            // Album title label
            albumTitleLabel.translatesAutoresizingMaskIntoConstraints = false
            albumTitleLabel.textColor = .black
            albumTitleLabel.font = UIFont(name: "Helvetica-Bold", size: 14)
            albumTitleLabel.textAlignment = .center
            view.addSubview(albumTitleLabel)
            
            // Artist name label
            artistNameLabel.translatesAutoresizingMaskIntoConstraints = false
            artistNameLabel.textColor = .black
            artistNameLabel.font = UIFont(name: "Helvetica-Bold", size: 14)
            artistNameLabel.textAlignment = .center
            view.addSubview(artistNameLabel)
            
            // Letter overlay (shown during fast scrolling)
            letterOverlay.translatesAutoresizingMaskIntoConstraints = false
            letterOverlay.textColor = UIColor.black.withAlphaComponent(0.6)
            letterOverlay.font = UIFont(name: "Helvetica-Bold", size: 80)
            letterOverlay.textAlignment = .center
            letterOverlay.alpha = 0
            view.addSubview(letterOverlay)
            
            // Empty state label
            emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
            emptyStateLabel.text = "No Albums"
            emptyStateLabel.textColor = UIColor.lightGray
            emptyStateLabel.font = UIFont(name: "Helvetica-Bold", size: 17)
            emptyStateLabel.textAlignment = .center
            emptyStateLabel.isHidden = true
            view.addSubview(emptyStateLabel)
            
            NSLayoutConstraint.activate([
                collectionView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
                collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
                collectionView.rightAnchor.constraint(equalTo: view.rightAnchor),
                collectionView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.75),
                
                albumTitleLabel.topAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: 5),
                albumTitleLabel.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20),
                albumTitleLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20),
                
                artistNameLabel.topAnchor.constraint(equalTo: albumTitleLabel.bottomAnchor, constant: 2),
                artistNameLabel.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20),
                artistNameLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20),
                
                letterOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                letterOverlay.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
                
                emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                emptyStateLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor)
            ])
            
            hasSetupUI = true
        }
    }
    
    func updateAlbumInfo() {
        guard currentIndex >= 0 && currentIndex < albums.count else { return }
        let album = albums[currentIndex]
        albumTitleLabel.text = album.representativeItem?.albumTitle ?? ""
        artistNameLabel.text = album.representativeItem?.albumArtist ?? album.representativeItem?.artist ?? ""
    }
    
    func showLetterOverlay() {
        guard currentIndex >= 0 && currentIndex < albums.count else { return }
        let albumTitle = albums[currentIndex].representativeItem?.albumTitle ?? ""
        let firstLetter = String(albumTitle.prefix(1)).uppercased()
        if firstLetter.isEmpty { return }
        
        letterOverlay.text = firstLetter
        letterOverlay.alpha = 1.0
        
        letterHideTimer?.invalidate()
        letterHideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) {
                self?.letterOverlay.alpha = 0
            }
        }
    }
    
    // MARK: - Continuous Scrolling (physics-based)
    
    func clickWheelDidRotateContinuously(event: ClickWheelRotationEvent) {
        guard albums.count > 0 else { return }
        
        if event.state == .ended {
            isFingerOnWheel = false
            return
        }
        
        // .changed — active finger movement
        isFingerOnWheel = true
        
        // Convert rotation delta to album units
        let deltaAlbums = Double(event.deltaRadians) / (2.0 * .pi) * albumsPerRevolution
        
        // Move position directly with finger
        scrollPosition += deltaAlbums
        scrollPosition = max(0, min(Double(albums.count - 1), scrollPosition))
        
        // Blend instantaneous velocity into tracked velocity (exponential moving average)
        // Clamp instant velocity to reject spikes from gesture event bunching
        let rawInstant = Double(event.angularVelocity) / (2.0 * .pi) * albumsPerRevolution
        let instantVelocity = max(-maxInstantVelocity, min(maxInstantVelocity, rawInstant))
        trackedVelocity = trackedVelocity * 0.6 + instantVelocity * 0.4
        trackedVelocity = max(-maxTrackedVelocity, min(maxTrackedVelocity, trackedVelocity))
        
        // Mark for next display link frame — don't update visuals directly
        needsVisualUpdate = true
        ensureDisplayLinkRunning()
    }
    
    private func ensureDisplayLinkRunning() {
        guard displayLink == nil else { return }
        lastFrameTime = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(physicsFrame))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func physicsFrame() {
        let now = CACurrentMediaTime()
        let dt = now - lastFrameTime
        lastFrameTime = now
        guard dt > 0 && dt < 0.5 else { return }
        
        if isFingerOnWheel {
            trackedVelocity *= exp(-friction * dt)
        } else {
            trackedVelocity *= exp(-friction * dt)
            scrollPosition += trackedVelocity * dt
            scrollPosition = max(0, min(Double(albums.count - 1), scrollPosition))
            
            if (scrollPosition <= 0 && trackedVelocity < 0) ||
               (scrollPosition >= Double(albums.count - 1) && trackedVelocity > 0) {
                trackedVelocity = 0
            }
            
            needsVisualUpdate = true
            
            if abs(trackedVelocity) < 0.3 {
                stopPhysics()
                snapToNearestAlbum()
                return
            }
        }
        
        if needsVisualUpdate {
            applyScrollPosition()
            needsVisualUpdate = false
        }
    }
    
    private func applyScrollPosition() {
        let newIndex = Int(round(scrollPosition))
        if newIndex != currentIndex {
            currentIndex = newIndex
            updateAlbumInfo()
            if SettingsStore.shared.clickerEnabled {
                haptics.selectionChanged()
            }
            if abs(trackedVelocity) > 3.0 {
                showLetterOverlay()
            }
        }
        
        let offsetX = coverFlowLayout.contentOffsetForFractionalPosition(scrollPosition)
        guard abs(offsetX - lastAppliedOffsetX) >= 0.5 else { return }
        lastAppliedOffsetX = offsetX
        collectionView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: false)
    }
    
    private func stopPhysics() {
        displayLink?.invalidate()
        displayLink = nil
        trackedVelocity = 0
        isFingerOnWheel = false
    }
    
    private func snapToNearestAlbum() {
        guard albums.count > 0 else { return }
        currentIndex = Int(round(scrollPosition))
        currentIndex = max(0, min(albums.count - 1, currentIndex))
        scrollPosition = Double(currentIndex)
        scrollToCurrentIndex(animated: true, duration: 0.15)
        updateAlbumInfo()
    }
    
    // MARK: - ClickWheelProtocol (discrete — unused in continuous mode)
    
    func clickWheelDidRotate(rotationDirection: RotationDirection) {}
    
    func centerPressed(pressure: ClickWheelTouchPressure) {
        stopPhysics()
        snapToNearestAlbum()
        if pressure == .NORMAL {
            guard currentIndex >= 0 && currentIndex < albums.count else { return }
            let album = albums[currentIndex]
            if let albumTitle = album.representativeItem?.albumTitle {
                let songs = AppDelegate.music.getSongsInAlbum(forAlbum: albumTitle)
                let vc = CoverFlowAlbumViewController()
                vc.albumTitle = albumTitle
                vc.songs = songs
                self.navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
    
    func menuPressed(pressure: ClickWheelTouchPressure) {
        stopPhysics()
        if pressure == .NORMAL {
            self.navigationController?.popViewController(animated: true)
        } else if pressure == .FORCE {
            self.navigationController?.popToRootViewController(animated: true)
        }
    }
    
    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        }
    }
    
    func nextSongPressed(pressure: ClickWheelTouchPressure) {
        stopPhysics()
        if pressure == .NORMAL {
            if currentIndex + 1 <= albums.count - 1 {
                currentIndex += 1
                scrollPosition = Double(currentIndex)
                scrollToCurrentIndex(animated: true)
                updateAlbumInfo()
            }
        }
    }
    
    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        stopPhysics()
        if pressure == .NORMAL {
            if currentIndex > 0 {
                currentIndex -= 1
                scrollPosition = Double(currentIndex)
                scrollToCurrentIndex(animated: true)
                updateAlbumInfo()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPhysics()
    }
}

// MARK: - UICollectionViewDataSource & Delegate

extension CoverFlowViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return albums.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "CoverFlowCell", for: indexPath) as! CoverFlowCell
        cell.configure(with: albums[indexPath.item])
        return cell
    }
    

}
