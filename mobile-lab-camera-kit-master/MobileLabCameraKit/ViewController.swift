//
//  ViewController.swift
//  MobileLabCameraKit
//
//  Created by Nien Lam on 2/28/18.
//  Copyright © 2018 Mobile Lab. All rights reserved.
//

import UIKit
import AVFoundation
import CoreLocation
import Vision


// Sample filters and settings.
// For more resournces/examples:
//   https://developer.apple.com/library/content/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html
//   https://developer.apple.com/library/content/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_tasks/ci_tasks.html
//   https://github.com/FlexMonkey/Filterpedia

let NoFilter = "No Filter"
let NoFilterFilter: CIFilter? = nil

let ComicEffect = "Comic Effect"
let ComicEffectFilter = CIFilter(name: "CIComicEffect")

let Crystallize = "Crystallize"
let CrystallizeFilter = CIFilter(name: "CICrystallize", parameters: ["inputRadius" : 50])

let HexagonalPixellate = "Hex Pixellate"
let HexagonalPixellateFilter = CIFilter(name: "CIHexagonalPixellate", parameters: ["inputScale" : 30])


let Filters = [
    NoFilter: NoFilterFilter,
    ComicEffect: ComicEffectFilter,
    Crystallize: CrystallizeFilter,
    HexagonalPixellate: HexagonalPixellateFilter,
    //ShadedMaterial: ShadedMaterialFilter,
]

