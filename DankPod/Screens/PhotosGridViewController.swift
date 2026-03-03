//
//  PhotosGridViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import Photos

class PhotosGridViewController: UIViewController, ClickWheelProtocol {
    var photoAssets: PHFetchResult<PHAsset>!
    var albumTitle: String = "All Photos"
    var counter: Int = 0
    var currentPage: Int = 0
    var hasSetupUI = false
    
    let photosPerPage = 25
    let columns = 5
    let spacing: CGFloat = 2
    
    var collectionView: UICollectionView!
    let imageManager = PHCachingImageManager()
    var thumbnailSize: CGSize = .zero
    var noPhotosLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        AppDelegate.baseVC.navBarTitle = albumTitle
        
        updateGrid()
    }
    
    func setupUI() {
        if !hasSetupUI {
            self.view.backgroundColor = .black
            
            let cellWidth = (UIScreen.main.bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            thumbnailSize = CGSize(width: cellWidth * UIScreen.main.scale, height: cellWidth * UIScreen.main.scale)
            
            let layout = UICollectionViewFlowLayout()
            layout.itemSize = CGSize(width: cellWidth, height: cellWidth)
            layout.minimumInteritemSpacing = spacing
            layout.minimumLineSpacing = spacing
            layout.sectionInset = .zero
            
            collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
            collectionView.translatesAutoresizingMaskIntoConstraints = false
            collectionView.backgroundColor = .black
            collectionView.register(PhotoThumbnailCell.self, forCellWithReuseIdentifier: "PhotoCell")
            collectionView.delegate = self
            collectionView.dataSource = self
            collectionView.isScrollEnabled = false
            view.addSubview(collectionView)
            collectionView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            
            noPhotosLabel = UILabel()
            noPhotosLabel.translatesAutoresizingMaskIntoConstraints = false
            noPhotosLabel.text = "No Photos"
            noPhotosLabel.font = UIFont(name: "Helvetica-Bold", size: 17)
            noPhotosLabel.textColor = .white
            noPhotosLabel.textAlignment = .center
            noPhotosLabel.isHidden = true
            view.addSubview(noPhotosLabel)
            noPhotosLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
            noPhotosLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            
            hasSetupUI = true
        }
    }
    
    func updateGrid() {
        if photoAssets.count == 0 {
            noPhotosLabel.isHidden = false
            collectionView.isHidden = true
            return
        }
        
        noPhotosLabel.isHidden = true
        collectionView.isHidden = false
        currentPage = counter / photosPerPage
        collectionView.reloadData()
        
        let indexInPage = counter - (currentPage * photosPerPage)
        let ip = IndexPath(item: indexInPage, section: 0)
        collectionView.layoutIfNeeded()
        DispatchQueue.main.async {
            self.highlightCell(at: ip)
        }
    }
    
    func highlightCell(at indexPath: IndexPath) {
        // Clear all highlights
        for cell in collectionView.visibleCells {
            if let photoCell = cell as? PhotoThumbnailCell {
                photoCell.setHighlighted(false)
            }
        }
        // Highlight the selected cell
        if let cell = collectionView.cellForItem(at: indexPath) as? PhotoThumbnailCell {
            cell.setHighlighted(true)
        }
    }
    
    var photosOnCurrentPage: Int {
        let startIndex = currentPage * photosPerPage
        let remaining = photoAssets.count - startIndex
        return min(remaining, photosPerPage)
    }
    
    
    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if photoAssets.count == 0 { return }
        
        if (rotationDirection == .CLOCKWISE) {
            if (counter + 1 <= photoAssets.count - 1) {
                counter += 1
                let newPage = counter / photosPerPage
                if newPage != currentPage {
                    currentPage = newPage
                    collectionView.reloadData()
                    collectionView.layoutIfNeeded()
                }
                let indexInPage = counter - (currentPage * photosPerPage)
                highlightCell(at: IndexPath(item: indexInPage, section: 0))
            }
        } else {
            if (counter > 0) {
                counter -= 1
                let newPage = counter / photosPerPage
                if newPage != currentPage {
                    currentPage = newPage
                    collectionView.reloadData()
                    collectionView.layoutIfNeeded()
                }
                let indexInPage = counter - (currentPage * photosPerPage)
                highlightCell(at: IndexPath(item: indexInPage, section: 0))
            }
        }
    }
    
    func playPausePressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            AppDelegate.music.playPause()
        }
    }
    
    func nextSongPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            if photoAssets.count == 0 { return }
            let newCounter = counter + photosPerPage
            if newCounter < photoAssets.count {
                counter = newCounter
            } else {
                counter = photoAssets.count - 1
            }
            updateGrid()
        }
    }
    
    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            if photoAssets.count == 0 { return }
            let newCounter = counter - photosPerPage
            if newCounter >= 0 {
                counter = newCounter
            } else {
                counter = 0
            }
            updateGrid()
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
        if pressure == .NORMAL {
            if photoAssets.count == 0 { return }
            let vc = PhotoFullScreenViewController()
            vc.photoAssets = photoAssets
            vc.currentIndex = counter
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }

}

extension PhotosGridViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photosOnCurrentPage
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "PhotoCell", for: indexPath) as! PhotoThumbnailCell
        let assetIndex = currentPage * photosPerPage + indexPath.item
        let asset = photoAssets[assetIndex]
        
        cell.assetIdentifier = asset.localIdentifier
        imageManager.requestImage(for: asset, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil) { image, _ in
            if cell.assetIdentifier == asset.localIdentifier {
                cell.imageView.image = image
            }
        }
        
        let indexInPage = counter - (currentPage * photosPerPage)
        cell.setHighlighted(indexPath.item == indexInPage)
        
        return cell
    }
}


class PhotoThumbnailCell: UICollectionViewCell {
    let imageView = UIImageView()
    var assetIdentifier: String = ""
    let highlightBorder = UIView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        imageView.topAnchor.constraint(equalTo: contentView.topAnchor).isActive = true
        imageView.leftAnchor.constraint(equalTo: contentView.leftAnchor).isActive = true
        imageView.rightAnchor.constraint(equalTo: contentView.rightAnchor).isActive = true
        imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
        
        highlightBorder.translatesAutoresizingMaskIntoConstraints = false
        highlightBorder.layer.borderWidth = 3
        highlightBorder.layer.borderColor = UIColor.gradientDarkBlue.cgColor
        highlightBorder.isHidden = true
        contentView.addSubview(highlightBorder)
        highlightBorder.topAnchor.constraint(equalTo: contentView.topAnchor).isActive = true
        highlightBorder.leftAnchor.constraint(equalTo: contentView.leftAnchor).isActive = true
        highlightBorder.rightAnchor.constraint(equalTo: contentView.rightAnchor).isActive = true
        highlightBorder.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setHighlighted(_ highlighted: Bool) {
        highlightBorder.isHidden = !highlighted
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        highlightBorder.isHidden = true
        assetIdentifier = ""
    }
}
