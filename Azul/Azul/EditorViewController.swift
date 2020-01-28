//
//  EditorViewController.swift
//  Azul
//
//  Created by German Villacorta on 1/21/20.
//  Copyright © 2020 Azul. All rights reserved.
//

import UIKit

extension CGSize {
    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        return CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}

class EditorViewController: UIViewController {

    var imageData: Data?
    var lastPoint = CGPoint.zero
    var startPoint = CGPoint.zero
    var color = UIColor.yellow
    var brushWidth: CGFloat = 5.0
    var opacity: CGFloat = 0.5
    
    var minX: CGFloat = CGFloat.greatestFiniteMagnitude
    var maxX: CGFloat = CGFloat.leastNormalMagnitude
    var minY: CGFloat = CGFloat.greatestFiniteMagnitude
    var maxY: CGFloat = CGFloat.leastNormalMagnitude
    
    var cropRectangle: CGRect?
    var isCropping = false
    
    @IBOutlet weak var currentImage: UIImageView!
    
    @IBOutlet weak var canvas: UIImageView!
    @IBOutlet weak var cropButton: UIBarButtonItem!
    @IBOutlet weak var doneCroppingButton: UIBarButtonItem!
    
    //Hola.
    override func viewDidLoad() {
        super.viewDidLoad()
        
        currentImage.image = UIImage(data: self.imageData!)

        canvas.backgroundColor = UIColor.clear
        
        doneCroppingButton.isEnabled = false
        doneCroppingButton.tintColor = UIColor.clear
    }
    

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        if (isCropping == false) {
            return
        }

        resetCanvas()
        resetCropRectangle()
        
        guard let touch = touches.first else {
          return
        }

        lastPoint = touch.location(in: canvas)
        startPoint = lastPoint
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
           
        if (isCropping == false) {
            return
        }
        
        guard let touch = touches.first else {
            return
        }

        let currentPoint = touch.location(in: view)
        drawLine(from: lastPoint, to: currentPoint)
               
        //Update mins & maxs para hacer el rectangulo.
        minX = min(minX, currentPoint.x)
        minY = min(minY, currentPoint.y)
           
        maxX = max(maxX, currentPoint.x)
        maxY = max(maxY, currentPoint.y)
           
        lastPoint = currentPoint
       }
       
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
           
        if (isCropping == false) {
            return
        }
        
        guard let touch = touches.first else {
            return
        }

        let currentPoint = touch.location(in: view)
        drawLine(from: currentPoint, to: startPoint)
        drawRect()
       }
    
    // Crop Button - Empieza a trazar lineas.
    @IBAction func beginCropping(_ sender: Any) {
        isCropping = true
        
        doneCroppingButton.isEnabled = true
        doneCroppingButton.tintColor = cropButton.tintColor
    }
    
    // Done Cropping Button - Cuando el usuario este de acuerdo con el rectangulo para recortar. La imagen se actualiza.
    @IBAction func doneCropping(_ sender: Any) {
        guard let rect = cropRectangle as CGRect? else {
            return
        }
        
        currentImage.image = snapshot(in: currentImage, rect: rect)
    }
    
    // Restart Button - Regresa la imagen a su estado natural.
    @IBAction func restoreImage(_ sender: Any) {
        currentImage.image = UIImage(data: self.imageData!)
    }
    
    // Cancel Button - Regresa a la camara.
    @IBAction func cancel(_ sender: Any) {
        self.dismiss(animated: false, completion: nil)
    }
    
    // Funcion para dibujar linea. Draw line == dibujar linea en ingles. Mundo de ingles de Disney.
    func drawLine(from fromPoint: CGPoint, to toPoint: CGPoint) {

        UIGraphicsBeginImageContext(view.frame.size)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        
        canvas.image?.draw(in: view.bounds)
        
        context.setLineCap(.square)
        context.setLineWidth(brushWidth)
        context.setStrokeColor(color.cgColor)
        
        context.move(to: fromPoint)
        context.addLine(to: toPoint)
      
        context.strokePath()
      
        canvas.image = UIGraphicsGetImageFromCurrentImageContext()
        canvas.alpha = opacity
        UIGraphicsEndImageContext()
    }
    
    // Dibuja un rectangulo con base en el trazo que hizo el usuario.
    func drawRect() {
        
        resetCanvas()
        
        UIGraphicsBeginImageContext(view.frame.size)
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        
        canvas.image?.draw(in: view.bounds)
                  
        context.setLineCap(.square)
        context.setLineDash(phase: 3.0, lengths: [10, 10])
        context.setLineWidth(brushWidth)
        context.setStrokeColor(color.cgColor)
          
        let rectangle = CGRect(x: minX - 10, y: minY - 10, width: maxX - minX + 25, height: maxY - minY + 25)
        
        self.cropRectangle = rectangle
        
        context.addRect(rectangle)
        context.strokePath()
        
        canvas.image = UIGraphicsGetImageFromCurrentImageContext()
        canvas.alpha = opacity
          UIGraphicsEndImageContext()
        
    }

    // Quita la linea que tiene.
    func resetCanvas() {
        canvas.image = nil
    }
    
    // Resetea los puntos para el rectangulo.
    func resetCropRectangle() {
        cropRectangle = nil
        
        minX = CGFloat.greatestFiniteMagnitude
        maxX = CGFloat.leastNormalMagnitude
        minY = CGFloat.greatestFiniteMagnitude
        maxY = CGFloat.leastNormalMagnitude
    }
    
    // Funcion que me piratie de internet.
    func snapshot(in imageView: UIImageView, rect: CGRect) -> UIImage {
        assert(imageView.contentMode == .scaleAspectFit)

        let image = imageView.image!

        // figure out what the scale is
        let imageRatio = imageView.bounds.width / imageView.bounds.height
        let imageViewRatio = image.size.width / image.size.height

        let scale: CGFloat
        if imageRatio > imageViewRatio {
            scale = image.size.height / imageView.bounds.height
        } else {
            scale = image.size.width / imageView.bounds.width
        }

        // convert the `rect` into coordinates within the image, itself

        let size = rect.size * scale
        let origin = CGPoint(x: image.size.width  / 2 - (imageView.bounds.midX - rect.minX) * scale,
                             y: image.size.height / 2 - (imageView.bounds.midY - rect.minY) * scale)
        let scaledRect = CGRect(origin: origin, size: size)

        // now render the image and grab the appropriate rectangle within
        // the image’s coordinate system

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false

        resetCanvas()
        resetCropRectangle()
        
        return UIGraphicsImageRenderer(bounds: scaledRect, format: format).image { _ in
            image.draw(at: .zero)
        }
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
