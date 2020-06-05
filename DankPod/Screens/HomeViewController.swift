//
//  HomeViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class HomeViewController: UIViewController, ClickWheelProtocol {
    var menuItems: [String] = ["Music", "Photos", "Videos", "Extras", "Settings", "Shuffle Songs"]
    let tableView: UITableView = UITableView()
    var vcs: [UIViewController] = [MusicViewController(), MusicViewController(), MusicViewController(), MusicViewController(), MusicViewController(), MusicViewController(), PlaybackViewController()]
    
    var counter: Int = 0
    var hasSetupUI = false
    
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
        
        
        tableView.reloadData()
        
        tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .top)

    }
    
    func setupUI() {
        if !hasSetupUI {
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
    }
    
    
    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if (rotationDirection == .CLOCKWISE) {
            if (counter + 1 <= self.menuItems.count - 1) {
                counter += 1
                let ip = IndexPath(row: counter, section: 0)
                tableView.selectRow(at: ip, animated: false, scrollPosition: .top)
            }
        } else {
            if (counter > 0) {
                counter -= 1
                let ip = IndexPath(row: counter, section: 0)
                tableView.selectRow(at: ip, animated: false, scrollPosition: .top)
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
            let vc = vcs[counter] as! PlaybackViewController
            vc.songs = AppDelegate.music.getCurrentQueue()
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
        cell.textLabel?.text = menuItems[indexPath.row]
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }


}
