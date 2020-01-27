//
//  CameraViewController.swift
//  Azul
//
//  Created by Luis Zul on 1/14/20.
//  Copyright © 2020 Azul. All rights reserved.
//

import Accelerate
import UIKit
import AVFoundation
import Photos

class CameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate  {
    
    private let context = CIContext()
    
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    /*
     The Core Graphics image representation of the source asset.
     */
    var blurCgImage: CGImage! = nil;
    
    /*
     The format of the source asset.
     */
    var format: vImage_CGImageFormat! = nil;
    
    /*
     The vImage buffer containing a scaled down copy of the source asset.
     */
    var sourceBuffer: vImage_Buffer! = nil;
    
    var sourceImageBuffer: vImage_Buffer! = nil;
    
    /*
     The 1-channel, 8-bit vImage buffer used as the operation destination.
     */
    var destinationBuffer: vImage_Buffer! = nil;
    
    let laplacian: [Float] =
    [-1.0, -1.0, -1.0, -1.0,  8.0, -1.0, -1.0, -1.0, -1.0];
    
    func imageLaplacianVariance(img: UIImage) -> Float {
        format = vImage_CGImageFormat(cgImage: self.blurCgImage)
        
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
        
        if destinationBuffer == nil {
            destinationBuffer = try? vImage_Buffer(width: Int(sourceBuffer.width),
                                                  height: Int(sourceBuffer.height),
                                                  bitsPerPixel: 8)
        }
        
        if destinationBuffer == nil {
            return 100;
        }
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
        
        var floatPixels: [Float]
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
        
        // Convolve with Laplacian.
        vDSP.convolve(floatPixels,
                      rowCount: Int(destinationBuffer.height),
                      columnCount: Int(destinationBuffer.width),
                      with3x3Kernel: self.laplacian,
                      result: &floatPixels)
        
        // Calculate standard deviation.
        var mean = Float.nan
        var stdDev = Float.nan
        
        vDSP_normalize(floatPixels, 1,
                       nil, 1,
                       &mean, &stdDev,
                       vDSP_Length(count))
        
        return stdDev;
    }
    
