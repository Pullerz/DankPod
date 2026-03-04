//
//  ClickWheelProtocol.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import UIKit

struct ClickWheelRotationEvent {
    let deltaRadians: CGFloat
    let angularVelocity: CGFloat
    let direction: RotationDirection
    let state: UIGestureRecognizer.State
}

protocol ClickWheelProtocol {
    func clickWheelDidRotate(rotationDirection: RotationDirection)
    func playPausePressed(pressure: ClickWheelTouchPressure)
    func nextSongPressed(pressure: ClickWheelTouchPressure)
    func previousSongPressed(pressure: ClickWheelTouchPressure)
    func menuPressed(pressure: ClickWheelTouchPressure)
    func centerPressed(pressure: ClickWheelTouchPressure)
    
    // Declared in protocol for dynamic dispatch; defaults provided below
    var prefersContinuousWheelInput: Bool { get }
    func clickWheelDidRotateContinuously(event: ClickWheelRotationEvent)
}

extension ClickWheelProtocol {
    var prefersContinuousWheelInput: Bool { false }
    func clickWheelDidRotateContinuously(event: ClickWheelRotationEvent) {}
}

enum ClickWheelTouchPressure {
    case NORMAL
    case FORCE
    case FORCE_ENDED
}
