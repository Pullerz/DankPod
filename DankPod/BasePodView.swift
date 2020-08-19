//
//  ViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class BasePodView: UIViewController, UIGestureRecognizerDelegate {

    private let safetyBar = UIView()
    public let navBar = UIView()
    private var navBarTitleLabel = UILabel()
    public var navBarTitle: String {
        set {
            self.navBarTitleLabel.text = newValue
        }
        get {
            return self.navBarTitleLabel.text!
        }
    }
    public var screen: UIView = UIView()
    public var clickWheel: UIImageView!
    public var clickWheelDelegate: ClickWheelProtocol!
    
    let centerClickLabel = UIButton()
    let playPauseLabel = UIButton()
    let previousSongLabel = UIButton()
    let nextSongLabel = UIButton()
    let menuLabel = UIButton()
    let feedbackLabel = UILabel()
    var clickwheelResolution: Int = 10
    let clickWheelOverlay = UIView()
    
    var circleGR: CircleGestureRecogniser!
    var forceTapGR: ForceTouchTapGestureRecogniser!
    let beneathScreen = UIView()
    let bodyBackground = UIImageView()
    
    let menuButton = UIView()
    let nextSongButton = UIView()
    let prevSongButton = UIView()
    let playPauseButton = UIView()
    let centerButton = UIView()
    
    let playbackStatusIcon: UIImageView = UIImageView()
    let shuffleIcon: UIImageView = UIImageView()
    let batteryIcon: UIImageView = UIImageView()
    let queueIcon: UIImageView = UIImageView()
    
    var currentValue:CGFloat = 0.0 {
        didSet {
            if (currentValue > 100) {
                currentValue = 100
            }
            if (currentValue < 0) {
                currentValue = 0
            }
        }
    }
    
    let rotateAnimation = CABasicAnimation()
    fileprivate var rotation: CGFloat = 0
    fileprivate var startRotationAngle: CGFloat = 0
    var lastUpdate: CGFloat = 0
    var calls: Int = 0
    var resetValue: CGFloat = 0
    var hasLayedOut = false
    
    var nextSongHeld = false
    var previousSongHeld = false
    var queueMode = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        setupNavBar()
        setupScreen()
        setupClickWheel()
        NotificationCenter.default.addObserver(self, selector: #selector(self.setBatteryIcon), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
    }
    
    override func viewDidLayoutSubviews() {
        var colors: [UIColor]!
        
        if (safetyBar.frame.height > 0) {
            colors = [UIColor.gradientVeryLightGrey, UIColor.gradientDarkGrey]
        } else {
            colors = [UIColor.gradientLightGrey, UIColor.gradientDarkGrey]
        }
        
        navBar.removeGradient()
        navBar.applyGradient(colours: colors)

        
        circleGR.midPoint = clickWheelOverlay.center
        
        
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
 

    private func setupNavBar() {
        self.view.backgroundColor = .white
        
        safetyBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(safetyBar)
        safetyBar.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        safetyBar.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        safetyBar.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        if #available(iOS 11.0, *) {
            safetyBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        } else {
            safetyBar.bottomAnchor.constraint(equalTo: view.topAnchor).isActive = true
        }
        
        safetyBar.backgroundColor = .green
        
        let navBarBottom = UIView()
        navBarBottom.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navBarBottom)
        navBarBottom.topAnchor.constraint(equalTo: safetyBar.bottomAnchor).isActive = true
        navBarBottom.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        navBarBottom.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        navBarBottom.heightAnchor.constraint(equalToConstant: 27).isActive = true
        navBarBottom.backgroundColor = .white
        navBarBottom.layer.shadowColor = UIColor.black.cgColor
        navBarBottom.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        navBarBottom.layer.shadowOpacity = 0.5
        
        navBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navBar)
        navBar.topAnchor.constraint(equalTo: safetyBar.topAnchor).isActive = true
        navBar.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        navBar.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        navBar.bottomAnchor.constraint(equalTo: navBarBottom.bottomAnchor).isActive = true
        navBar.backgroundColor = .red
        
        navBarTitleLabel = UILabel()
        navBarTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(navBarTitleLabel)
        navBarTitleLabel.centerYAnchor.constraint(equalTo: navBarBottom.centerYAnchor, constant: -5).isActive = true
        navBarTitleLabel.centerXAnchor.constraint(equalTo: navBarBottom.centerXAnchor).isActive = true
        navBarTitleLabel.font = UIFont(name: "Helvetica-Bold", size: 17)
        navBarTitleLabel.textColor = .black
        navBarTitleLabel.textAlignment = .center
        navBarTitleLabel.text = "iPod"
        
        playbackStatusIcon.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(playbackStatusIcon)
        playbackStatusIcon.leftAnchor.constraint(equalTo: navBar.leftAnchor, constant: 20).isActive = true
        playbackStatusIcon.centerYAnchor.constraint(equalTo: navBarTitleLabel.centerYAnchor).isActive = true
        playbackStatusIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        playbackStatusIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        if AppDelegate.music.musicPlayer.playbackState == .playing {
            setPlaybackIcon(state: .playing)
        }
        
        shuffleIcon.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(shuffleIcon)
        shuffleIcon.leftAnchor.constraint(equalTo: playbackStatusIcon.rightAnchor, constant: 7).isActive = true
        shuffleIcon.centerYAnchor.constraint(equalTo: navBarTitleLabel.centerYAnchor).isActive = true
        shuffleIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        shuffleIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true
        shuffleIcon.image = #imageLiteral(resourceName: "navbarShuffleIcon")
        shuffleIcon.isHidden = true
        
        queueIcon.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(queueIcon)
        queueIcon.leftAnchor.constraint(equalTo: shuffleIcon.rightAnchor, constant: 7).isActive = true
        queueIcon.centerYAnchor.constraint(equalTo: navBarTitleLabel.centerYAnchor).isActive = true
        queueIcon.widthAnchor.constraint(equalToConstant: 12).isActive = true
        queueIcon.heightAnchor.constraint(equalToConstant: 12).isActive = true
        queueIcon.image = #imageLiteral(resourceName: "qeueIcon")
        queueIcon.isHidden = true
        
        batteryIcon.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(batteryIcon)
        batteryIcon.rightAnchor.constraint(equalTo: navBar.rightAnchor, constant: -20).isActive = true
        batteryIcon.centerYAnchor.constraint(equalTo: navBarTitleLabel.centerYAnchor).isActive = true
        batteryIcon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        batteryIcon.heightAnchor.constraint(equalToConstant: 13).isActive = true
        
        setBatteryIcon()
    }

    
    private func setupScreen() {
        screen.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(screen)
        screen.topAnchor.constraint(equalTo: navBar.bottomAnchor).isActive = true
        screen.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        screen.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        screen.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.4, constant: 0).isActive = true
    }
    
    private func setupClickWheel() {
        bodyBackground.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bodyBackground)
        bodyBackground.topAnchor.constraint(equalTo: screen.bottomAnchor).isActive = true
        bodyBackground.leftAnchor.constraint(equalTo: screen.leftAnchor).isActive = true
        bodyBackground.rightAnchor.constraint(equalTo: screen.rightAnchor).isActive = true
        bodyBackground.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        bodyBackground.image = #imageLiteral(resourceName: "alumninium_texture")
        bodyBackground.alpha = 0.35
        
        beneathScreen.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(beneathScreen)
        beneathScreen.topAnchor.constraint(equalTo: screen.bottomAnchor).isActive = true
        beneathScreen.leftAnchor.constraint(equalTo: screen.leftAnchor).isActive = true
        beneathScreen.rightAnchor.constraint(equalTo: screen.rightAnchor).isActive = true
        beneathScreen.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        beneathScreen.backgroundColor = .clear
        
        let bezel = UIView()
        bezel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bezel)
        bezel.centerYAnchor.constraint(equalTo: beneathScreen.topAnchor).isActive = true
        bezel.leftAnchor.constraint(equalTo: beneathScreen.leftAnchor).isActive = true
        bezel.rightAnchor.constraint(equalTo: beneathScreen.rightAnchor).isActive = true
        bezel.heightAnchor.constraint(equalToConstant: 2).isActive = true
        bezel.backgroundColor = .lightGray
        
        clickWheel = UIImageView(image: #imageLiteral(resourceName: "clickwheelbackground"))
        clickWheel.translatesAutoresizingMaskIntoConstraints = false
        beneathScreen.addSubview(clickWheel)
        clickWheel.topAnchor.constraint(equalTo: beneathScreen.topAnchor, constant: 35).isActive = true
        clickWheel.centerXAnchor.constraint(equalTo: beneathScreen.centerXAnchor).isActive = true
        clickWheel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.75).isActive = true
        clickWheel.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.75).isActive = true
        
       
        menuLabel.setAttributedTitle(NSAttributedString(string: "MENU", attributes: [NSAttributedString.Key.font: UIFont(name: "Helvetica-Bold", size: 17)!, NSAttributedString.Key.foregroundColor: UIColor.white]), for: .normal)
        menuLabel.translatesAutoresizingMaskIntoConstraints = false
        beneathScreen.addSubview(menuLabel)
        menuLabel.topAnchor.constraint(equalTo: clickWheel.topAnchor, constant: 15).isActive = true
        menuLabel.centerXAnchor.constraint(equalTo: clickWheel.centerXAnchor).isActive = true
        
        
        nextSongLabel.setImage(#imageLiteral(resourceName: "nextSong"), for: .normal)
        nextSongLabel.tintColor = UIColor.white
        nextSongLabel.translatesAutoresizingMaskIntoConstraints = false
        beneathScreen.addSubview(nextSongLabel)
        nextSongLabel.rightAnchor.constraint(equalTo: clickWheel.rightAnchor, constant: -18).isActive = true
        nextSongLabel.centerYAnchor.constraint(equalTo: clickWheel.centerYAnchor).isActive = true
        nextSongLabel.widthAnchor.constraint(equalToConstant: 25).isActive = true
        nextSongLabel.heightAnchor.constraint(equalToConstant: 25).isActive = true
    
        previousSongLabel.setImage(#imageLiteral(resourceName: "previousSong"), for: .normal)
        previousSongLabel.tintColor = UIColor.white
        previousSongLabel.translatesAutoresizingMaskIntoConstraints = false
        beneathScreen.addSubview(previousSongLabel)
        previousSongLabel.leftAnchor.constraint(equalTo: clickWheel.leftAnchor, constant: 18).isActive = true
        previousSongLabel.centerYAnchor.constraint(equalTo: clickWheel.centerYAnchor).isActive = true
        previousSongLabel.widthAnchor.constraint(equalToConstant: 25).isActive = true
        previousSongLabel.heightAnchor.constraint(equalToConstant: 25).isActive = true
        
        playPauseLabel.setImage(#imageLiteral(resourceName: "playPause"), for: .normal)
        playPauseLabel.tintColor = UIColor.white
        playPauseLabel.translatesAutoresizingMaskIntoConstraints = false
        beneathScreen.addSubview(playPauseLabel)
        playPauseLabel.centerXAnchor.constraint(equalTo: clickWheel.centerXAnchor).isActive = true
        playPauseLabel.bottomAnchor.constraint(equalTo: clickWheel.bottomAnchor, constant: -10).isActive = true
        playPauseLabel.widthAnchor.constraint(equalToConstant: 28).isActive = true
        playPauseLabel.heightAnchor.constraint(equalToConstant: 28).isActive = true

        clickWheelOverlay.translatesAutoresizingMaskIntoConstraints = false
        beneathScreen.addSubview(clickWheelOverlay)
        clickWheelOverlay.topAnchor.constraint(equalTo: clickWheel.topAnchor).isActive = true
        clickWheelOverlay.leftAnchor.constraint(equalTo: clickWheel.leftAnchor).isActive = true
        clickWheelOverlay.rightAnchor.constraint(equalTo: clickWheel.rightAnchor).isActive = true
        clickWheelOverlay.bottomAnchor.constraint(equalTo: clickWheel.bottomAnchor).isActive = true
        clickWheelOverlay.isUserInteractionEnabled = true
        circleGR = CircleGestureRecogniser(midPoint: clickWheelOverlay.center, target: self, action: #selector(self.rotateGesture(recognizer:)))
        circleGR.delegate = self
        circleGR.cancelsTouchesInView = false
        clickWheelOverlay.addGestureRecognizer(circleGR)
        //UITapGestureRecognizer(target: self, action: #selector(self.wheelClicked(sender:)))
        forceTapGR = ForceTouchTapGestureRecogniser(target: self, action: #selector(self.wheelClicked(sender:)))
        forceTapGR.delegate = self
        forceTapGR.cancelsTouchesInView = false
        clickWheelOverlay.addGestureRecognizer(forceTapGR)
        let lpGR = UILongPressGestureRecognizer(target: self, action: #selector(self.wheelLongPress(sender:)))
        lpGR.minimumPressDuration = 0.1
        lpGR.delegate = self
        lpGR.cancelsTouchesInView = true
        clickWheelOverlay.addGestureRecognizer(lpGR)
        
        
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        beneathScreen.addSubview(menuButton)
        menuButton.topAnchor.constraint(equalTo: clickWheel.topAnchor, constant: 10).isActive = true
        menuButton.widthAnchor.constraint(equalTo: clickWheel.widthAnchor, multiplier: 0.3).isActive = true
        menuButton.heightAnchor.constraint(equalTo: clickWheel.heightAnchor, multiplier: 0.3).isActive = true
        menuButton.centerXAnchor.constraint(equalTo: clickWheel.centerXAnchor).isActive = true
        menuButton.backgroundColor = .clear
        menuButton.isUserInteractionEnabled = false
        
        nextSongButton.translatesAutoresizingMaskIntoConstraints = false
        beneathScreen.addSubview(nextSongButton)
        nextSongButton.centerYAnchor.constraint(equalTo: clickWheel.centerYAnchor).isActive = true
        nextSongButton.widthAnchor.constraint(equalTo: clickWheel.widthAnchor, multiplier: 0.3).isActive = true
        nextSongButton.heightAnchor.constraint(equalTo: clickWheel.heightAnchor, multiplier: 0.3).isActive = true
        nextSongButton.rightAnchor.constraint(equalTo: clickWheel.rightAnchor, constant: -10).isActive = true
        nextSongButton.backgroundColor = .clear
        nextSongButton.isUserInteractionEnabled = false
        
        prevSongButton.translatesAutoresizingMaskIntoConstraints = false
        beneathScreen.addSubview(prevSongButton)
        prevSongButton.centerYAnchor.constraint(equalTo: clickWheel.centerYAnchor).isActive = true
        prevSongButton.widthAnchor.constraint(equalTo: clickWheel.widthAnchor, multiplier: 0.3).isActive = true
        prevSongButton.heightAnchor.constraint(equalTo: clickWheel.heightAnchor, multiplier: 0.3).isActive = true
        prevSongButton.leftAnchor.constraint(equalTo: clickWheel.leftAnchor, constant: 10).isActive = true
        prevSongButton.backgroundColor = .clear
        prevSongButton.isUserInteractionEnabled = false
        
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        beneathScreen.addSubview(playPauseButton)
        playPauseButton.bottomAnchor.constraint(equalTo: clickWheel.bottomAnchor, constant: -10).isActive = true
        playPauseButton.widthAnchor.constraint(equalTo: clickWheel.widthAnchor, multiplier: 0.3).isActive = true
        playPauseButton.heightAnchor.constraint(equalTo: clickWheel.heightAnchor, multiplier: 0.3).isActive = true
        playPauseButton.centerXAnchor.constraint(equalTo: clickWheel.centerXAnchor).isActive = true
        playPauseButton.backgroundColor = .clear
        playPauseButton.isUserInteractionEnabled = false
    
        centerButton.translatesAutoresizingMaskIntoConstraints = false
        beneathScreen.addSubview(centerButton)
        centerButton.centerYAnchor.constraint(equalTo: clickWheel.centerYAnchor).isActive = true
        centerButton.widthAnchor.constraint(equalTo: clickWheel.widthAnchor, multiplier: 0.3).isActive = true
        centerButton.heightAnchor.constraint(equalTo: clickWheel.heightAnchor, multiplier: 0.3).isActive = true
        centerButton.centerXAnchor.constraint(equalTo: clickWheel.centerXAnchor).isActive = true
        centerButton.backgroundColor = .clear
        centerButton.isUserInteractionEnabled = false
        
        
    }
    
    
    @objc
    func rotateGesture(recognizer:CircleGestureRecogniser){
        let velocity = recognizer.velocity(in: recognizer.view)
        let magnitude = sqrtf(powf(Float(velocity.x), 2) + powf(Float(velocity.y), 2))
        
        if magnitude > 800 {
            let newVal = map(n: magnitude, start1: 0, stop1: 2000, start2: 10, stop2: 3)
//            print(Int(newVal), magnitude)
            clickwheelResolution = Int(newVal)
        } else {
            clickwheelResolution = 10
        }
        if let rotation = recognizer.rotation, velocity.x != 0 && velocity.y != 0 {
            currentValue += rotation.degrees / 360 * 100
            
            var direction: RotationDirection!
            
            if (currentValue > lastUpdate) {
                direction = RotationDirection.CLOCKWISE
            } else if (currentValue < lastUpdate) {
                direction = RotationDirection.COUNTER_CLOCKWISE
            } else if (currentValue == lastUpdate && currentValue == 100) {
                direction = RotationDirection.CLOCKWISE
            } else if (currentValue == lastUpdate && currentValue == 0) {
                direction = RotationDirection.COUNTER_CLOCKWISE
            }
            
            
            lastUpdate = currentValue
            
            calls += 1
            if (calls >= clickwheelResolution && direction != nil) {
                self.clickWheelDelegate.clickWheelDidRotate(rotationDirection: direction)
                let generator = UISelectionFeedbackGenerator()
                generator.selectionChanged()
                calls = 0
            }
        }
        if recognizer.state == .ended {
            clickwheelResolution = 10
        }
    }
    
    @objc func wheelLongPress(sender: UILongPressGestureRecognizer) {
        let touchLocation = sender.location(ofTouch: 0, in: beneathScreen)
        let forceGenerator = UIImpactFeedbackGenerator(style: .heavy)
        
        if sender.state == .ended {
            if forceTapGR.isForceTouch {
                if (touchLocation.x >= menuButton.frame.minX && touchLocation.x <= menuButton.frame.maxX
                    && touchLocation.y >= menuButton.frame.minY && touchLocation.y <= menuButton.frame.maxY) {
                    self.clickWheelDelegate.menuPressed(pressure: .FORCE_ENDED)
                    forceGenerator.impactOccurred()
                } else if (touchLocation.x >= nextSongButton.frame.minX && touchLocation.x <= nextSongButton.frame.maxX
                    && touchLocation.y >= nextSongButton.frame.minY && touchLocation.y <= nextSongButton.frame.maxY) {
                    self.clickWheelDelegate.nextSongPressed(pressure: .FORCE_ENDED)
                    nextSongHeld = false
                    forceGenerator.impactOccurred()
                } else if (touchLocation.x >= prevSongButton.frame.minX && touchLocation.x <= prevSongButton.frame.maxX
                   && touchLocation.y >= prevSongButton.frame.minY && touchLocation.y <= prevSongButton.frame.maxY) {
                    self.clickWheelDelegate.previousSongPressed(pressure: .FORCE_ENDED)
                    previousSongHeld = false
                    forceGenerator.impactOccurred()
                } else if (touchLocation.x >= playPauseButton.frame.minX && touchLocation.x <= playPauseButton.frame.maxX
                   && touchLocation.y >= playPauseButton.frame.minY && touchLocation.y <= playPauseButton.frame.maxY) {
                    self.clickWheelDelegate.playPausePressed(pressure: .FORCE_ENDED)
                    forceGenerator.impactOccurred()
                } else if (touchLocation.x >= centerButton.frame.minX && touchLocation.x <= centerButton.frame.maxX
                   && touchLocation.y >= centerButton.frame.minY && touchLocation.y <= centerButton.frame.maxY) {
                    self.clickWheelDelegate.centerPressed(pressure: .FORCE_ENDED)
                    forceGenerator.impactOccurred()
                }
                forceTapGR.isForceTouch = false
            }
        }
    }
    
    
    @objc func wheelClicked(sender: ForceTouchTapGestureRecogniser) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        let forceGenerator = UIImpactFeedbackGenerator(style: .heavy)
        
        let touchLocation = sender.location(ofTouch: 0, in: beneathScreen)
        
        if (touchLocation.x >= menuButton.frame.minX && touchLocation.x <= menuButton.frame.maxX
            && touchLocation.y >= menuButton.frame.minY && touchLocation.y <= menuButton.frame.maxY) {
            if sender.isForceTouch == true {
                self.clickWheelDelegate.menuPressed(pressure: .FORCE)
                forceGenerator.impactOccurred()
            } else {
                self.clickWheelDelegate.menuPressed(pressure: .NORMAL)
                generator.impactOccurred()
            }
        } else if (touchLocation.x >= nextSongButton.frame.minX && touchLocation.x <= nextSongButton.frame.maxX
            && touchLocation.y >= nextSongButton.frame.minY && touchLocation.y <= nextSongButton.frame.maxY) {
            if sender.isForceTouch == true {
                self.clickWheelDelegate.nextSongPressed(pressure: .FORCE)
                nextSongHeld = true
                forceGenerator.impactOccurred()
            } else {
                self.clickWheelDelegate.nextSongPressed(pressure: .NORMAL)
                generator.impactOccurred()
            }
        } else if (touchLocation.x >= prevSongButton.frame.minX && touchLocation.x <= prevSongButton.frame.maxX
           && touchLocation.y >= prevSongButton.frame.minY && touchLocation.y <= prevSongButton.frame.maxY) {
            if sender.isForceTouch == true {
                self.clickWheelDelegate.previousSongPressed(pressure: .FORCE)
                previousSongHeld = true
                forceGenerator.impactOccurred()
            } else {
                self.clickWheelDelegate.previousSongPressed(pressure: .NORMAL)
                generator.impactOccurred()
            }
        } else if (touchLocation.x >= playPauseButton.frame.minX && touchLocation.x <= playPauseButton.frame.maxX
           && touchLocation.y >= playPauseButton.frame.minY && touchLocation.y <= playPauseButton.frame.maxY) {
            if sender.isForceTouch == true {
                self.clickWheelDelegate.playPausePressed(pressure: .FORCE)
                forceGenerator.impactOccurred()
            } else {
                self.clickWheelDelegate.playPausePressed(pressure: .NORMAL)
                generator.impactOccurred()
            }
        } else if (touchLocation.x >= centerButton.frame.minX && touchLocation.x <= centerButton.frame.maxX
           && touchLocation.y >= centerButton.frame.minY && touchLocation.y <= centerButton.frame.maxY) {
            if sender.isForceTouch == true {
                self.clickWheelDelegate.centerPressed(pressure: .FORCE)
                forceGenerator.impactOccurred()
            } else {
                self.clickWheelDelegate.centerPressed(pressure: .NORMAL)
                generator.impactOccurred()
            }
        }
        
        
        
        if nextSongHeld && previousSongHeld {
            //Toggle queue mode
            queueIcon.isHidden = !queueIcon.isHidden
            nextSongHeld = false
            previousSongHeld = false
            AppDelegate.music.toggleQueueMode()
        }
        
    }
    
    
    func setPlaybackIcon(state: PlaybackState) {
        switch state {
        case .playing:
            playbackStatusIcon.image = #imageLiteral(resourceName: "navbarPlayIcon")
        case .paused:
            playbackStatusIcon.image = #imageLiteral(resourceName: "navbarPauseIcon")
        case .stopped:
            playbackStatusIcon.isHidden = true
        }
    }
    
    @objc
    func setBatteryIcon() {
        let level = UIDevice.current.batteryLevel * 100
        if level > 80 {
            batteryIcon.image = #imageLiteral(resourceName: "battery_100")
        } else if level <= 80 && level > 60 {
            batteryIcon.image = #imageLiteral(resourceName: "battery_80")
        } else if level <= 60 && level > 40 {
            batteryIcon.image = #imageLiteral(resourceName: "battery_60")
        } else if level <= 40 && level > 20 {
            batteryIcon.image = #imageLiteral(resourceName: "battery_40")
        } else if level <= 20 {
            batteryIcon.image = #imageLiteral(resourceName: "battery_20")
        }
    }
    
    
    
}




enum RotationDirection {
    case CLOCKWISE
    case COUNTER_CLOCKWISE
}

enum PlaybackState {
    case playing
    case paused
    case stopped
}