    @IBOutlet weak var varianceLabel: UILabel!
    @IBOutlet weak var previewImageView: UIImageView!
    private var isBlurry = false;
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let uiImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer) else { return }
        DispatchQueue.main.async { [unowned self] in
            self.blurCgImage = uiImage.cgImage
            let stdDev = self.imageLaplacianVariance(img: uiImage)
            self.varianceLabel.text = String(stdDev)
            if stdDev <= 30 {
                if self.lblMessage.text != "La imagen se encuentra borrosa. Ajústala antes de tomarla." {
                    self.lblMessage.text = "La imagen se encuentra borrosa. Ajústala antes de tomarla.";
                    self.isBlurry = true
                }
            } else {
                if self.lblMessage.text != "La imagen está enfocada. Ya puedes tomar la fotografía." {
                   self.lblMessage.text = "La imagen está enfocada. Ya puedes tomar la fotografía."
                    self.isBlurry = false
                }
            }
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Enable the Record button to let the user stop recording.
        DispatchQueue.main.async {
            self.btnTakePhoto.isEnabled = true
            self.btnTakePhoto.setImage(#imageLiteral(resourceName: "CaptureStop"), for: [])
        }
    }
    
    @IBOutlet weak var angleType: UILabel!
    @IBOutlet weak var lblMessage: UILabel!
    @IBOutlet weak var btnTakePhoto: UIButton!
    @IBOutlet weak var previewView: PreviewView!
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "session queue")
    private var photoData: Data? = nil
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private var angleIndex = 0;
    private let angles: [String] = [
        "Pliegue",
        "Enrollado Frente",
        "Enrollado Lado",
        "Libre"
    ]
    
    private var setupResult: SessionSetupResult = .success
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    
    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }
    
    // MARK: View Controller Life Cycle
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        previewView.session = session
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: // The user has previously granted access to the camera.
                break
            
            case .notDetermined: // The user has not yet been asked for camera access.
                sessionQueue.suspend()
                AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                    if !granted {
                        self.setupResult = .notAuthorized
                    }
                    self.sessionQueue.resume()
                })
            default:
                 setupResult = .notAuthorized
            return
        }
        
        sessionQueue.async {
            self.configureSession()
        }
        DispatchQueue.main.async {
            self.angleType.text = self.angles[self.angleIndex]
            self.spinner = UIActivityIndicatorView(style: .large)
            self.spinner.color = UIColor.yellow
            self.previewView.addSubview(self.spinner)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.videoOutput.setSampleBufferDelegate(self,
                                                    queue: DispatchQueue(label: "sample buffer delegate", attributes: []))
                // Only setup observers and start the session if setup succeeded.
                self.session.startRunning()
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "AVCam doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                          options: [:],
                                                                                          completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    // MARK: Session Management

    func configureSession() {
        
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        /*
         Do not create an AVCaptureMovieFileOutput when setting up the session because
         Live Photo is not supported when AVCaptureMovieFileOutput is added to the session.
         */
        session.sessionPreset = .photo
        
        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            // Choose the back dual camera, if available, otherwise default to a wide angle camera.
            
            if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                // If a rear dual camera is not available, default to the rear wide angle camera.
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                // If the rear wide angle camera isn't available, default to the front wide angle camera.
                defaultVideoDevice = frontCameraDevice
            }
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    /*
                     Dispatch video streaming to the main queue because AVCaptureVideoPreviewLayer is the backing layer for PreviewView.
                     You can manipulate UIView only on the main thread.
                     Note: As an exception to the above rule, it's not necessary to serialize video orientation changes
                     on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                     
                     Use the window scene's orientation as the initial video orientation. Subsequent orientation changes are
                     handled by CameraViewController.viewWillTransition(to:with:).
                     */
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if self.windowOrientation != .unknown {
                        if let videoOrientation = AVCaptureVideoOrientation(rawValue: self.windowOrientation.rawValue) {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    
                    self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
                }
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add the frame capture output
        if session.canAddOutput(videoOutput)
        {
            session.addOutput(videoOutput)
            
            let pixelFormat: FourCharCode = {
                if self.videoOutput.availableVideoPixelFormatTypes
                    .contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
                    return kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                } else if self.videoOutput.availableVideoPixelFormatTypes
                    .contains(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
                    return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                } else {
                    fatalError("No available YpCbCr formats.")
                }
            }()
            videoOutput.videoSettings["PixelFormatType"] = pixelFormat;
            
            
            if let videoOutputConnection = self.videoOutput.connection(with: .video) {
                videoOutputConnection.videoOrientation = .portrait
                videoOutputConnection.isVideoMirrored = true
            }
        } else {
            print("Could not add frame output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add the photo output.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
            photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
            photoOutput.enabledSemanticSegmentationMatteTypes = photoOutput.availableSemanticSegmentationMatteTypes
            photoOutput.maxPhotoQualityPrioritization = .quality
            depthDataDeliveryMode = photoOutput.isDepthDataDeliverySupported ? .on : .off
            photoQualityPrioritizationMode = .balanced
            
        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    @IBAction func brightnessUp(_ sender: Any) {
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            
            let currentISO = self.videoDeviceInput.device.iso
                        
            if (currentISO + 100) < self.videoDeviceInput.device.activeFormat.maxISO {
                self.videoDeviceInput.device.setExposureModeCustom(duration: CMTimeMake(value: 1,timescale: 30), iso: currentISO + 100, completionHandler: { (time) in
                })
            }

            self.videoDeviceInput.device.unlockForConfiguration()
        } catch {
            debugPrint(error)
        }
    }
    
    func performConfigurationOnCurrentCameraDevice(block: @escaping ((_ currentDevice:AVCaptureDevice) -> Void)) {
        let currentDevice = self.videoDeviceInput.device
        performConfiguration { () -> Void in
            do {
                try currentDevice.lockForConfiguration()
                block(currentDevice)
                currentDevice.unlockForConfiguration()
            }
            catch {}
        }
    }
    
    func performConfiguration(block: @escaping (() -> Void)) {
        sessionQueue.async() { () -> Void in
            block()
        }
    }
    
    
    @IBAction func contrastUp(_ sender: Any) {
        _ = self.videoDeviceInput.device
        
        
        performConfigurationOnCurrentCameraDevice { (currentDevice) -> Void in
            if currentDevice.isWhiteBalanceModeSupported(.locked) {
                let maxBalanceGain = currentDevice.maxWhiteBalanceGain
                let currentGains = currentDevice.deviceWhiteBalanceGains

                let currentTemperature = currentDevice.temperatureAndTintValues(for: currentGains).temperature
                let temperatureAndTintValues = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: currentTemperature, tint: 100)
                
                let chromaticity = AVCaptureDevice.WhiteBalanceGains(redGain: maxBalanceGain, greenGain: maxBalanceGain, blueGain: maxBalanceGain)
                
            self.videoDeviceInput.device.setExposureModeCustom(duration: CMTimeMake(value: 1,timescale: 30), iso: 50, completionHandler: { (time) in
            })
                
                currentDevice.chromaticityValues(for: chromaticity)
                
                let deviceGains = currentDevice.deviceWhiteBalanceGains(for: temperatureAndTintValues)

                currentDevice.setWhiteBalanceModeLocked(with: deviceGains) {
                    (timestamp:CMTime) -> Void in
                }
            }
        }
    }
    
    @IBAction func toggleTorch(_ sender: Any) {
        guard let device = AVCaptureDevice.default(for: AVMediaType.video) else { return }
         guard device.hasTorch else { return }

         do {
             try device.lockForConfiguration()

             if (device.torchMode == AVCaptureDevice.TorchMode.on) {
                 device.torchMode = AVCaptureDevice.TorchMode.off
             } else {
                 do {
                     try device.setTorchModeOn(level: 1.0)
                 } catch {
                     print(error)
                 }
             }

             device.unlockForConfiguration()
         } catch {
             print(error)
         }
        
    }
    
    @IBAction func brightnessDown(_ sender: Any) {
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            
            let currentISO = self.videoDeviceInput.device.iso
            
            if (currentISO - 100) > self.videoDeviceInput.device.activeFormat.minISO {
                self.videoDeviceInput.device.setExposureModeCustom(duration: CMTimeMake(value: 1,timescale: 30), iso: currentISO - 100, completionHandler: { (time) in
                })
            }
            self.videoDeviceInput.device.unlockForConfiguration()
        } catch {
            debugPrint(error)
        }
    }
    
    func setupCaptureSession() {
        sessionQueue.async {
            self.session.sessionPreset = AVCaptureSession.Preset.photo
            self.configureSession();
        }
    }
    
    // MARK: Capturing Photos

    private enum DepthDataDeliveryMode {
        case on
        case off
    }
    
    private var depthDataDeliveryMode: DepthDataDeliveryMode = .off
    
    private var photoQualityPrioritizationMode: AVCapturePhotoOutput.QualityPrioritization = .balanced
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    private var spinner: UIActivityIndicatorView!
    
    @IBAction func capturePhoto(_ sender: UIButton) {
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        
        sessionQueue.async {
            if self.isBlurry {
                return;
            }
            
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            
            let pixelFormat: FourCharCode = {
                if self.photoOutput.availablePhotoPixelFormatTypes
                    .contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
                    return kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                } else if self.photoOutput.availablePhotoPixelFormatTypes
                    .contains(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
                    return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                } else {
                    fatalError("No available YpCbCr formats.")
                }
            }()
            
            let photoSettings = AVCapturePhotoSettings(
                rawPixelFormatType: 0,
                processedFormat: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat])
            
            // Capture HEIF photos when supported. Enable auto-flash and high-resolution photos.
