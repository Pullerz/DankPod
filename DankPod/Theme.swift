//
//  Theme.swift
//  DankPod
//
//  Created by Alistair Pullen on 03/03/2026.
//  Copyright © 2026 Apullen Developments Ltd. All rights reserved.
//

import UIKit

extension Notification.Name {
    static let themeDidChange = Notification.Name("themeDidChange")
}

struct iPodTheme {
    let name: String
    let bodyColor: UIColor
    let wheelRingColor: UIColor
    let centerButtonColor: UIColor
    let labelTintColor: UIColor
    let navBarGradientTop: UIColor
    let navBarGradientBottom: UIColor
    let textureAlpha: CGFloat
}

class ThemeManager {

    static let shared = ThemeManager()

    static let allThemes: [iPodTheme] = [
        iPodTheme(
            name: "Silver",
            bodyColor: UIColor(hex: "C0C0C0")!,
            wheelRingColor: UIColor(hex: "C0C0C0")!,
            centerButtonColor: UIColor(hex: "D4D4D4")!,
            labelTintColor: .white,
            navBarGradientTop: UIColor.gradientVeryLightGrey,
            navBarGradientBottom: UIColor.gradientDarkGrey,
            textureAlpha: 0.35
        ),
        iPodTheme(
            name: "Black",
            bodyColor: UIColor(hex: "1C1C1E")!,
            wheelRingColor: UIColor(hex: "2C2C2E")!,
            centerButtonColor: UIColor(hex: "3A3A3C")!,
            labelTintColor: .white,
            navBarGradientTop: UIColor(hex: "3A3A3C")!,
            navBarGradientBottom: UIColor(hex: "1C1C1E")!,
            textureAlpha: 0.15
        ),
        iPodTheme(
            name: "Purple",
            bodyColor: UIColor(hex: "6B3FA0")!,
            wheelRingColor: UIColor(hex: "6B3FA0")!,
            centerButtonColor: UIColor(hex: "7E52B3")!,
            labelTintColor: .white,
            navBarGradientTop: UIColor(hex: "8B6DB5")!,
            navBarGradientBottom: UIColor(hex: "5A3490")!,
            textureAlpha: 0.20
        ),
        iPodTheme(
            name: "Blue",
            bodyColor: UIColor(hex: "3B82C4")!,
            wheelRingColor: UIColor(hex: "3B82C4")!,
            centerButtonColor: UIColor(hex: "5A9BD5")!,
            labelTintColor: .white,
            navBarGradientTop: UIColor(hex: "6DA8D9")!,
            navBarGradientBottom: UIColor(hex: "2E6FA8")!,
            textureAlpha: 0.20
        ),
        iPodTheme(
            name: "Green",
            bodyColor: UIColor(hex: "4BA535")!,
            wheelRingColor: UIColor(hex: "4BA535")!,
            centerButtonColor: UIColor(hex: "5CB848")!,
            labelTintColor: .white,
            navBarGradientTop: UIColor(hex: "6DC05A")!,
            navBarGradientBottom: UIColor(hex: "3E8C2C")!,
            textureAlpha: 0.20
        ),
        iPodTheme(
            name: "Yellow",
            bodyColor: UIColor(hex: "F5D100")!,
            wheelRingColor: UIColor(hex: "F5D100")!,
            centerButtonColor: UIColor(hex: "F7DC33")!,
            labelTintColor: UIColor(hex: "6E6E6E")!,
            navBarGradientTop: UIColor(hex: "F8E566")!,
            navBarGradientBottom: UIColor(hex: "D4B300")!,
            textureAlpha: 0.25
        ),
        iPodTheme(
            name: "Orange",
            bodyColor: UIColor(hex: "F27830")!,
            wheelRingColor: UIColor(hex: "F27830")!,
            centerButtonColor: UIColor(hex: "F59055")!,
            labelTintColor: .white,
            navBarGradientTop: UIColor(hex: "F6A070")!,
            navBarGradientBottom: UIColor(hex: "D06020")!,
            textureAlpha: 0.20
        ),
        iPodTheme(
            name: "Pink",
            bodyColor: UIColor(hex: "F472B6")!,
            wheelRingColor: UIColor(hex: "F472B6")!,
            centerButtonColor: UIColor(hex: "F68EC6")!,
            labelTintColor: .white,
            navBarGradientTop: UIColor(hex: "F7A0D0")!,
            navBarGradientBottom: UIColor(hex: "D45E9E")!,
            textureAlpha: 0.20
        ),
        iPodTheme(
            name: "(PRODUCT) RED",
            bodyColor: UIColor(hex: "BF1E2E")!,
            wheelRingColor: UIColor(hex: "BF1E2E")!,
            centerButtonColor: UIColor(hex: "D03040")!,
            labelTintColor: .white,
            navBarGradientTop: UIColor(hex: "D04050")!,
            navBarGradientBottom: UIColor(hex: "A01A28")!,
            textureAlpha: 0.20
        )
    ]

    private init() {}

    var currentTheme: iPodTheme {
        let name = SettingsStore.shared.ipodColor
        return ThemeManager.allThemes.first(where: { $0.name == name }) ?? ThemeManager.allThemes[0]
    }

    func applyTheme(named name: String) {
        SettingsStore.shared.ipodColor = name
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }
}