let FilterNames = [String](Filters.keys)

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, CLLocationManagerDelegate {
    
    // Real time camera capture session.
    var captureSession = AVCaptureSession()
    
    // References to camera devices.
    var backCamera: AVCaptureDevice?
    var frontCamera: AVCaptureDevice?
    var currentCamera: AVCaptureDevice?
    

    // Context for using Core Image filters.
    let context = CIContext()
    
    // Track device orientation changes.
    var orientation: AVCaptureVideoOrientation = .portrait
    
    // Use location manager to get heading.
    let locationManager = CLLocationManager()
   
    
    // Reference to current filter.
    var currentFilter: CIFilter?
    var filterIndex = 0
    
    // Vision framework objects.
    let faceDetection = VNDetectFaceRectanglesRequest()
    let faceLandmarks = VNDetectFaceLandmarksRequest()
    let faceLandmarksDetectionRequest = VNSequenceRequestHandler()
    let faceDetectionRequest = VNSequenceRequestHandler()
    
    // Layer for custom drawing.
    let shapeLayer = CAShapeLayer()
    
    // Markers for tracking eyes.
    let leftEyeMaker = UIImageView(image: UIImage(named: "bunnyEye.png"))
    let rightEyeMaker = UIImageView(image: UIImage(named: "bunnyEye.png"))
    
    let lipsMaker = UIImageView(image: UIImage(named: "tooth.png"))
    let faceContourMaker = UIImageView(image: UIImage(named: "face.png"))
    let noseMaker = UIImageView(image: UIImage(named: "bunnyNose.png"))
    let leftEyebrowMaker = UIImageView(image: UIImage(named: "leftEyebrow.png"))
    let rightEyebrowMaker = UIImageView(image: UIImage(named: "rightEyebrow.png"))
    
    

    // Flag to track if face tracking is on/off.
    var isVisionOn = false
    
    
    // Image view for filtered image.
    @IBOutlet weak var filteredImage: UIImageView!
    
    // Label for magnetic heading value.
    @IBOutlet weak var headingLabel: UILabel!
    // Outlets to buttons.
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var filterButton: UIButton!
    @IBOutlet weak var visionButton: UIButton!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Camera device setup.
        setupDevice()
        setupInputOutput()
        
        
        // Configure location manager to get heading.
        if (CLLocationManager.headingAvailable()) {
            locationManager.headingFilter = 1
            locationManager.startUpdatingHeading()
            locationManager.delegate = self
        }
    
    
        // Add eye markers used for face tracking.
        // Set to hidden on initial setup.
        leftEyeMaker.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        leftEyeMaker.isHidden = true
        self.view.addSubview(leftEyeMaker)
        
        rightEyeMaker.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        rightEyeMaker.isHidden = true
        self.view.addSubview(rightEyeMaker)
        
        
        // Add nose markers ff
        noseMaker.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        noseMaker.isHidden = true
        self.view.addSubview(noseMaker)
        
        
        leftEyebrowMaker.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        leftEyebrowMaker.isHidden = true
        self.view.addSubview(leftEyebrowMaker)
        
        
        rightEyebrowMaker.frame = CGRect(x: 0, y: 0, width: 40, height: 20)
        rightEyebrowMaker.isHidden = true
        self.view.addSubview(rightEyebrowMaker)
        
        lipsMaker.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        lipsMaker.isHidden = true
        self.view.addSubview(lipsMaker)
        
        faceContourMaker.frame = CGRect(x: 0, y: 0, width: 150, height: 100)
        faceContourMaker.isHidden = true
        self.view.addSubview(faceContourMaker)
        
    
        
        
        // Setup shape layer for custom drawing with face tracking.
        // Need to filp coordinate system for Vision
        shapeLayer.strokeColor = UIColor.red.cgColor
        shapeLayer.lineWidth = 2.0
        shapeLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: -1))
        shapeLayer.isHidden = true
        view.layer.addSublayer(shapeLayer)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Detect device orientation changes.
        orientation = AVCaptureVideoOrientation(rawValue: UIApplication.shared.statusBarOrientation.rawValue)!
        
        // Configure shape layer dimensions.
        shapeLayer.frame = view.frame
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // Toggle front/back camera
    @IBAction func handleCameraButton(_ sender: UIButton) {
        switchCameraInput()
        
        // Set button title.
        let buttonTitle = currentCamera == frontCamera ? "Front Camera" : "Back Camera"
        cameraButton.setTitle(buttonTitle, for: .normal)
    }
    
    // Cycle through filters.
    @IBAction func handleFilterButton(_ sender: UIButton) {
        // Increment to next index.
        filterIndex = filterIndex + 1 == Filters.count ? 0 : filterIndex + 1
        
        // Set button ui name.
        let filterName = FilterNames[filterIndex]
        filterButton.setTitle(filterName, for: .normal)
        
        // Set current filter.
        currentFilter =  Filters[filterName]!
    }
    
    // Toggle face tracking.
    @IBAction func handleVisionButton(_ sender: UIButton) {
        isVisionOn = !isVisionOn
        
        let buttonTitle = isVisionOn ? "Vision On" : "Vision Off"
        visionButton.setTitle(buttonTitle, for: .normal)
        
        // Toggle visibility.
        shapeLayer.isHidden = !isVisionOn
        leftEyeMaker.isHidden = !isVisionOn
        rightEyeMaker.isHidden = !isVisionOn
        leftEyebrowMaker.isHidden = !isVisionOn
        rightEyebrowMaker.isHidden = !isVisionOn
        faceContourMaker.isHidden = !isVisionOn
        lipsMaker.isHidden = !isVisionOn
        faceContourMaker.isHidden = !isVisionOn
        noseMaker.isHidden = !isVisionOn
    }
    
    
    // CLLocationManagerDelegate method returns heading.
    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        headingLabel.text = "Bunny has: \(Int(heading.magneticHeading)/20) % chance to find carrots"
    }
    
    
    // AVCaptureVideoDataOutputSampleBufferDelegate method.
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        // Set correct device orientation.
        connection.videoOrientation = orientation
        
        // Get pixel buffer.
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        var cameraImage = CIImage(cvImageBuffer: pixelBuffer!)
        
        // Mirror camera image if using front camera.
        if currentCamera == frontCamera {
            cameraImage = cameraImage.oriented(.upMirrored)
        }
        
        // Get the filtered image if a currentFilter is set.
        var filteredImage: UIImage!
        if currentFilter == nil {
            filteredImage =  UIImage(ciImage: cameraImage)
        } else {
            self.currentFilter!.setValue(cameraImage, forKey: kCIInputImageKey)
            let cgImage = self.context.createCGImage(self.currentFilter!.outputImage!, from: cameraImage.extent)!
            filteredImage = UIImage(cgImage: cgImage)
        }
        
        self.detectFace(on: cameraImage.oriented(.upMirrored))
        
        // Set image view outlet with filtered image.
        DispatchQueue.main.async {
            self.filteredImage.image = filteredImage
        }
    }
}



///////////////////////////////////////////////////////////////
// Helper methods for vision framekwork.
extension ViewController {
    
