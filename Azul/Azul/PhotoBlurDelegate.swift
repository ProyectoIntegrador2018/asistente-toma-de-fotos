//
//  PhotoBlurDelegate.swift
//  Azul
//
//  Created by Luis Zul on 1/21/20.
//  Copyright © 2020 Azul. All rights reserved.
//

import Foundation
import AVFoundation
import Accelerate

class PhotoBlurDelegate : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private var sampleBuffer: CMSampleBuffer! = nil;
    
    init(blurHandler: @escaping () -> Void,
         unBlurHandler: @escaping () -> Void) {
        self.blurHandler = blurHandler;
        self.unBlurHandler = unBlurHandler;
    }
    
    private let blurHandler: () -> Void
    private let unBlurHandler: () -> Void
    
    var isBlurry: Bool = false;
    let laplacian: [Float] =
        [-1.0, -1.0, -1.0, -1.0,  8.0, -1.0, -1.0, -1.0, -1.0];
    
    func getLaplacianStDev(data: UnsafeMutableRawPointer,
                           rowBytes: Int,
                           width: Int, height: Int) -> Float {
        var sourceBuffer = vImage_Buffer(data: data,
                                         height: vImagePixelCount(height),
                                         width: vImagePixelCount(width),
                                         rowBytes: rowBytes)
        
        var floatPixels: [Float]
        let count = width * height
        
        if sourceBuffer.rowBytes == width * MemoryLayout<Pixel_8>.stride {
            let start = sourceBuffer.data.assumingMemoryBound(to: Pixel_8.self)
            floatPixels = vDSP.integerToFloatingPoint(
                UnsafeMutableBufferPointer(start: start,
                                           count: count),
                floatingPointType: Float.self)
        } else {
            floatPixels = [Float](unsafeUninitializedCapacity: count) {
                buffer, initializedCount in
                
                var floatBuffer = vImage_Buffer(data: buffer.baseAddress,
                                                height: sourceBuffer.height,
                                                width: sourceBuffer.width,
                                                rowBytes: width * MemoryLayout<Float>.size)
                
                vImageConvert_Planar8toPlanarF(&sourceBuffer,
                                               &floatBuffer,
                                               0, 255,
                                               vImage_Flags(kvImageNoFlags))
                
                initializedCount = count
            }
        }
        
        // Convolve with Laplacian.
        vDSP.convolve(floatPixels,
                      rowCount: height,
                      columnCount: width,
                      with3x3Kernel: self.laplacian,
                      result: &floatPixels)
        
        // Calculate standard deviation.
        var mean = Float.nan
        var stdDev = Float.nan
        
        vDSP_normalize(floatPixels, 1,
                       nil, 1,
                       &mean, &stdDev,
                       vDSP_Length(count))
        
        return stdDev
    }
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(self.sampleBuffer) else {
            fatalError("Error acquiring pixel buffer.")
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer,
                                     CVPixelBufferLockFlags.readOnly)
        
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let count = width * height
        
        let lumaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        let lumaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        
        let lumaCopy = UnsafeMutableRawPointer.allocate(byteCount: count,
                                                        alignment: MemoryLayout<Pixel_8>.alignment)
        lumaCopy.copyMemory(from: lumaBaseAddress!,
                            byteCount: count)
        
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer,
                                       CVPixelBufferLockFlags.readOnly)
        
        DispatchQueue.global(qos: .utility).async {
            let stdDev = self.calculateStdDev(data: lumaCopy,
                                              rowBytes: lumaRowBytes,
                                              width: width,
                                              height: height,
                                              sequenceCount: 1,
                                              expectedCount: 1,
                                              orientation: UInt32(connection.videoOrientation.rawValue))
            print(stdDev)
            
            lumaCopy.deallocate()
        }
    }
    
    func calculateStdDev(data: UnsafeMutableRawPointer,
                  rowBytes: Int,
                  width: Int, height: Int,
                  sequenceCount: Int,
                  expectedCount: Int,
                  orientation: UInt32? ) -> Float {
        var sourceBuffer = vImage_Buffer(data: data,
                                         height: vImagePixelCount(height),
                                         width: vImagePixelCount(width),
                                         rowBytes: rowBytes)
        
        var floatPixels: [Float]
        let count = width * height
        
        if sourceBuffer.rowBytes == width * MemoryLayout<Pixel_8>.stride {
            let start = sourceBuffer.data.assumingMemoryBound(to: Pixel_8.self)
            floatPixels = vDSP.integerToFloatingPoint(
                UnsafeMutableBufferPointer(start: start,
                                           count: count),
                floatingPointType: Float.self)
        } else {
            floatPixels = [Float](unsafeUninitializedCapacity: count) {
                buffer, initializedCount in
                
                var floatBuffer = vImage_Buffer(data: buffer.baseAddress,
                                                height: sourceBuffer.height,
                                                width: sourceBuffer.width,
                                                rowBytes: width * MemoryLayout<Float>.size)
                
                vImageConvert_Planar8toPlanarF(&sourceBuffer,
                                               &floatBuffer,
                                               0, 255,
                                               vImage_Flags(kvImageNoFlags))
                
                initializedCount = count
            }
        }
        
        // Convolve with Laplacian.
        vDSP.convolve(floatPixels,
                      rowCount: height,
                      columnCount: width,
                      with3x3Kernel: laplacian,
                      result: &floatPixels)
        
        // Calculate standard deviation.
        var mean = Float.nan
        var stdDev = Float.nan
        
        vDSP_normalize(floatPixels, 1,
                       nil, 1,
                       &mean, &stdDev,
                       vDSP_Length(count))
        
        return stdDev
    }
}
