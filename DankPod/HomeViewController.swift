//
//  HomeViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class MainViewController: BasePodView, ClickWheelProtocol {
    

    let menuItems: [String] = ["Music", "Photos", "Videos", "Extras", "Settings", "Shuffle Songs"]
    let tableView: UITableView = UITableView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navBarTitle = "iPod"
        self.clickWheelDelegate = self
    }
    
   
    func clickWheelDidRotate(rotationDirection: RotationDirection) {
        switch rotationDirection {
        case .CLOCKWISE:
            print("Click wheel rotated clockwise")
        case .COUNTER_CLOCKWISE:
            print("Click wheel rotated counter clockwise")
        }
    }
    
    func playPausePressed() {
        
    }
    
    func nextSongPressed() {
        
    }
    
    func previousSongPressed() {
        
    }
    
    func menuPressed() {
        
    }

    func centerPressed() {
        
    }
    

}
