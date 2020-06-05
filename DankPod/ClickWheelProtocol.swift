//
//  ClickWheelProtocol.swift
//  DankPod
//
//  Created by Alistair Pullen on 22/05/2020.
//  Copyright © 2020 Apullen Developments Ltd. All rights reserved.
//

import Foundation

protocol ClickWheelProtocol {
    func clickWheelDidRotate(rotationDirection: RotationDirection)
    func playPausePressed(pressure: ClickWheelTouchPressure)
    func nextSongPressed(pressure: ClickWheelTouchPressure)
    func previousSongPressed(pressure: ClickWheelTouchPressure)
    func menuPressed(pressure: ClickWheelTouchPressure)
    func centerPressed(pressure: ClickWheelTouchPressure)
    
}

enum ClickWheelTouchPressure {
    case NORMAL
    case FORCE
    case FORCE_ENDED
}
