//
//  PhotoBlurDelegate.swift
//  Azul
//
//  Created by Luis Zul on 1/28/20.
//  Copyright © 2020 Azul. All rights reserved.
//

import Accelerate
import AVFoundation
import Foundation
import UIKit

class PhotoBlurDelegate : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let context = CIContext()
    
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
    
    func initializeDestinationBuffer(img: UIImage) {
        if destinationBuffer == nil {
            destinationBuffer = try? vImage_Buffer(width: Int(sourceBuffer.width),
                                                  height: Int(sourceBuffer.height),
                                                  bitsPerPixel: 8)
        }
    }
    
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
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let uiImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer) else { return }
        DispatchQueue.main.async { [unowned self] in
            self.blurCgImage = uiImage.cgImage
            let stdDev = self.imageLaplacianVariance(img: uiImage)
            if stdDev <= 20 {
                self.blurHandler()
            } else {
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
