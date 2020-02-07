//
//  PhotoBlurDelegate.swift
//  Azul
//
//  Created by Luis Zul on 1/28/20.
//  Copyright © 2020 Azul. All rights reserved.
//
//  Lógica para determinar si el frame de captura del video de la cámara
//  es borroso.
//  Maneja memoria de forma explícita. Por lo tanto, seguir las recomendaciones en los
//  comentarios a continuación.

import Accelerate
import AVFoundation
import Foundation
import UIKit

class PhotoBlurDelegate : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let context = CIContext()
    
    /* NOTA:
        Los buffers necesitan ser miembros de una clase para evitar ser reciclados por
        el garbage collector de iOS.
     */
    
    /*
     The Core Graphics image representation of the source asset.
     */
    var blurCgImage: CGImage! = nil
    
    /*
     The format of the source asset.
     */
    var format: vImage_CGImageFormat! = nil
    
    /*
     The vImage buffer containing a scaled down copy of the source asset.
     */
    var sourceBuffer: vImage_Buffer! = nil
    
    var sourceImageBuffer: vImage_Buffer! = nil
    
    /*
     The 1-channel, 8-bit vImage buffer used as the operation destination.
     */
    var destinationBuffer: vImage_Buffer! = nil
    
    var floatPixels: [Float]! = nil;
    
    let laplacian: [Float] =
        [-1.0, -1.0, -1.0, -1.0,  8.0, -1.0, -1.0, -1.0, -1.0]
    
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    /* NOTA
        Siempre verificar si los buffers están llenos con == nil, de lo contario al sobreescribir
        se ocupa más memoria y/o se rompe la aplicación.
     */
    func initializeSourceBuffer(img: UIImage) {
        if sourceImageBuffer == nil {
            sourceImageBuffer = try? vImage_Buffer(cgImage: self.blurCgImage,
                                                   format: format)
        }
        
        defer {
            sourceImageBuffer.free()
            sourceImageBuffer = nil
        }
        
        if sourceBuffer == nil {
            sourceBuffer = try? vImage_Buffer(width: Int(sourceImageBuffer!.height / 3),
                                              height: Int(sourceImageBuffer!.width / 3),
                                              bitsPerPixel: format.bitsPerPixel)
        }
        
        vImageScale_ARGB8888(&(sourceImageBuffer!),
                             &sourceBuffer,
                             nil,
                             vImage_Flags(kvImageNoFlags))
    }
    
    /* NOTA
       Siempre verificar si los buffers están llenos con == nil, de lo contario al sobreescribir
       se ocupa más memoria y/o se rompe la aplicación.
    */
    func initializeDestinationBuffer(img: UIImage) {
        if destinationBuffer == nil {
            destinationBuffer = try? vImage_Buffer(width: Int(sourceBuffer.width),
                                                  height: Int(sourceBuffer.height),
                                                  bitsPerPixel: 8)
        }
    }
    
    /* Parte del pre-procesamiento para la detección de enfoque es convertir la imagen a escala de grises. */
    func convertToGrayscale() {
        // Declare the three coefficients that model the eye's sensitivity
        // to color.
        let redCoefficient: Float = 0.2126
        let greenCoefficient: Float = 0.7152
        let blueCoefficient: Float = 0.0722
        
        // Create a 1D matrix containing the three luma coefficients that
        // specify the color-to-grayscale conversion.
        let divisor: Int32 = 0x1000
        let fDivisor = Float(divisor)
        
        var coefficientsMatrix = [
            Int16(redCoefficient * fDivisor),
            Int16(greenCoefficient * fDivisor),
            Int16(blueCoefficient * fDivisor)
        ]
        
        // Use the matrix of coefficients to compute the scalar luminance by
        // returning the dot product of each RGB pixel and the coefficients
        // matrix.
        let preBias: [Int16] = [0, 0, 0, 0]
        let postBias: Int32 = 0
        
        vImageMatrixMultiply_ARGB8888ToPlanar8(&sourceBuffer,
                                               &destinationBuffer,
                                               &coefficientsMatrix,
                                               divisor,
                                               preBias,
                                               postBias,
                                               vImage_Flags(kvImageNoFlags))
    }
    
    /* NOTA
       Siempre verificar si los buffers están llenos con == nil, de lo contario al sobreescribir
       se ocupa más memoria y/o se rompe la aplicación.
    */
    func createFloatBuffer() {
        let count = Int(destinationBuffer.width) * Int(destinationBuffer.height)
        
        if destinationBuffer.rowBytes == Int(destinationBuffer.width) * MemoryLayout<Pixel_8>.stride {
            let start = destinationBuffer.data.assumingMemoryBound(to: Pixel_8.self)
            floatPixels = vDSP.integerToFloatingPoint(
                UnsafeMutableBufferPointer(start: start,
                                           count: count),
                floatingPointType: Float.self)
        } else {
            floatPixels = [Float](unsafeUninitializedCapacity: count) {
                buffer, initializedCount in
                
                var floatBuffer = vImage_Buffer(data: buffer.baseAddress,
                                                height: destinationBuffer.height,
                                                width: destinationBuffer.width,
                                                rowBytes: Int(destinationBuffer.width) * MemoryLayout<Float>.size)
                
                vImageConvert_Planar8toPlanarF(&destinationBuffer,
                                               &floatBuffer,
                                               0, 255,
                                               vImage_Flags(kvImageNoFlags))
                
                initializedCount = count
            }
        }
    }
    
    /* Pre-procesamiento de la fotografía que determina si la imagen está borrosa o no*/
    func imageLaplacianVariance(img: UIImage) -> Float {
        format = vImage_CGImageFormat(cgImage: self.blurCgImage)
        
        initializeSourceBuffer(img: img)
        
        initializeDestinationBuffer(img: img)
        
        if destinationBuffer == nil {
            return 100;
        }
        
        convertToGrayscale()
            
        createFloatBuffer()
        
        // Convolve with Laplacian.
        vDSP.convolve(floatPixels,
                      rowCount: Int(destinationBuffer.height),
                      columnCount: Int(destinationBuffer.width),
                      with3x3Kernel: self.laplacian,
                      result: &floatPixels)
        
        // Calculate standard deviation.
        var mean = Float.nan
        var stdDev = Float.nan
        
        let count = Int(destinationBuffer.width) * Int(destinationBuffer.height)
        vDSP_normalize(floatPixels, 1,
                       nil, 1,
                       &mean, &stdDev,
                       vDSP_Length(count))
        
        return stdDev;
    }
    
    var isBlurry = false;
    /* Función llamada cada vez que llega un frame de video de captura,
        transforma la imagen y obtiene su desviación estándar, la cual
        se compara para determinar si la imagen está borrosa.
 
        Si la imagen está borrosa, notifica a CameraViewController para que cambie
        el texto.
    */
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let uiImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer) else { return }
        DispatchQueue.main.async { [unowned self] in
            self.blurCgImage = uiImage.cgImage
            let stdDev = self.imageLaplacianVariance(img: uiImage)
            if stdDev <= 30 {
                self.isBlurry = true;
                self.blurHandler()
            } else {
                self.isBlurry = false;
                self.unBlurHandler()
            }
        }
    }
    
    var blurHandler: () -> ();
    var unBlurHandler: () -> ();
    
    public init(blur: @escaping () -> (),
                unBlur: @escaping () -> ()) {
        self.blurHandler = blur;
        self.unBlurHandler = unBlur;
    }
    
    /* NOTA:
        Función muy importante, pues libera la memoria cada vez que salimos de la vista principal de la aplicación.
        De lo contario, se llena la memoria hasta no poder más, y se rompe la aplicación. Siempre checar si
        están llenos los buffers con != nil, y siempre liberarlos como en este ejemplo cuando se terminen de utilizar.
        Si llamas .free() en un buffer que es nil, también da error entonces ten cuidado.
     */
    public func freeMemory() {
        if sourceBuffer != nil {
            sourceBuffer.free()
            sourceBuffer = nil
        }
        if sourceImageBuffer != nil {
            sourceImageBuffer.free()
            sourceImageBuffer = nil
        }
        if destinationBuffer != nil {
            destinationBuffer.free()
            destinationBuffer = nil
        }
    }
}
