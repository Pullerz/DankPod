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
    let label = UILabel()
    var indicatorButton: UIButton?
    var indicatorButtonShouldChange: Bool = false

    
    init() {
        super.init(style: .default, reuseIdentifier: nil)
        self.textLabel?.font = UIFont(name: "Helvetica-Bold", size: 15)
        self.accessoryType = .disclosureIndicator
        self.tintColor = .black
        self.selectionStyle = .blue
        self.accessoryView?.tintColor = .white
        if let subviews = self.accessoryView?.subviews {
            for subview in subviews {
                subview.tintColor = .white
            }
        }
    
        background.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(background)
        background.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        background.leftAnchor.constraint(equalTo: self.leftAnchor).isActive = true
        background.rightAnchor.constraint(equalTo: self.rightAnchor).isActive = true
        background.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
        background.isHidden = true
        background.backgroundColor = .red
        
        guard let textLabel = self.textLabel else { return }
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont(name: "Helvetica-Bold", size: 15)
        self.addSubview(label)
        label.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
        label.leftAnchor.constraint(equalTo: self.leftAnchor, constant: 15).isActive = true
        label.rightAnchor.constraint(equalTo: self.rightAnchor, constant: -20).isActive = true
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        
    }
    
    override func layoutSubviews() {
        if let indicatorButton = allSubviews.compactMap({ $0 as? UIButton }).last {
            self.indicatorButton = indicatorButton
            if indicatorButtonShouldChange == true && self.isSelected {
                self.setIndicatorButtonTint(color: .white)
                indicatorButtonShouldChange = false
            }
         }
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
            self.label.textColor = .white
            self.tintColor = .white
            self.background.isHidden = false

            self.setIndicatorButtonTint(color: .white)
            
        } else {
            self.label.textColor = .black
            self.tintColor = .black
            self.background.isHidden = true
            
            self.setIndicatorButtonTint(color: UIColor.lightGray)
        }
        // Configure the view for the selected state
    }
    
    func setIndicatorButtonTint(color: UIColor) {
        if let indicatorButton = self.indicatorButton {
            let image = indicatorButton.backgroundImage(for: .normal)?.withRenderingMode(.alwaysTemplate)
            indicatorButton.setBackgroundImage(image, for: .normal)
            indicatorButton.tintColor = color
        } else {
            indicatorButtonShouldChange = true
        }
    }

}

extension UIView {
   var allSubviews: [UIView] {
      return subviews.flatMap { [$0] + $0.allSubviews }
   }
}