    func detectFace(on image: CIImage) {
        try? faceDetectionRequest.perform([faceDetection], on: image)
        if let results = faceDetection.results as? [VNFaceObservation] {
            if !results.isEmpty {
                faceLandmarks.inputFaceObservations = results
                detectLandmarks(on: image)
                
                DispatchQueue.main.async {
                    self.shapeLayer.sublayers?.removeAll()
                }
            }
        }
    }
    
    func detectLandmarks(on image: CIImage) {
        try? faceLandmarksDetectionRequest.perform([faceLandmarks], on: image)
        if let landmarksResults = faceLandmarks.results as? [VNFaceObservation] {
            for observation in landmarksResults {
                DispatchQueue.main.async {
                    if let boundingBox = self.faceLandmarks.inputFaceObservations?.first?.boundingBox {
                        let faceBoundingBox = boundingBox.scaled(to: self.view.bounds.size)
                        
                        
                        let leftEye = observation.landmarks?.leftEye
                        // self.convertPointsForFace(leftEye, faceBoundingBox)
                        self.centerMarkerForFace(leftEye, faceBoundingBox, self.leftEyeMaker)
                        
                        let rightEye = observation.landmarks?.rightEye
                        // self.convertPointsForFace(rightEye, faceBoundingBox)
                        self.centerMarkerForFace(rightEye, faceBoundingBox, self.rightEyeMaker)
                    
                        
                        let leftEyebrow = observation.landmarks?.leftEyebrow
                        self.centerMarkerForFace(leftEyebrow, faceBoundingBox, self.leftEyebrowMaker)
                        
                        let rightEyebrow = observation.landmarks?.rightEyebrow
                        self.centerMarkerForFace(rightEyebrow, faceBoundingBox, self.rightEyebrowMaker)
                    
                        let lips = observation.landmarks?.innerLips
                        self.centerMarkerForFace(lips, faceBoundingBox, self.lipsMaker)
//                        let lips = observation.landmarks?.innerLips
//                        self.convertPointsForFace(lips, faceBoundingBox)
                        
//                        let outerLips = observation.landmarks?.outerLips
//                        self.convertPointsForFace(outerLips, faceBoundingBox)
                        
//                        let noseCrest = observation.landmarks?.noseCrest
//                        self.convertPointsForFace(noseCrest, faceBoundingBox)
                        
                        let faceContour = observation.landmarks?.faceContour
                        self.centerMarkerForFace(faceContour, faceBoundingBox, self.faceContourMaker)
                        
//                        let faceContour = observation.landmarks?.faceContour
//                        self.convertPointsForFace(faceContour, faceBoundingBox)
                        
//                        let leftEyebrow = observation.landmarks?.leftEyebrow
//                        self.convertPointsForFace(leftEyebrow, faceBoundingBox)
                        
//                        let rightEyebrow = observation.landmarks?.rightEyebrow
//                        self.convertPointsForFace(rightEyebrow, faceBoundingBox)
                        
                        
                        let nose = observation.landmarks?.nose
                        self.centerMarkerForFace(nose, faceBoundingBox, self.noseMaker)
                        
                    }
                }
            }
        }
    }
    
    func centerMarkerForFace(_ landmark: VNFaceLandmarkRegion2D?, _ boundingBox: CGRect, _ markerView: UIView) {
        if let points = landmark?.normalizedPoints {
            // Caculate the avg point from normalized points.
            var totalX: CGFloat = 0.0
            var totalY: CGFloat = 0.0
            for point in points {
                totalX += point.x * boundingBox.width + boundingBox.origin.x
                totalY += point.y * boundingBox.height + boundingBox.origin.y
            }
            let avgX = totalX / CGFloat(points.count)
            let avgY = totalY / CGFloat(points.count)
            
            // Position marker view.
            markerView.center = CGPoint(x: self.view.bounds.width - avgX , y: self.view.bounds.height - avgY)
        }
    }
    
    func convertPointsForFace(_ landmark: VNFaceLandmarkRegion2D?, _ boundingBox: CGRect) {
        if let points = landmark?.normalizedPoints {
            let faceLandmarkPoints = points.map { (point: CGPoint) -> (x: CGFloat, y: CGFloat) in
                let pointX = point.x * boundingBox.width + boundingBox.origin.x
                let pointY = point.y * boundingBox.height + boundingBox.origin.y
                
                return (x: pointX, y: pointY)
            }
            
            DispatchQueue.main.async {
                self.draw(points: faceLandmarkPoints)
            }
        }
    }
    
