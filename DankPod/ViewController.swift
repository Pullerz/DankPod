//
//  ViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class BasePodView: UIViewController {

    private let safetyBar = UIView()
    private let navBar = UIView()
    private var navBarTitleLabel = UILabel()
    public var navBarTitle: String {
        set {
            self.navBarTitleLabel.text = newValue
        }
        get {
            return self.navBarTitleLabel.text
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        setupNavBar()
    }
    
    override func viewDidLayoutSubviews() {
        var colors: [UIColor]!
        
        if (safetyBar.frame.height > 0) {
            colors = [UIColor.gradientVeryLightGrey, UIColor.gradientDarkGrey]
        } else {
            colors = [UIColor.gradientLightGrey, UIColor.gradientDarkGrey]
        }
        
        navBar.applyGradient(colours: colors)
    }

    func setupNavBar() {
        self.view.backgroundColor = .white
        
        safetyBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(safetyBar)
        safetyBar.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        safetyBar.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        safetyBar.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        safetyBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        
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
        
        navBarTitleLabel = UILabel()
        navBarTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(navBarTitleLabel)
        navBarTitleLabel.centerYAnchor.constraint(equalTo: navBarBottom.centerYAnchor, constant: -5).isActive = true
        navBarTitleLabel.centerXAnchor.constraint(equalTo: navBarBottom.centerXAnchor).isActive = true
        navBarTitleLabel.font = UIFont(name: "Helvetica-Bold", size: 17)
        navBarTitleLabel.textColor = .black
        navBarTitleLabel.textAlignment = .center
        navBarTitleLabel.text = "iPod"
        
        
        
    }
    
    
}

