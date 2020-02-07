//
//  CameraViewTouchDelegate.swift
//  Azul
//
//  Created by Luis Zul on 1/28/20.
//  Copyright © 2020 Azul. All rights reserved.
//
//  Miembro de PreviewView que se encarga de ejecutar la lógica necesaria
//  sobre CameraViewController para enfocar la imagen al hacer tap.

import Foundation
import UIKit

class CameraPreviewTouchDelegate : PreviewViewTouchDelegate {
    
    var cameraViewController : CameraViewController;
    
    init(controller: CameraViewController) {
        self.cameraViewController = controller;
    }
    
    func touch(touch: UITouch, view: UIView) {
        let touchPoint = touch.location(in: view)
        let focusPoint = CGPoint(x: touchPoint.y / UIScreen.main.bounds.size.height, y: 1.0 - (touchPoint.x / UIScreen.main.bounds.size.width))
        try? cameraViewController.videoDeviceInput.device.lockForConfiguration()
        if cameraViewController.videoDeviceInput.device.isFocusPointOfInterestSupported {
            cameraViewController.videoDeviceInput.device.focusPointOfInterest = focusPoint
            cameraViewController.videoDeviceInput.device.focusMode = .autoFocus
        }
        cameraViewController.videoDeviceInput.device.unlockForConfiguration()
    }
}
