//
//  RecentlyPlayedViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import MediaPlayer

class RecentlyPlayedViewController: UIViewController, ClickWheelProtocol {

    var recentAlbums: [(albumTitle: String, artistName: String)] = []
    let tableView = UITableView()
    var counter: Int = 0
    var hasSetupUI = false
    let emptyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Recently Played"
        loadRecentlyPlayed()
        tableView.reloadData()
        if !recentAlbums.isEmpty {
            tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
            emptyLabel.isHidden = true
        } else {
            emptyLabel.isHidden = false
        }
    }

    func loadRecentlyPlayed() {
        let allSongs = AppDelegate.music.getSongs().items ?? []

        // Filter to songs that have been played
        let playedSongs = allSongs.filter { $0.lastPlayedDate != nil }

        // Sort by lastPlayedDate descending (most recent first)
        let sorted = playedSongs.sorted {
            ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast)
        }

        // Group by album title, keeping the most recent play date per album
        var seen = Set<String>()
        var result: [(albumTitle: String, artistName: String)] = []
        for song in sorted {
            guard let album = song.albumTitle, !album.isEmpty else { continue }
            if !seen.contains(album) {
                seen.insert(album)
                result.append((
                    albumTitle: album,
                    artistName: song.albumArtist ?? song.artist ?? ""
                ))
            }
            if result.count >= 25 { break }
        }
        recentAlbums = result
    }

    func setupUI() {
        if !hasSetupUI {
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

            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            emptyLabel.font = UIFont(name: "Helvetica-Bold", size: 15)
            emptyLabel.textColor = .darkGray
            emptyLabel.textAlignment = .center
            emptyLabel.text = "No Recently Played"
            emptyLabel.isHidden = true
            view.addSubview(emptyLabel)
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            emptyLabel.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20).isActive = true
            emptyLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20).isActive = true

            hasSetupUI = true
        }
    }

    // MARK: - ClickWheelProtocol

    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if rotationDirection == .CLOCKWISE {
            if counter + 1 <= recentAlbums.count - 1 {
                counter += 1
                let ip = IndexPath(row: counter, section: 0)
                tableView.selectRow(at: ip, animated: false, scrollPosition: .bottom)
            }
        } else {
            if counter > 0 {
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

    func nextSongPressed(pressure: ClickWheelTouchPressure) {}

    func previousSongPressed(pressure: ClickWheelTouchPressure) {}

    func menuPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            self.navigationController?.popViewController(animated: true)
        } else if pressure == .FORCE {
            self.navigationController?.popToRootViewController(animated: true)
        }
    }

    func centerPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            guard !recentAlbums.isEmpty else { return }
            let album = recentAlbums[counter]
            let songs = AppDelegate.music.getSongsInAlbum(forAlbum: album.albumTitle)
            let vc = SongsViewController()
            vc.menuItems = songs
            vc.albumName = album.albumTitle
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }
}

extension RecentlyPlayedViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return recentAlbums.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = recentAlbums[indexPath.row].albumTitle
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }
}
