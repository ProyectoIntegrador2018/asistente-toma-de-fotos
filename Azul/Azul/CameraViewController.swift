//
//  CameraViewController.swift
//  Azul
//
//  Created by Luis Zul on 1/14/20.
//  Copyright © 2020 Azul. All rights reserved.
//
//  Clase encargada de manejar el input de la cámara,
//  verificar que la fotografía esté enfocada antes de tomarla y
//  poder ajustar el brillo y guía de ángulo.

import UIKit
import AVFoundation
import Photos
import Lottie
import Instructions

class CameraViewController: UIViewController, CoachMarksControllerDataSource, CoachMarksControllerDelegate {
    
    
    func coachMarksController(_ coachMarksController: CoachMarksController, coachMarkViewsAt index: Int, madeFrom coachMark: CoachMark) -> (bodyView: (UIView & CoachMarkBodyView), arrowView: (UIView & CoachMarkArrowView)?) {
        let coachViews = coachMarksController.helper.makeDefaultCoachViews(withArrow: true, arrowOrientation: coachMark.arrowOrientation)
        
        coachViews.bodyView.hintLabel.text = hintLabels[index]
        coachViews.bodyView.nextLabel.text = nextLabels[index]
        
        switch index {
        case 0:
            pointOfInterest = brightnessView
            resetView.isHidden = true
        case 1:
            pointOfInterest = birghtnessDownView
            brightnessView.isHidden = true
        case 2:
            pointOfInterest = flashView
            birghtnessDownView.isHidden = true
        case 3:
            pointOfInterest = guideUpView
            flashView.isHidden = true
        case 4:
            pointOfInterest = guideDownView
            guideUpView.isHidden = true
        case 5:
            pointOfInterest = photoView
            guideDownView.isHidden = true
        case 6:
            pointOfInterest = resetView
            guideDownView.isHidden = true
        default:
            pointOfInterest = resetView
        }
        
        return (bodyView: coachViews.bodyView, arrowView: coachViews.arrowView)
    }
    
    func coachMarksController(_ coachMarksController: CoachMarksController, coachMarkAt index: Int) -> CoachMark {
        return coachMarksController.helper.makeCoachMark(for: pointOfInterest)
    }
    
    func numberOfCoachMarks(for coachMarksController: CoachMarksController) -> Int {
        return 7
    }
    
    
    
    
    // Método que maneja el output de la grabación del video.
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Enable the Record button to let the user stop recording.
        DispatchQueue.main.async {
            self.btnTakePhoto.isEnabled = true
            self.btnTakePhoto.setImage(#imageLiteral(resourceName: "CaptureStop"), for: [])
        }
    }
    
    // UI Components found in Main.storyboard
    @IBOutlet weak var templateImage: UIImageView!
    @IBOutlet weak var angleType: UILabel!
    @IBOutlet weak var lblMessage: UILabel!
    @IBOutlet weak var previewView: PreviewView!
    @IBOutlet weak var btnTakePhoto: UIButton!
    
    var pointOfInterest = UIView()
    let coachMarksController = CoachMarksController()
    
    // UIView for walkthrough
    @IBOutlet weak var resetView: UIView!
    @IBOutlet weak var brightnessView: UIView!
    @IBOutlet weak var birghtnessDownView: UIView!
    @IBOutlet weak var flashView: UIView!
    @IBOutlet weak var guideUpView: UIView!
    @IBOutlet weak var guideDownView: UIView!
    @IBOutlet weak var photoView: UIView!
    
    
    private let nextLabels = [
        0: "Reset",
        1: "Brillo",
        2: "Brillo",
        3: "Flash",
        4: "Guia Fotografica",
        5: "Guia Fotografica",
        6: "Foto"
    ]
    
    private let hintLabels = [
        0: "Restaura los valores originales de brillo y apaga el flash",
        1: "Aumenta el brillo de la camara",
        2: "Reduce el brillo de la camara",
        3: "Activa o desactiva el flash de la camara",
        4: "Cicla las diferentes guias fotograficas",
        5: "Cicla las diferentes guias fotograficas",
        6: "Captura una foto de la camara"
    ]
    
