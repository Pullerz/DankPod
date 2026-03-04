//
//  PhotosMenuViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import Photos

class PhotosMenuViewController: UIViewController, ClickWheelProtocol {
    var menuItems: [String] = []
    let tableView: UITableView = UITableView()
    var albumCollections: [PHAssetCollection] = []
    
    var counter: Int = 0
    var hasSetupUI = false
    var hasRequestedAccess = false
    private var lastAuthStatus: PHAuthorizationStatus = .notDetermined
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = "Photos"
        
        if !hasRequestedAccess {
            hasRequestedAccess = true
            PHPhotoLibrary.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    self?.lastAuthStatus = status
                    self?.loadAlbums(status: status)
                }
            }
        } else {
            // Re-load albums each time we appear so Time Machine filter changes take effect
            loadAlbums(status: lastAuthStatus)
        }
    }
    
    private func timeMachinePhotoFetchOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let year = SettingsStore.shared.timeMachineYear
        if year > 0 {
            var components = DateComponents()
            components.year = year + 1
            components.month = 1
            components.day = 1
            if let cutoff = Calendar.current.date(from: components) {
                fetchOptions.predicate = NSPredicate(format: "mediaType = %d AND creationDate < %@", PHAssetMediaType.image.rawValue, cutoff as NSDate)
            } else {
                fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            }
        } else {
            fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        }
        return fetchOptions
    }
    
    func loadAlbums(status: PHAuthorizationStatus) {
        menuItems.removeAll()
        albumCollections.removeAll()
        
        var isAuthorized = status == .authorized
        if #available(iOS 14, *) {
            isAuthorized = isAuthorized || status == .limited
        }
        
        if isAuthorized {
            // "All Photos" is always first
            menuItems.append("All Photos")
            albumCollections.append(PHAssetCollection()) // placeholder for "All Photos"
            
            // Camera Roll (smart album)
            let filterOptions = self.timeMachinePhotoFetchOptions()
            let cameraRoll = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
            cameraRoll.enumerateObjects { (collection, _, _) in
                let assets = PHAsset.fetchAssets(in: collection, options: filterOptions)
                if assets.count > 0 {
                    self.menuItems.append(collection.localizedTitle ?? "Camera Roll")
                    self.albumCollections.append(collection)
                }
            }
            
            // Favorites
            let favorites = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil)
            favorites.enumerateObjects { (collection, _, _) in
                let assets = PHAsset.fetchAssets(in: collection, options: filterOptions)
                if assets.count > 0 {
                    self.menuItems.append(collection.localizedTitle ?? "Favorites")
                    self.albumCollections.append(collection)
                }
            }
            
            // User albums
            let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            userAlbums.enumerateObjects { (collection, _, _) in
                let assets = PHAsset.fetchAssets(in: collection, options: filterOptions)
                if assets.count > 0 {
                    self.menuItems.append(collection.localizedTitle ?? "Untitled Album")
                    self.albumCollections.append(collection)
                }
            }
            
            // "Settings" is always last
            menuItems.append("Settings")
            albumCollections.append(PHAssetCollection()) // placeholder for Settings
        } else {
            menuItems.append("No Photo Access")
            albumCollections.append(PHAssetCollection())
        }
        
        tableView.reloadData()
        if menuItems.count > 0 {
            tableView.selectRow(at: IndexPath(row: counter, section: 0), animated: false, scrollPosition: .top)
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
            if menuItems[counter] == "No Photo Access" {
                return
            }
            
            if menuItems[counter] == "Settings" {
                let vc = PhotoSettingsViewController()
                self.navigationController?.pushViewController(vc, animated: true)
                return
            }
            
            let vc = PhotosGridViewController()
            let fetchOptions = timeMachinePhotoFetchOptions()
            
            if menuItems[counter] == "All Photos" {
                vc.photoAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                vc.albumTitle = "All Photos"
            } else {
                let collection = albumCollections[counter]
                vc.photoAssets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                vc.albumTitle = menuItems[counter]
            }
            
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }


}

extension PhotosMenuViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.menuItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = CustomTableViewCell()
        cell.label.text = menuItems[indexPath.row]
        cell.selectionStyle = .none
        if menuItems[indexPath.row] == "No Photo Access" {
            cell.accessoryType = .none
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }


}
