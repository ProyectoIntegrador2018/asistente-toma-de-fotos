//
//  PreviewView.swift
//  Azul
//
//  Created by Luis Zul on 1/14/20.
//  Copyright © 2020 Azul. All rights reserved.
//
//  Vista que despliega los frames de video de la captura provenientes de la cámara.
//  su miembro touchDelegate ejecuta acciones cuando haces tap a la vista.

import UIKit
import AVFoundation

protocol PreviewViewTouchDelegate {
    func touch(touch: UITouch, view: UIView);
}

class PreviewView: UIView {
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check PreviewView.layerClass implementation.")
        }
        return layer
    }
    
    var session: AVCaptureSession? {
        get {
            return videoPreviewLayer.session
        }
        set {
            videoPreviewLayer.session = newValue
        }
    }
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var touchDelegate: PreviewViewTouchDelegate! = nil;
    
    func addTouchDelegate(delegate: PreviewViewTouchDelegate) {
        touchDelegate = delegate;
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touchDelegate != nil {
            for touch in touches {
                touchDelegate.touch(touch: touch, view: self);
            }
        }
    }
}
