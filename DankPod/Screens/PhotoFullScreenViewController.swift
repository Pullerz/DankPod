//
//  PhotoFullScreenViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit
import Photos

class PhotoFullScreenViewController: UIViewController, ClickWheelProtocol {
    var photoAssets: PHFetchResult<PHAsset>!
    var currentIndex: Int = 0
    var hasSetupUI = false
    var imageView: UIImageView!
    var loadingSpinner: UIActivityIndicatorView!
    var isSlideshow: Bool = false
    var slideshowTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        setupUI()
        AppDelegate.baseVC.clickWheelDelegate = self
        updateNavTitle()
        loadCurrentPhoto()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        stopSlideshow()
    }
    
    func setupUI() {
        if !hasSetupUI {
            self.view.backgroundColor = .black
            
            imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.backgroundColor = .black
            view.addSubview(imageView)
            imageView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            imageView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            imageView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            
            loadingSpinner = UIActivityIndicatorView(style: .white)
            loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
            loadingSpinner.hidesWhenStopped = true
            view.addSubview(loadingSpinner)
            loadingSpinner.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
            loadingSpinner.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            
            hasSetupUI = true
        }
    }
    
    func updateNavTitle() {
        AppDelegate.baseVC.navBarTitle = "\(currentIndex + 1) of \(photoAssets.count)"
    }
    
    func loadCurrentPhoto() {
        let asset = photoAssets[currentIndex]
        let targetSize = CGSize(width: UIScreen.main.bounds.width * UIScreen.main.scale, height: UIScreen.main.bounds.height * UIScreen.main.scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        loadingSpinner.startAnimating()
        
        PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { [weak self] image, _ in
            self?.loadingSpinner.stopAnimating()
            self?.imageView.image = image
        }
        updateNavTitle()
    }
    
    func navigateToPhoto(index: Int) {
        guard index >= 0 && index < photoAssets.count else { return }
        currentIndex = index
        
        if isSlideshow {
            let transition = UserDefaults.standard.string(forKey: "slideshowTransition") ?? "Cross Fade"
            if transition == "Fade to Black" {
                UIView.animate(withDuration: 0.25, animations: {
                    self.imageView.alpha = 0
                }, completion: { _ in
                    self.loadCurrentPhoto()
                    UIView.animate(withDuration: 0.25) {
                        self.imageView.alpha = 1
                    }
                })
            } else {
                UIView.transition(with: imageView, duration: 0.5, options: .transitionCrossDissolve, animations: {
                    self.loadCurrentPhoto()
                }, completion: nil)
            }
        } else {
            loadCurrentPhoto()
        }
    }
    
    func buildShuffledIndices() -> [Int] {
        var indices = Array(0..<photoAssets.count)
        indices.shuffle()
        return indices
    }
    
    func startSlideshow() {
        let storedTime = UserDefaults.standard.double(forKey: "slideshowTimePerSlide")
        
        // Manual mode (negative sentinel) — no auto-advance, no slideshow state
        if storedTime < 0 {
            return
        }
        
        isSlideshow = true
        
        // Default to 3s when unset (0.0)
        let timePerSlide = storedTime > 0 ? storedTime : 3.0
        
        let shouldShuffle = UserDefaults.standard.bool(forKey: "slideshowShuffle")
        var shuffledIndices: [Int] = []
        var shufflePosition = 0
        
        if shouldShuffle {
            shuffledIndices = buildShuffledIndices()
            // Start from current photo in shuffle order
            if let idx = shuffledIndices.firstIndex(of: currentIndex) {
                shuffledIndices.remove(at: idx)
                shuffledIndices.insert(currentIndex, at: 0)
            }
            shufflePosition = 0
        }
        
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: timePerSlide, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let shouldRepeat = UserDefaults.standard.bool(forKey: "slideshowRepeat")
            
            if shouldShuffle {
                shufflePosition += 1
                if shufflePosition >= shuffledIndices.count {
                    if shouldRepeat {
                        shuffledIndices = self.buildShuffledIndices()
                        shufflePosition = 0
                        self.navigateToPhoto(index: shuffledIndices[shufflePosition])
                    } else {
                        self.stopSlideshow()
                    }
                } else {
                    self.navigateToPhoto(index: shuffledIndices[shufflePosition])
                }
            } else {
                let nextIndex = self.currentIndex + 1
                if nextIndex >= self.photoAssets.count {
                    if shouldRepeat {
                        self.navigateToPhoto(index: 0)
                    } else {
                        self.stopSlideshow()
                    }
                } else {
                    self.navigateToPhoto(index: nextIndex)
                }
            }
        }
    }
    
    func stopSlideshow() {
        isSlideshow = false
        slideshowTimer?.invalidate()
        slideshowTimer = nil
    }
    
    func toggleSlideshow() {
        if isSlideshow {
            stopSlideshow()
        } else {
            startSlideshow()
        }
    }
    
    
    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        if (rotationDirection == .CLOCKWISE) {
            if (currentIndex + 1 <= photoAssets.count - 1) {
                navigateToPhoto(index: currentIndex + 1)
            }
        } else {
            if (currentIndex > 0) {
                navigateToPhoto(index: currentIndex - 1)
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
            if (currentIndex + 1 <= photoAssets.count - 1) {
                navigateToPhoto(index: currentIndex + 1)
            }
        }
    }
    
    func previousSongPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            if (currentIndex > 0) {
                navigateToPhoto(index: currentIndex - 1)
            }
        }
    }
    
    func menuPressed(pressure: ClickWheelTouchPressure) {
        if isSlideshow {
            stopSlideshow()
            return
        }
        if (pressure == .NORMAL) {
            self.navigationController?.popViewController(animated: true)
        } else if (pressure == .FORCE) {
            self.navigationController?.popToRootViewController(animated: true)
        }
    }
    
    func centerPressed(pressure: ClickWheelTouchPressure) {
        if pressure == .NORMAL {
            toggleSlideshow()
        }
    }

}
