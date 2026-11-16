//
//  HomeViewController.swift
//  Classic
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class MusicViewController: UIViewController, ClickWheelProtocol {
    var menuItems: [String] = ["Cover Flow", "Recently Played", "Playlists", "Artists", "Albums", "Songs", "Genres", "Search"]
    let tableView: UITableView = UITableView()
    var vcs: [UIViewController] = [CoverFlowViewController(), RecentlyPlayedViewController(), PlaylistsViewController(), ArtistsViewController(), AlbumsViewController(), SongsViewController(), GenresViewController(), SearchViewController()]
    
    var counter: Int = 0
    var hasSetupUI = false
    private lazy var split = SplitMenuLayout(provider: self)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Conditionally add Made For You if iOS 16+ (requires MusicKit)
        if #available(iOS 16.0, *) {
            // Insert after "Recently Played" (index 2)
            menuItems.insert("Made For You", at: 2)
            vcs.insert(MadeForYouViewController(), at: 2)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Music"
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
                tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
                split.selectionDidChange(to: counter)
            }
        } else {
            if (counter > 0) {
                counter -= 1
                let ip = IndexPath(row: counter, section: 0)
                tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
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
        let vc = vcs[counter]
        self.navigationController?.pushViewController(vc, animated: true)
    }


}

extension MusicViewController: UITableViewDelegate, UITableViewDataSource {
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


extension MusicViewController: SplitPreviewProviding {
    func splitPreviewKind(forRow row: Int) -> SplitPreviewKind? {
        guard menuItems.indices.contains(row) else { return nil }
        // One shared slideshow for the whole menu (it keeps running as the highlight moves),
        // with Cover Flow previewed as an artwork wall.
        return menuItems[row] == "Cover Flow" ? .albumCollage : .albumSlideshow
    }
}