    // The capture session is responsible of routing video frames to the preview view of the app.
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "session queue")
    private var photoData: Data? = nil
    private var maskImage: UIImage? = nil
    
    var defaultISO: Float!
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private var angleIndex = 0;
    // IMPORTANT
    // Modify these values to change the templates.
    
    // Add or remove names as needed.
    private let angles: [String] = [
        "Libre",
        "Pliegue",
        "Enrollado Frente",
        "Enrollado Lado"
    ]
    // Add or remove guide images as needed.
    private let angleImages: [UIImage?] = [
        nil, #imageLiteral(resourceName: "pliegue_template"), #imageLiteral(resourceName: "frente_template"), #imageLiteral(resourceName: "lado_template")
    ]
    
    // Add or remove mask images as needed.
    private let angleMaskImages: [UIImage?] = [
       nil, #imageLiteral(resourceName: "pliegue_mask"), #imageLiteral(resourceName: "frente_mask"), #imageLiteral(resourceName: "lado_mask")
    ]
    
    private var setupResult: SessionSetupResult = .success
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    
    // Classes that give us the video and photos we need for the application
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    
    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }
    
    // MARK: View Controller Life Cycle
    
    // Loads the UI components shown in Main.storyboard
    func loadUIComponents() {
        self.angleType.text = self.angles[self.angleIndex]
        if self.angleImages[self.angleIndex] != nil {
            self.templateImage.image = self.angleImages[self.angleIndex]
        }
        self.spinner = UIActivityIndicatorView(style: .large)
        self.spinner.color = UIColor.yellow
        self.previewView.addSubview(self.spinner)
        self.previewView.addTouchDelegate(delegate: CameraPreviewTouchDelegate(controller: self))
    }
    
    func startWalkthrough() {
        self.coachMarksController.start(in: .window(over: self))
    }
    
    // Method called when the application starts and when you come back from the preview edit view.
    override func viewDidLoad() {
        super.viewDidLoad()
        previewView.session = session
        self.coachMarksController.dataSource = self
        self.coachMarksController.delegate = self
        self.coachMarksController.overlay.isUserInteractionEnabled = true
        pointOfInterest = resetView
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: break
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
            self.loadUIComponents();
        }
    }
    
    func checkFirstLaunch() -> Bool {
        let defaults = UserDefaults.standard
        if let _ = defaults.string(forKey: "firstLaunch") {
            return true
        } else {
            defaults.set(true, forKey: "firstLaunch")
            return false
        }
    }
    
      override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let defaults = UserDefaults.standard
        if checkFirstLaunch() == true && defaults.bool(forKey: "NeedWalkThrough") == false {
            let alert = UIAlertController(title: "Bienvenido!", message: "Te gustaria iniciar el tutorial?", preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction(title: "Si", style: .default, handler: { (actionAlert) in
                    self.startWalkthrough()
                    defaults.set(false, forKey: "NeedWalkThrough")
                }))
            
            alert.addAction(UIAlertAction(title: "No", style: .destructive, handler: { (actionAlert) in
                    defaults.set(true, forKey: "NeedWalkThrough")
                }))
            
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    // Class that receives a photo and determines it is blurry. Used in real-time to prevent users from taking
    // blurry photos.
    var photoBlurDelegate: PhotoBlurDelegate! = nil
    
    // Method called when the user of the app hasn't given the app permission to record or take
    // photos from the camera.
    func presentNotAuthorizedAlert() {
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
    
    // If anything goes wrong while capturing the video frames and/or photos, this method is called.
    func presentConfigurationWrongAlert() {
        let alertMsg = "Alert message when something goes wrong during capture session configuration"
        let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
        let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
        
        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                style: .cancel,
                                                handler: nil))
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    // Método que siempre se ejecuta al empezar a correr el controlador.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.photoBlurDelegate = PhotoBlurDelegate(blur: {
                    self.lblMessage.text = "La foto se encuentra borrosa. Por favor enfócala presionando la pantalla."
                }, unBlur: {
                    self.lblMessage.text = "La foto está enfocada. Puedes tomar la foto."
                })
                self.videoOutput.setSampleBufferDelegate(self.photoBlurDelegate,
                                                    queue: DispatchQueue(label: "sample buffer delegate", attributes: []))
                // Only setup observers and start the session if setup succeeded.
                self.session.startRunning()
                self.resetCamera(self)
            case .notAuthorized:
                DispatchQueue.main.async {
                    self.presentNotAuthorizedAlert();
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    self.presentConfigurationWrongAlert();
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
        self.coachMarksController.stop(immediately: true)
        super.viewWillDisappear(animated)
    }
    
    // Conectar el input frame por frame de la cámara a la aplicación.
    func addFrameCaptureInput() {
        // Add the frame capture output
        if session.canAddOutput(videoOutput)
        {
            session.addOutput(videoOutput)

            // Este formato lo ocupa PhotoBlurDelegate para calcular el enfoque. Este no es utilizado
            // al tomar la fotografía.
            var pixelFormat: FourCharCode! = nil;
            if self.videoOutput.availableVideoPixelFormatTypes
                    .contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
                pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            } else if self.videoOutput.availableVideoPixelFormatTypes
                    .contains(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
                pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            } else {
                fatalError("No available YpCbCr formats.")
            }
            videoOutput.videoSettings["PixelFormatType"] = pixelFormat;


            if let videoOutputConnection = self.videoOutput.connection(with: .video) {
                videoOutputConnection.videoOrientation = .landscapeLeft
                videoOutputConnection.isVideoMirrored = true
            }
        } else {
            print("Could not add frame output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
    }
    
    // Conectar la toma de fotografías a la aplicación.
    func addPhotoInput() {
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
    }
    
    // Buscar la cámara a conectar por la aplicación, pues varía entre versiones de iPad.
    func setVideoDeviceFromDefaultDevice() {
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
            
            self.videoDeviceInput = videoDeviceInput
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
    }
    
    // Conectar la cámara a la aplicación, la cual después conecta la toma de frames y fotografías.
    func addVideoInput() {
        self.setVideoDeviceFromDefaultDevice();
        
        defaultISO = self.videoDeviceInput.device.iso;

        
        if session.canAddInput(videoDeviceInput) {
            session.addInput(videoDeviceInput)

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
        self.addVideoInput();
        
        self.addFrameCaptureInput();
        
        self.addPhotoInput();
        
        session.commitConfiguration()
    }
    
    //Aumenta el brillo modificando el valor de ISO de la cámara
    @IBAction func brightnessUp(_ sender: Any) {
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            //Toma el ISO actual
            let currentISO = self.videoDeviceInput.device.iso
            
            //Aumenta el ISO por 100 hasta el valor máximo permitido por el dispositivo
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
    
    //Al presionar el botón si el flash está apagado se enciende y si esta encendido se apaga
    @IBAction func toggleTorch(_ sender: Any) {
        guard let device = AVCaptureDevice.default(for: AVMediaType.video) else { return }
         guard device.hasTorch else { return }

         try? device.lockForConfiguration()

         if (device.torchMode == AVCaptureDevice.TorchMode.on) {
             device.torchMode = AVCaptureDevice.TorchMode.off
         } else {
            try? device.setTorchModeOn(level: 1.0)
         }

         device.unlockForConfiguration()
        
    }
    
    //Reduce el brillo modificando el valor de ISO de la cámara
    @IBAction func brightnessDown(_ sender: Any) {
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            
            let currentISO = self.videoDeviceInput.device.iso
            
            //Reduce el ISO por 100 hasta el valor mínimo permitido por el dispositivo

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
    
    // Settings para el pre-procesamiento de la cámara.
    func createPhotoSettings() -> AVCapturePhotoSettings {
        var photoSettings = AVCapturePhotoSettings()
        
        // Capture HEIF photos when supported. Enable auto-flash and high-resolution photos.
        if  self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }
        
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
        
        return photoSettings
    }
    
    // Método que utiliza el botón para tomar la fotografía a almacenar.
    @IBAction func capturePhoto(_ sender: UIButton) {
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        
        sessionQueue.async {
            if self.photoBlurDelegate.isBlurry {
                return;
            }
            
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            let photoSettings = self.createPhotoSettings();
            
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
                if self.angleMaskImages[self.angleIndex] != nil {
                    self.maskImage = self.angleMaskImages[self.angleIndex]!
                } else {
                    self.maskImage = nil
                }
                self.photoData = imageData
                self.performSegue(withIdentifier: "editorSegue", sender: nil)
            },
               errorHandler: { photoCaptureProcessor in
                    DispatchQueue.main.async {
                    }
                }
            )
            
            // The photo output holds a weak reference to the photo capture delegate and stores it in an array to maintain a strong reference.
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
            
        }
    }

    // Método que se llama después de tomar la fotografía, llama al editor.
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        videoOutput.setSampleBufferDelegate(nil,
                                            queue: DispatchQueue(label: "sample buffer delegate", attributes: []))
        self.photoBlurDelegate.freeMemory();
        if let editorViewController = segue.destination as? EditorViewController {
            editorViewController.imageData = self.photoData
            editorViewController.maskImage = self.maskImage
        }
    }
    
    //Regresa los valores originales de brillo de la cámara a su estado original, apaga el flash
    @IBAction func resetCamera(_ sender: Any) {
        try? self.videoDeviceInput.device.lockForConfiguration()
        
        self.videoDeviceInput.device.setExposureModeCustom(duration: CMTimeMake(value: 1,timescale: 30), iso: defaultISO, completionHandler: { (time) in
        })
        
        if self.videoDeviceInput.device.isExposurePointOfInterestSupported {
            self.videoDeviceInput.device.exposurePointOfInterest = CGPoint(x: 0, y: 0)
            self.videoDeviceInput.device.exposureMode = .autoExpose
        }
        self.videoDeviceInput.device.unlockForConfiguration()
        
        guard let device = AVCaptureDevice.default(for: AVMediaType.video) else { return }
         guard device.hasTorch else { return }

         try? device.lockForConfiguration()

         if (device.torchMode == AVCaptureDevice.TorchMode.on) {
             device.torchMode = AVCaptureDevice.TorchMode.off
         }

         device.unlockForConfiguration()
        

    }
    
    // Cambia entre las guías de tipo de fotografías definidas al principio de este archivo.
    @IBAction func cycleAngleUp(_ sender: Any) {
        self.angleIndex -= 1
        if self.angleIndex < 0 {
            self.angleIndex = self.angles.count - 1
        }
        self.angleType.text = self.angles[self.angleIndex]
        self.templateImage.image = self.angleImages[self.angleIndex]
    }
    
    // Cambia entre las guías de tipo de fotografías definidas al principio de este archivo.
    @IBAction func cycleAngleDown(_ sender: Any) {
        self.angleIndex += 1
        if self.angleIndex >= self.angles.count {
            self.angleIndex = 0
        }
        self.angleType.text = self.angles[self.angleIndex]
        self.templateImage.image = self.angleImages[self.angleIndex]
    }
}
