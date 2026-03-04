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
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Cover Flow"
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
        if albums.count > 0 {
            emptyStateLabel.isHidden = true
            // Scroll to current index
            let indexPath = IndexPath(item: currentIndex, section: 0)
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
            updateAlbumInfo()
        } else {
            emptyStateLabel.isHidden = false
            albumTitleLabel.text = ""
            artistNameLabel.text = ""
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
            collectionView.decelerationRate = .fast
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
    
    // MARK: - ClickWheelProtocol
    
    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if rotationDirection == .CLOCKWISE {
            if currentIndex + 1 <= albums.count - 1 {
                currentIndex += 1
                let indexPath = IndexPath(item: currentIndex, section: 0)
                collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
                updateAlbumInfo()
                showLetterOverlay()
            }
        } else {
            if currentIndex > 0 {
                currentIndex -= 1
                let indexPath = IndexPath(item: currentIndex, section: 0)
                collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
                updateAlbumInfo()
                showLetterOverlay()
            }
        }
    }
    
    func centerPressed(pressure: ClickWheelTouchPressure) {
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
        if pressure == .NORMAL {
            if currentIndex + 1 <= albums.count - 1 {
                currentIndex += 1
                let indexPath = IndexPath(item: currentIndex, section: 0)
                collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
                updateAlbumInfo()
                showLetterOverlay()
            }
        }
    }
    
    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            if currentIndex > 0 {
                currentIndex -= 1
                let indexPath = IndexPath(item: currentIndex, section: 0)
                collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
                updateAlbumInfo()
                showLetterOverlay()
            }
        }
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
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentIndexFromScrollPosition()
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateCurrentIndexFromScrollPosition()
        }
    }
    
    private func updateCurrentIndexFromScrollPosition() {
        guard let collectionView = collectionView else { return }
        let centerX = collectionView.contentOffset.x + collectionView.bounds.width / 2.0
        let closestIndexPath = collectionView.indexPathForItem(at: CGPoint(x: centerX, y: collectionView.bounds.height / 2.0))
        if let indexPath = closestIndexPath {
            currentIndex = indexPath.item
            updateAlbumInfo()
        }
    }
}
