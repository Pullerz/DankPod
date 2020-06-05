//
//  CustomTableViewCell.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class CustomTableViewCell: UITableViewCell {

    let background: UIView = UIView()
    
    init() {
        super.init(style: .default, reuseIdentifier: nil)
        self.textLabel?.font = UIFont(name: "Helvetica-Bold", size: 15)
        self.accessoryType = .disclosureIndicator
        self.tintColor = .black
        self.selectionStyle = .blue
    
        background.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(background)
        background.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        background.leftAnchor.constraint(equalTo: self.leftAnchor).isActive = true
        background.rightAnchor.constraint(equalTo: self.rightAnchor).isActive = true
        background.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        self.sendSubviewToBack(background)
        background.isHidden = true
        background.backgroundColor = .red
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        
    }

    override func layoutIfNeeded() {
        let gradient: CAGradientLayer = CAGradientLayer()
        gradient.frame = self.bounds
        gradient.colors = [UIColor.gradientLightBlue, UIColor.gradientDarkBlue].map { $0.cgColor }
        gradient.locations = nil
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 0, y: 1)
        background.layer.insertSublayer(gradient, at: 0)
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        if (selected) {
            self.textLabel?.textColor = .white
            self.tintColor = .white
            self.background.isHidden = false
        } else {
            self.textLabel?.textColor = .black
            self.tintColor = .black
            self.background.isHidden = true
        }
        // Configure the view for the selected state
    }

}
