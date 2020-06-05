//
//  HomeViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class MainViewController: BasePodView {
    

    
    var selectedViewController: UIViewController!
    var navController: UINavigationController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navBarTitle = "iPod"
        selectedViewController = HomeViewController()
        navController = UINavigationController(rootViewController: selectedViewController)
        navController.isNavigationBarHidden = true
        self.clickWheelDelegate = selectedViewController as? ClickWheelProtocol
        setContainerViewController(viewController: navController)
    }
    
   

 
    
    
    /**
     Sets the contents of the view controller to the currently selected tab
     */
    private func setContainerViewController(viewController: UIViewController) {
        
        //Remove all UI from container
        for subView in self.screen.subviews {
            subView.removeFromSuperview()
        }
        for child in self.children {
            child.removeFromParent()
        }
        
        let controller = viewController
        self.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        self.screen.addSubview(controller.view)
        
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: self.screen.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: self.screen.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: self.screen.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: self.screen.bottomAnchor)
        ])
        
        controller.didMove(toParent: self)
        self.selectedViewController = viewController
        self.view.layoutIfNeeded()
    }

}
