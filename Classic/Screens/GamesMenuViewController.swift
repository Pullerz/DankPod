//
//  GamesMenuViewController.swift
//  Classic
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class GamesMenuViewController: UIViewController, ClickWheelProtocol {
    // Alphabetical, as on the iPod. Each launch gets a fresh game.
    let games: [(title: String, make: () -> UIViewController)] = [
        ("Blocks", { BlocksViewController() }),
        ("Brick", { BrickBreakerViewController() }),
        ("iQuiz", { IQuizViewController() }),
        ("Klondike", { KlondikeViewController() }),
        ("Maze", { MazeViewController() }),
        ("Minesweeper", { MinesweeperViewController() }),
        ("Music Quiz", { MusicQuizViewController() }),
        ("Parachute", { ParachuteViewController() }),
        ("Snake", { SnakeViewController() }),
        ("Vortex", { VortexViewController() }),
    ]
    var menuItems: [String] { games.map { $0.title } }
    let tableView: UITableView = UITableView()
    
    var counter: Int = 0
    var hasSetupUI = false
    private lazy var split = SplitMenuLayout(provider: self)
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Games"
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
                tableView.scrollToRow(at: ip, at: .none, animated: false)
                split.selectionDidChange(to: counter)
            }
        } else {
            if (counter > 0) {
                counter -= 1
                let ip = IndexPath(row: counter, section: 0)
                tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
                tableView.scrollToRow(at: ip, at: .none, animated: false)
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
        guard pressure == .NORMAL else { return }
        self.navigationController?.pushViewController(games[counter].make(), animated: true)
    }


}

extension GamesMenuViewController: UITableViewDelegate, UITableViewDataSource {
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


extension GamesMenuViewController: SplitPreviewProviding {
    func splitPreviewKind(forRow row: Int) -> SplitPreviewKind? {
        guard games.indices.contains(row) else { return nil }
        return .game(games[row].title)
    }
}
