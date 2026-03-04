//
//  MadeForYouSongsViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import Foundation
import UIKit
import MediaPlayer
import MusicKit

@available(iOS 15.0, *)
class MadeForYouSongsViewController: UIViewController, ClickWheelProtocol {
    var playlist: Playlist!
    var tracks: [Track] = []
    let tableView: UITableView = UITableView()
    
    var counter: Int = 0
    var hasSetupUI = false
    var isLoading = true
    var hasLoadedOnce = false
    
    let emptyLabel: UILabel = UILabel()
    let loadingIndicator: UIActivityIndicatorView = UIActivityIndicatorView(style: .medium)
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = playlist.name
        if !hasLoadedOnce {
            loadTracks()
            hasLoadedOnce = true
        } else {
            if !tracks.isEmpty {
                tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
            }
        }
    }
    
    func loadTracks() {
        isLoading = true
        loadingIndicator.startAnimating()
        loadingIndicator.isHidden = false
        emptyLabel.isHidden = true
        
        Task {
            do {
                let fetched = try await MusicKitService.shared.getTracks(for: playlist)
                await MainActor.run {
                    self.tracks = fetched
                    self.isLoading = false
                    self.loadingIndicator.stopAnimating()
                    self.loadingIndicator.isHidden = true
                    self.tableView.reloadData()
                    if !fetched.isEmpty {
                        self.counter = 0
                        self.tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .none)
                    } else {
                        self.showEmptyState("No songs available")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.loadingIndicator.stopAnimating()
                    self.loadingIndicator.isHidden = true
                    self.showEmptyState("Could not load songs")
                }
            }
        }
    }
    
    func showEmptyState(_ message: String) {
        emptyLabel.text = message
        emptyLabel.isHidden = false
    }
    
    func setupUI() {
        if !hasSetupUI {
            self.view.backgroundColor = .white
            
            tableView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(tableView)
            tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            tableView.delegate = self
            tableView.dataSource = self
            tableView.separatorStyle = .none
            
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            emptyLabel.font = UIFont(name: "Helvetica-Bold", size: 15)
            emptyLabel.textColor = .darkGray
            emptyLabel.textAlignment = .center
            emptyLabel.isHidden = true
            view.addSubview(emptyLabel)
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            emptyLabel.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20).isActive = true
            emptyLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20).isActive = true
            
            loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(loadingIndicator)
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            
            hasSetupUI = true
        }
    }
    
    // MARK: - ClickWheelProtocol
    
    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if (rotationDirection == .CLOCKWISE) {
            if (counter + 1 <= self.tracks.count - 1) {
                counter += 1
                let ip = IndexPath(row: counter, section: 0)
                tableView.selectRow(at: ip, animated: false, scrollPosition: .bottom)
            }
        } else {
            if (counter > 0) {
                counter -= 1
                let ip = IndexPath(row: counter, section: 0)
                tableView.selectRow(at: ip, animated: false, scrollPosition: .bottom)
            }
        }
    }
    
    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        }
    }
    
    func nextSongPressed(pressure: ClickWheelTouchPressure) {
    }
    
    func previousSongPressed(pressure: ClickWheelTouchPressure) {
    }
    
    func menuPressed(pressure: ClickWheelTouchPressure) {
        if (pressure == .NORMAL) {
            self.navigationController?.popViewController(animated: true)
        } else if (pressure == .FORCE) {
            self.navigationController?.popToRootViewController(animated: true)
        }
    }
    
    func centerPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            guard !tracks.isEmpty else { return }
            
            // Start playback via MusicKit (sets queue + plays)
            MusicKitService.shared.playTracks(tracks, startingAt: counter)
            
            // Push PlaybackViewController immediately — use skipQueueSetup
            // so it doesn't overwrite the MusicKit queue, and comingFromHome
            // so it doesn't call play() again (MusicKitService already started playback)
            let vc = PlaybackViewController()
            // We need to provide a songs array for PlaybackVC's UI (track count, artwork, etc.)
            // Use getCurrentQueue() as a best-effort; if empty, create a minimal placeholder
            let queue = AppDelegate.music.getCurrentQueue()
            if !queue.isEmpty {
                vc.songs = queue
            } else {
                // Fallback: create a single-item array from the now-playing item
                // PlaybackVC needs at least something for its UI
                if let nowPlaying = AppDelegate.music.musicPlayer.nowPlayingItem {
                    vc.songs = [nowPlaying]
                } else {
                    // Last resort: get all songs (not ideal but prevents crash)
                    vc.songs = AppDelegate.music.getSongs().items ?? []
                }
            }
            vc.startingIndex = -1
            vc.comingFromHome = true
            vc.skipQueueSetup = true
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }
}

@available(iOS 15.0, *)
extension MadeForYouSongsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.tracks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        let track = tracks[indexPath.row]
        cell.label.text = track.title
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }
}