//            if  self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
//                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
//            }
            
            if self.videoDeviceInput.device.isFlashAvailable {
                photoSettings.flashMode = .auto
            }
            
            photoSettings.isHighResolutionPhotoEnabled = true
            if !photoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
            }
            
            photoSettings.isDepthDataDeliveryEnabled = (self.depthDataDeliveryMode == .on
            && self.photoOutput.isDepthDataDeliveryEnabled)
            
            photoSettings.photoQualityPrioritization = self.photoQualityPrioritizationMode
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                // Flash the screen to signal that AVCam took a photo.
                DispatchQueue.main.async {
                    self.previewView.videoPreviewLayer.opacity = 0
                    UIView.animate(withDuration: 0.25) {
                        self.previewView.videoPreviewLayer.opacity = 1
                    }
                }
            }, livePhotoCaptureHandler: { capturing in
                self.sessionQueue.async {
                }
            }, completionHandler: { photoCaptureProcessor in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
            }, photoProcessingHandler: { animate in
                // Animates a spinner while photo is processing
                DispatchQueue.main.async {
                    if animate {
                        self.spinner.hidesWhenStopped = true
                        self.spinner.center = CGPoint(x: self.previewView.frame.size.width / 2.0, y: self.previewView.frame.size.height / 2.0)
                        self.spinner.startAnimating()
                    } else {
                        self.spinner.stopAnimating()
                    }
                }
            }, presentEditorViewController: { imageData in
                self.photoData = imageData
                self.performSegue(withIdentifier: "editorSegue", sender: nil)
            },
               errorHandler: { photoCaptureProcessor in
                    DispatchQueue.main.async {
                        self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                        let alertController = UIAlertController(title: "Azul", message:
                            "La fotografía no tiene el enfoque correcto.\n Intenta de nuevo.", preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: "Cerrar", style: .default))

                        self.present(alertController, animated: true, completion: nil)
                    }
                }
            )
            
            // The photo output holds a weak reference to the photo capture delegate and stores it in an array to maintain a strong reference.
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
            
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        videoOutput.setSampleBufferDelegate(nil,
                                            queue: DispatchQueue(label: "sample buffer delegate", attributes: []))
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
        if let editorViewController = segue.destination as? EditorViewController {
            editorViewController.imageData = self.photoData
        }
    }
    
    @IBAction func cycleAngleUp(_ sender: Any) {
        self.angleIndex -= 1
        if self.angleIndex < 0 {
            self.angleIndex = self.angles.count - 1
        }
        self.angleType.text = self.angles[self.angleIndex]
    }
    
    @IBAction func cycleAngleDown(_ sender: Any) {
        self.angleIndex += 1
        if self.angleIndex >= self.angles.count {
            self.angleIndex = 0
        }
        self.angleType.text = self.angles[self.angleIndex]
    }
    
    
}