    func draw(points: [(x: CGFloat, y: CGFloat)]) {
        let newLayer = CAShapeLayer()
        newLayer.strokeColor = UIColor.red.cgColor
        // doesn‘ t work
        newLayer.fillColor = UIColor.yellow.cgColor
        newLayer.lineWidth = 2.0
        
        let path = UIBezierPath()
        path.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for i in 0..<points.count - 1 {
            let point = CGPoint(x: points[i].x, y: points[i].y)
            path.addLine(to: point)
            path.move(to: point)
        }
        path.addLine(to: CGPoint(x: points[0].x, y: points[0].y))
        newLayer.path = path.cgPath
        
        shapeLayer.addSublayer(newLayer)
    }
}

extension CGRect {
    func scaled(to size: CGSize) -> CGRect {
        return CGRect(
            x: self.origin.x * size.width,
            y: self.origin.y * size.height,
            width: self.size.width * size.width,
            height: self.size.height * size.height
        )
    }
}



///////////////////////////////////////////////////////////////
// Helper methods to setup camera capture view.
extension ViewController {
    
    func setupDevice() {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                                                                      mediaType: AVMediaType.video, position: AVCaptureDevice.Position.unspecified)
        let devices = deviceDiscoverySession.devices
        
        for device in devices {
            if device.position == AVCaptureDevice.Position.back {
                backCamera = device
            }
            else if device.position == AVCaptureDevice.Position.front {
                frontCamera = device
            }
        }
        
        currentCamera = backCamera
    }
    
    func setupInputOutput() {
        do {
            setupCorrectFramerate(currentCamera: currentCamera!)
            
            let captureDeviceInput = try AVCaptureDeviceInput(device: currentCamera!)
            captureSession.sessionPreset = AVCaptureSession.Preset.hd1280x720
            
            if captureSession.canAddInput(captureDeviceInput) {
                captureSession.addInput(captureDeviceInput)
            }
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer delegate", attributes: []))
            
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            captureSession.startRunning()
        } catch {
            print(error)
        }
    }
    
    func setupCorrectFramerate(currentCamera: AVCaptureDevice) {
        for vFormat in currentCamera.formats {
            var ranges = vFormat.videoSupportedFrameRateRanges as [AVFrameRateRange]
            let frameRates = ranges[0]
            do {
                //set to 240fps - available types are: 30, 60, 120 and 240 and custom
                // lower framerates cause major stuttering
                if frameRates.maxFrameRate == 180 {
                    try currentCamera.lockForConfiguration()
                    currentCamera.activeFormat = vFormat as AVCaptureDevice.Format
                    //for custom framerate set min max activeVideoFrameDuration to whatever you like, e.g. 1 and 180
                    currentCamera.activeVideoMinFrameDuration = frameRates.minFrameDuration
                    currentCamera.activeVideoMaxFrameDuration = frameRates.maxFrameDuration
                }
            }
            catch {
                print("Could not set active format")
                print(error)
            }
        }
    }
    
    func cameraWithPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                                                         mediaType: AVMediaType.video,
                                                         position: .unspecified) as AVCaptureDevice.DiscoverySession
        for device in discovery.devices as [AVCaptureDevice] {
            if device.position == position {
                return device
            }
        }
        
        return nil
    }
    
    func switchCameraInput() {
        self.captureSession.beginConfiguration()
        
        var existingConnection:AVCaptureDeviceInput!
        
        for connection in self.captureSession.inputs {
            let input = connection as! AVCaptureDeviceInput
            if input.device.hasMediaType(AVMediaType.video) {
                existingConnection = input
            }
            
        }
        
        self.captureSession.removeInput(existingConnection)
        
        var newCamera:AVCaptureDevice!
        if let oldCamera = existingConnection {
            newCamera = oldCamera.device.position == .back ? frontCamera : backCamera
            currentCamera = newCamera
        }
        
        var newInput: AVCaptureDeviceInput!
        
        do {
            newInput = try AVCaptureDeviceInput(device: newCamera)
            self.captureSession.addInput(newInput)
        } catch {
            print(error)
        }
        
        self.captureSession.commitConfiguration()
    }
}
