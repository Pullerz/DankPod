//
//  CoverFlowAlbumViewController.swift
//  DankPod
//
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import MediaPlayer

class CoverFlowAlbumViewController: UIViewController, ClickWheelProtocol {
    
    var albumTitle: String = ""
    var songs: [MPMediaItem] = []
    let tableView = UITableView()
    var counter: Int = 0
    var hasSetupUI = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = albumTitle
        tableView.reloadData()
        if songs.count > 0 {
            tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .none)
        }
        counter = 0
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
    
    // MARK: - ClickWheelProtocol
    
    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if rotationDirection == .CLOCKWISE {
            if counter + 1 <= songs.count - 1 {
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
    
    func centerPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            guard counter >= 0 && counter < songs.count else { return }
            let vc = PlaybackViewController()
            vc.songs = songs
            vc.startingIndex = counter
            self.navigationController?.pushViewController(vc, animated: true)
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
    }
    
    func previousSongPressed(pressure: ClickWheelTouchPressure) {
    }
}

// MARK: - UITableViewDelegate & DataSource

extension CoverFlowAlbumViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return songs.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = songs[indexPath.row].title
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }
}
