//
//  ForceTouchGestureRecogniser.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import Foundation
import UIKit.UIGestureRecognizerSubclass


class ForceTouchTapGestureRecogniser: UITapGestureRecognizer {
    private let threshold: CGFloat = 0.9
    public var isForceTouch: Bool = false
    
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        isForceTouch = false
        if let touch = touches.first {
            handleTouch(touch)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        if let touch = touches.first {
            handleTouch(touch)
        }
    }
    
    
    private func handleTouch(_ touch: UITouch) {
        
        guard touch.force != 0 && touch.maximumPossibleForce != 0 else { return }

        if touch.force / touch.maximumPossibleForce >= threshold {
            isForceTouch = true
            state = UIGestureRecognizer.State.ended
        }
    }
}
