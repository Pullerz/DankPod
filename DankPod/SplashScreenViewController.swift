//
//  SplashScreenViewController.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class SplashScreenViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let imageView = UIImageView(image: #imageLiteral(resourceName: "splashIcon"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        imageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.9).isActive = true
        imageView.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.9).isActive = true
        
        let dankPod = UILabel()
        dankPod.translatesAutoresizingMaskIntoConstraints = false
        dankPod.font = UIFont(name: "Helvetica-Bold", size: 50)
        dankPod.text = "DankPod"
        dankPod.textAlignment = .center
        view.addSubview(dankPod)
        dankPod.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 25).isActive = true
        dankPod.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            AppDelegate.baseVC.modalPresentationStyle = .fullScreen
            self.present(AppDelegate.baseVC, animated: true, completion: nil)
        }
        
    }
    


}
