//
//  MadeForYouViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import MusicKit

@available(iOS 15.0, *)
class MadeForYouViewController: UIViewController, ClickWheelProtocol {

    var playlists: [Playlist] = []
    let tableView = UITableView()
    var counter: Int = 0
    var hasSetupUI = false
    let emptyLabel = UILabel()
    let loadingIndicator = UIActivityIndicatorView(style: .medium)
    var isLoading = true
    var hasLoadedOnce = false

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Made For You"
        if !hasLoadedOnce {
            loadPlaylists()
            hasLoadedOnce = true
        } else {
            if !playlists.isEmpty {
                tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .none)
            }
        }
    }

    func loadPlaylists() {
        isLoading = true
        loadingIndicator.startAnimating()
        loadingIndicator.isHidden = false
        emptyLabel.isHidden = true

        Task {
            do {
                let status = await MusicKitService.shared.requestAuthorization()
                guard status == .authorized else {
                    await MainActor.run {
                        self.isLoading = false
                        self.loadingIndicator.stopAnimating()
                        self.loadingIndicator.isHidden = true
                        self.showEmptyState("Apple Music access required")
                    }
                    return
                }

                let fetched = try await MusicKitService.shared.getPersonalPlaylists()
                await MainActor.run {
                    self.playlists = fetched
                    self.isLoading = false
                    self.loadingIndicator.stopAnimating()
                    self.loadingIndicator.isHidden = true
                    self.tableView.reloadData()
                    if !fetched.isEmpty {
                        self.counter = 0
                        self.tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .none)
                    } else {
                        self.showEmptyState("No playlists available")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.loadingIndicator.stopAnimating()
                    self.loadingIndicator.isHidden = true
                    self.showEmptyState("Could not load playlists")
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
        if rotationDirection == .CLOCKWISE {
            if counter + 1 <= playlists.count - 1 {
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
            guard !playlists.isEmpty else { return }
            let vc = MadeForYouSongsViewController()
            vc.playlist = playlists[counter]
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }
}

@available(iOS 15.0, *)
extension MadeForYouViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return playlists.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = playlists[indexPath.row].name
        cell.selectionStyle = .none
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }
}
