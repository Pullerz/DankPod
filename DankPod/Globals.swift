//
//  Globals.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import Foundation
import UIKit

extension UIColor {
    static var gradientVeryLightGrey: UIColor {
        get {
            return UIColor(red: 250/255, green: 250/255, blue: 250/255, alpha: 1)
        }
    }
    
    static var gradientLightGrey: UIColor {
        get {
            return UIColor(red: 232/255, green: 239/255, blue: 241/255, alpha: 1)
        }
    }
    
    static var gradientDarkGrey: UIColor {
        get {
            return UIColor(red: 228/255, green: 228/255, blue: 228/255, alpha: 1)
        }
    }
    
    static var gradientLightBlue: UIColor {
        get {
            return UIColor(red: 109/255, green: 197/255, blue: 234/255, alpha: 1)
        }
    }
    
    static var gradientDarkBlue: UIColor {
        get {
            return UIColor(red: 64/255, green: 139/255, blue: 220/255, alpha: 1)
        }
    }
}


extension UIView {
    func applyGradient(colours: [UIColor]) -> Void {
        self.applyGradient(colours: colours, locations: nil)
    }
    
    func applyGradient(colours: [UIColor], locations: [NSNumber]?) -> Void {
        let gradient: CAGradientLayer = CAGradientLayer()
        gradient.frame = self.bounds
        gradient.colors = colours.map { $0.cgColor }
        gradient.locations = locations
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 0, y: 1)
        self.layer.insertSublayer(gradient, at: 0)
    }
    
    func applyGradient(colours: [UIColor], startPoint: CGPoint, endPoint: CGPoint) -> Void {
        if let sublayers = self.layer.sublayers {
            for sublayer in sublayers {
                if (sublayer as? CAGradientLayer != nil) {
                    sublayer.removeFromSuperlayer()
                }
            }
        }
        let gradient: CAGradientLayer = CAGradientLayer()
        gradient.frame = self.bounds
        gradient.colors = colours.map { $0.cgColor }
        gradient.locations = nil
        gradient.startPoint = startPoint
        gradient.endPoint = endPoint
        self.layer.insertSublayer(gradient, at: 0)
    }
    
    func removeGradient() {
        if var sublayers = self.layer.sublayers {
            for i in 0..<sublayers.count {
                let sublayer = sublayers[i]
                if sublayer as? CAGradientLayer != nil {
                    self.layer.sublayers!.remove(at: i)
                }
            }
        }
    }
}

extension FloatingPoint {
    var degreesToRadians: Self { return self * .pi / 180 }
    var radiansToDegrees: Self { return self * 180 / .pi }
}

func secondsToHoursMinutesSeconds (seconds : Int) -> (Int, Int, Int) {
  return (seconds / 3600, (seconds % 3600) / 60, (seconds % 3600) % 60)
}

func map(n: Float, start1: Float, stop1: Float, start2: Float, stop2: Float) -> Float {
  return ((n-start1)/(stop1-start1))*(stop2-start2)+start2;
};
