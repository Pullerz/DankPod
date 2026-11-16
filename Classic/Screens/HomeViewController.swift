//
//  HomeViewController.swift
//  Classic
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class HomeViewController: UIViewController, ClickWheelProtocol {
    var menuItems: [String] = ["Music", "Photos", "Videos", "Extras", "Settings", "Shuffle Songs"]
    let tableView: UITableView = UITableView()
    var vcs: [UIViewController] = [MusicViewController(), PhotosMenuViewController(), VideosViewController(), ExtrasMenuViewController(), SettingsMenuViewController(), MusicViewController(), PlaybackViewController()]
    
    var counter: Int = 0
    var hasSetupUI = false
    private lazy var split = SplitMenuLayout(provider: self)
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "iPod"

        if !menuItems.contains("Now Playing") && (AppDelegate.music.musicPlayer.playbackState == .playing || AppDelegate.music.musicPlayer.playbackState == .paused) {
            menuItems.append("Now Playing")
        } else if menuItems.contains("Now Playing") && AppDelegate.music.musicPlayer.playbackState == .stopped {
            menuItems.removeAll(where: {$0 == "Now Playing"})
        }
        counter = min(counter, menuItems.count - 1)
        
        
        tableView.reloadData()
        
        tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .top)
        
        split.viewWillAppear(selectedRow: counter)

    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        split.viewDidDisappear()
    }

    func setupUI() {
        if !hasSetupUI {
            split.install(tableView: tableView, in: view)
            tableView.delegate = self
            tableView.dataSource = self
            tableView.separatorStyle = .none
            hasSetupUI = true
        }
    }
    
    
    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if (rotationDirection == .CLOCKWISE) {
            if (counter + 1 <= self.menuItems.count - 1) {
                counter += 1
                let ip = IndexPath(row: counter, section: 0)
                tableView.selectRow(at: ip, animated: false, scrollPosition: .top)
                split.selectionDidChange(to: counter)
            }
        } else {
            if (counter > 0) {
                counter -= 1
                let ip = IndexPath(row: counter, section: 0)
                tableView.selectRow(at: ip, animated: false, scrollPosition: .top)
                split.selectionDidChange(to: counter)
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
        
        
        if menuItems[counter] == "Now Playing" {
            let queue = AppDelegate.music.getCurrentQueue()
            guard !queue.isEmpty else {
                let alert = UIAlertController(
                    title: "Cannot Open Now Playing",
                    message: "This song was started outside of Classic. To use Now Playing, start a song from within the app.",
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
                return
            }
            let vc = vcs[counter] as! PlaybackViewController
            vc.songs = queue
            vc.startingIndex = AppDelegate.music.musicPlayer.indexOfNowPlayingItem
            vc.comingFromHome = true
            self.navigationController?.pushViewController(vc, animated: true)
        } else if menuItems[counter] == "Shuffle Songs" {
            let songs = AppDelegate.music.getSongs()
            let vc = PlaybackViewController()
            vc.isShuffled = true
            vc.songs = songs.items.shuffled()
            self.navigationController?.pushViewController(vc, animated: true)
        } else {
            let vc = vcs[counter]
            self.navigationController?.pushViewController(vc, animated: true)
        }
        
        
    }


}

extension HomeViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.menuItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = menuItems[indexPath.row]
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }


}


extension HomeViewController: SplitPreviewProviding {
    func splitPreviewKind(forRow row: Int) -> SplitPreviewKind? {
        guard menuItems.indices.contains(row) else { return nil }
        switch menuItems[row] {
        case "Music":         return .albumSlideshow
        case "Photos":        return .recentPhotos(albumID: nil)
        case "Videos":        return .videos
        case "Extras":        return .extras
        case "Settings":      return .about
        case "Shuffle Songs": return .shuffle
        case "Now Playing":   return .nowPlaying
        default:              return nil
        }
    }
}
