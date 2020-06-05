//
//  HomeViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import MediaPlayer

class SongsViewController: UIViewController, ClickWheelProtocol {
    var menuItems: [MPMediaItem] = []
    let tableView: UITableView = UITableView()
    
    var counter: Int = 0
    var hasSetupUI = false
    var albumName: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = albumName ?? "Songs"
        getSongs()
    }
    
    func getSongs() {
        if menuItems.count == 0 {
            let songs = AppDelegate.music.getSongs()
            menuItems = songs.items
            tableView.reloadData()
            tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
        } else {
            tableView.reloadData()
            tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
        }
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
    
    var playHeld = false
    
    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        } else if pressure == .FORCE {
            playHeld = true
        } else if pressure == .FORCE_ENDED {
            playHeld = false
        }
    }
    
    func nextSongPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            if playHeld && AppDelegate.music.queueMode {
                print("Add to head of queue")
                playHeld = false
                AppDelegate.music.pushToHeadOfQueue(song: menuItems[counter])
            }
        } else if pressure == .FORCE {
            
        } else if pressure == .FORCE_ENDED {
            
        }
    }
    
    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL && AppDelegate.music.queueMode {
            if playHeld {
                print("Add to tail of queue")
                playHeld = false
                AppDelegate.music.pushToTailOfQueue(song: menuItems[counter])
            }
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
        let vc = PlaybackViewController()
        vc.songs = menuItems
        vc.startingIndex = counter
        self.navigationController?.pushViewController(vc, animated: true)
    }


}

extension SongsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.menuItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.textLabel?.text = menuItems[indexPath.row].title
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }


}
