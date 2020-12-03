//
//  ArtistsAlbumsViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import Foundation
import UIKit
import MediaPlayer

class AlbumsViewController: UIViewController, ClickWheelProtocol {
    var menuItems: [MPMediaItemCollection]! = []
    let tableView: UITableView = UITableView()
    var artistName: String?
    var genreName: String?
    
    var counter: Int = 0
    var hasSetupUI = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = artistName ?? genreName ?? "Albums"
        getAlbums()
    }
    
    func getAlbums() {
        if let artist = self.artistName {
            menuItems = AppDelegate.music.getAlbums(forArtist: artist)
            var tmp: [MPMediaItemCollection] = []
            for menuItem in menuItems {
                if let albumTitle = menuItem.representativeItem?.albumTitle {
                    if !tmp.contains(where: {$0.representativeItem?.albumTitle == albumTitle}) {
                        tmp.append(menuItem)
                    }
                }
            }
            menuItems = tmp
        } else {
            menuItems = AppDelegate.music.getAllAlbums()
        }
        
        tableView.reloadData()
        tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
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
            if let albumTitle = menuItems[counter].representativeItem?.albumTitle {
                let songs = AppDelegate.music.getSongsInAlbum(forAlbum: albumTitle)
                let vc = SongsViewController()
                vc.menuItems = songs
                vc.albumName = albumTitle
                self.navigationController?.pushViewController(vc, animated: true)
            }
        }
    }


}

extension AlbumsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.menuItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = menuItems[indexPath.row].representativeItem?.albumTitle
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }


}
