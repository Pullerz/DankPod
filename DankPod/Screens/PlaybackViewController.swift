//
//  PlaybackViewController.swift
//  DankPod
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
        }
        
    }

    func updateUI() {
        let displayItem = currentDisplayItem
        trackNumber.text = "\(AppDelegate.music.musicPlayer.indexOfNowPlayingItem + 1) of \(songs.count)"
        albumArt.image = displayItem?.artwork?.image(at: CGSize(width: 300, height: 300))
        songName.text = displayItem?.title ?? ""
        artistName.text = displayItem?.artist ?? ""
        albumName.text = displayItem?.albumTitle ?? ""
    }
    
    @objc func fireTimer() {
        guard let nowPlaying = AppDelegate.music.musicPlayer.nowPlayingItem else { return }

        let duration = nowPlaying.playbackDuration
        guard duration > 0 else { return }

        progressBar.setProgress(Float(AppDelegate.music.musicPlayer.currentPlaybackTime / duration), animated: true)
        let (_,m1,s1) = secondsToHoursMinutesSeconds(seconds: Int(AppDelegate.music.musicPlayer.currentPlaybackTime))
        let (_,m2,s2) = secondsToHoursMinutesSeconds(seconds: Int(duration - AppDelegate.music.musicPlayer.currentPlaybackTime))
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
        UIView.animate(withDuration: 0.2) {
            self.progressBar.alpha = 1
            self.timeElapsed.alpha = 1
            self.timeRemaining.alpha = 1
            self.volumeBar.alpha = 0
            self.lowVolume.alpha = 0
            self.highVolume.alpha = 0
        }
    }
    
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
        
    }
    
    func getVolumeLevelAsPercentage() -> Float {
        return AVAudioSession.sharedInstance().outputVolume
    }
    

}
