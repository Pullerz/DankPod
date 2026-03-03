//
//  CustomSettingsTableViewCell.swift
//  DankPod
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import UIKit

class CustomSettingsTableViewCell: CustomTableViewCell {

    let valueLabel = UILabel()
    private var valueRightConstraint: NSLayoutConstraint!

    // When true the standard disclosure chevron is shown (default).
    // Set to false for toggle/inline rows and stub rows.
    var showChevron: Bool = true {
        didSet {
            accessoryType = showChevron ? .disclosureIndicator : .none
            valueRightConstraint.constant = showChevron ? -5 : -38
        }
    }

    override init() {
        super.init()

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = UIFont(name: "Helvetica-Bold", size: 14)
        valueLabel.textColor = .black
        valueLabel.textAlignment = .right
        contentView.addSubview(valueLabel)
        valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        valueRightConstraint = valueLabel.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -5)
        valueRightConstraint.isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        valueLabel.textColor = selected ? .white : .black
    }
}
