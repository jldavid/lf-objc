#if os(iOS)
import UIKit
#endif
import Foundation
import AVFoundation

@objc public class AVMixer: NSObject {

    static let supportedSettingsKeys:[String] = [
        "sessionPreset",
        "orientation",
        "continuousAutofocus",
        "continuousExposure",
    ]

#if os(iOS)
    static public func getAVCaptureVideoOrientation(orientation:UIDeviceOrientation) -> AVCaptureVideoOrientation? {
        switch orientation {
        case .Portrait:
            return .Portrait
        case .PortraitUpsideDown:
            return .PortraitUpsideDown
        case .LandscapeLeft:
            return .LandscapeRight
        case .LandscapeRight:
            return .LandscapeLeft
        default:
            return nil
        }
    }
#endif

    static public func deviceWithPosition(position:AVCaptureDevicePosition) -> AVCaptureDevice? {
        for device in AVCaptureDevice.devices() {
            guard let device:AVCaptureDevice = device as? AVCaptureDevice else {
                continue
            }
            if (device.hasMediaType(AVMediaTypeVideo) && device.position == position) {
                return device
            }
        }
        return nil
    }

    static public let defaultFPS:Int32 = 30
    static public let defaultSessionPreset:String = AVCaptureSessionPresetMedium
    static public let defaultVideoSettings:[NSObject: AnyObject] = [
        kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    ]

    public var FPS:Int32 = AVMixer.defaultFPS

    public var orientation:AVCaptureVideoOrientation = .Portrait {
        didSet {
            guard orientation != oldValue else {
                return
            }
            #if os(iOS)
            if let connection:AVCaptureConnection = videoIO.view.layer.valueForKey("connection") as? AVCaptureConnection {
                if (connection.supportsVideoOrientation) {
                    connection.videoOrientation = orientation
                }
            }
            #endif
            if (_videoDataOutput != nil) {
                for connection in _videoDataOutput!.connections {
                    if let connection:AVCaptureConnection = connection as? AVCaptureConnection {
                        if (connection.supportsVideoOrientation) {
                            connection.videoOrientation = orientation
                        }
                    }
                }
            }
        }
    }

    #if os(iOS)
    public var torch:Bool = false {
        didSet {
            let torchMode:AVCaptureTorchMode = torch ? .On : .Off
            guard let device:AVCaptureDevice = currentCamera?.device
                where device.isTorchModeSupported(torchMode) && device.torchAvailable else {
                logger.warning("torchMode(\(torchMode)) is not supported")
                return
            }
            do {
                try device.lockForConfiguration()
                device.torchMode = torchMode
                device.unlockForConfiguration()
            }
            catch let error as NSError {
                logger.error("while setting torch: \(error)")
            }
        }
    }
    #endif

    public var continuousAutofocus:Bool = true {
        didSet {
            let focusMode:AVCaptureFocusMode = continuousAutofocus ? .ContinuousAutoFocus : .AutoFocus
            guard let device:AVCaptureDevice = currentCamera?.device
                where device.isFocusModeSupported(focusMode) else {
                logger.warning("focusMode(\(focusMode.rawValue)) is not supported")
                return
            }
            do {
                try device.lockForConfiguration()
                device.focusMode = focusMode
                device.unlockForConfiguration()
            }
            catch let error as NSError {
                logger.error("while locking device for autofocus: \(error)")
            }
        }
    }

    public var focusPointOfInterest: CGPoint? {
        set {
            if let device = currentCamera?.device {
                
                if device.focusPointOfInterestSupported {
                    
                    if let newValue = newValue {
                        do {
                            try device.lockForConfiguration()
                            device.focusPointOfInterest = newValue
                            device.focusMode = AVCaptureFocusMode.AutoFocus
                            device.unlockForConfiguration()
                        }
                        catch let error {
                            print("Error while locking device for focus poi: \(error)")
                        }
                    }
                }
                else {
                    print("focus poi not supported");
                }
            }
        }
        
        get {
            return self.focusPointOfInterest
        }
    }
    
    public var exposurePointOfInterest: CGPoint? {
        set {
            if let device = currentCamera?.device {

                if device.exposurePointOfInterestSupported {
                    
                    if let newValue = newValue {
                        do {
                            try device.lockForConfiguration()
                            device.exposurePointOfInterest = newValue
                            device.exposureMode = AVCaptureExposureMode.AutoExpose
                            device.unlockForConfiguration()
                        }
                        catch let error {
                            print("Error while locking device for expose poi: \(error)")
                        }
                    }
                }
                else {
                    print("expose poi not supported");
                }
            }
        }
        get {
            return self.exposurePointOfInterest
        }
    }

    public var continuousExposure:Bool = true {
        didSet {
            let exposureMode:AVCaptureExposureMode = continuousExposure ? .ContinuousAutoExposure : .AutoExpose
            guard let device:AVCaptureDevice = currentCamera?.device
                where device.isExposureModeSupported(exposureMode) else {
                logger.warning("exposureMode(\(exposureMode.rawValue)) is not supported")
                return
            }
            do {
                try device.lockForConfiguration()
                device.exposureMode = exposureMode
                device.unlockForConfiguration()
            } catch let error as NSError {
                logger.error("while locking device for autoexpose: \(error)")
            }
        }
    }

    #if os(iOS)
    public var syncOrientation:Bool = false {
        didSet {
            let center:NSNotificationCenter = NSNotificationCenter.defaultCenter()
            if (syncOrientation) {
                center.addObserver(self, selector: #selector(AVMixer.onOrientationChanged(_:)), name: UIDeviceOrientationDidChangeNotification, object: nil)
            } else {
                center.removeObserver(self, name: UIDeviceOrientationDidChangeNotification, object: nil)
            }
        }
    }
    #endif

    public var sessionPreset:String = AVMixer.defaultSessionPreset {
        didSet {
            session.beginConfiguration()
            session.sessionPreset = sessionPreset
            session.commitConfiguration()
        }
    }

    public var videoSettings:[NSObject:AnyObject] = AVMixer.defaultVideoSettings {
        didSet {
            videoDataOutput.videoSettings = videoSettings
        }
    }

    private var _session:AVCaptureSession? = nil
    var session:AVCaptureSession! {
        if (_session == nil) {
            _session = AVCaptureSession()
            _session!.sessionPreset = AVMixer.defaultSessionPreset
        }
        return _session!
    }

    private var _audioDataOutput:AVCaptureAudioDataOutput? = nil
    var audioDataOutput:AVCaptureAudioDataOutput! {
        get {
            if (_audioDataOutput == nil) {
                _audioDataOutput = AVCaptureAudioDataOutput()
            }
            return _audioDataOutput
        }
        set {
            if (_audioDataOutput == newValue) {
                return
            }
            if (_audioDataOutput != nil) {
                _audioDataOutput!.setSampleBufferDelegate(nil, queue: nil)
                session.removeOutput(_audioDataOutput!)
            }
            _audioDataOutput = newValue
        }
    }

    private var _videoDataOutput:AVCaptureVideoDataOutput? = nil
    var videoDataOutput:AVCaptureVideoDataOutput! {
        get {
            if (_videoDataOutput == nil) {
                _videoDataOutput = AVCaptureVideoDataOutput()
                _videoDataOutput!.alwaysDiscardsLateVideoFrames = true
                _videoDataOutput!.videoSettings = videoSettings
            }
            return _videoDataOutput!
        }
        set {
            if (_videoDataOutput == newValue) {
                return
            }
            if (_videoDataOutput != nil) {
                _videoDataOutput!.setSampleBufferDelegate(nil, queue: nil)
                session.removeOutput(_videoDataOutput!)
            }
            _videoDataOutput = newValue
        }
    }

    public private(set) var currentAudio:AVCaptureDeviceInput? = nil {
        didSet {
            guard oldValue != currentAudio else {
                return
            }
            if let oldValue:AVCaptureDeviceInput = oldValue {
                session.removeInput(oldValue)
            }
            if let currentAudio:AVCaptureDeviceInput = currentAudio {
                session.addInput(currentAudio)
            }
        }
    }

    public private(set) var currentCamera:AVCaptureDeviceInput? = nil {
        didSet {
            guard oldValue != currentCamera else {
                return
            }
            if let oldValue:AVCaptureDeviceInput = oldValue {
                session.removeInput(oldValue)
            }
            if let currentCamera:AVCaptureDeviceInput = currentCamera {
                session.addInput(currentCamera)
            }
        }
    }

    private(set) var currentScreen:ScreenCaptureSession? = nil {
        didSet {
            guard oldValue != currentScreen else {
                return
            }
            if let oldValue:ScreenCaptureSession = oldValue {
                oldValue.delegate = nil
                oldValue.stopRunning()
            }
            if let currentScreen:ScreenCaptureSession = currentScreen {
                currentScreen.delegate = videoIO
                currentScreen.startRunning()
            }
        }
    }

    private(set) var audioIO:AudioIOComponent = AudioIOComponent()
    private(set) var videoIO:VideoIOComponent = VideoIOComponent()

    public override init() {
        super.init()
    }

    deinit {
        #if os(iOS)
        syncOrientation = false
        #endif
    }

    public func attachAudio(audio:AVCaptureDevice?) {
        audioDataOutput = nil
        guard let audio:AVCaptureDevice = audio else {
            currentAudio = nil
            return
        }
        do {
            currentAudio = try AVCaptureDeviceInput(device: audio)
            session.addOutput(audioDataOutput)
            audioDataOutput.setSampleBufferDelegate(audioIO, queue: audioIO.lockQueue)
        } catch let error as NSError {
            logger.error("\(error)")
        }
    }

    public func attachCamera(camera:AVCaptureDevice?) {
        videoDataOutput = nil
        guard let camera:AVCaptureDevice = camera else {
            currentCamera = nil
            return
        }

        currentScreen = nil

        do {
            try camera.lockForConfiguration()
            camera.activeVideoMinFrameDuration = CMTimeMake(1, FPS)
            #if os(iOS)
            let torchMode:AVCaptureTorchMode = torch ? .On : .Off
            if (camera.isTorchModeSupported(torchMode)) {
                camera.torchMode = torchMode
            }
            #endif
            camera.unlockForConfiguration()
        } catch let error as NSError {
            logger.error("\(error)")
        }

        do {
            currentCamera = try AVCaptureDeviceInput(device: camera)
            session.addOutput(videoDataOutput)
            for connection in videoDataOutput.connections {
                guard let connection:AVCaptureConnection = connection as? AVCaptureConnection else {
                    continue
                }
                if (connection.supportsVideoOrientation) {
                    connection.videoOrientation = orientation
                }
            }
            #if os(iOS)
            switch camera.position {
            case AVCaptureDevicePosition.Front:
                videoIO.view.layer.transform = CATransform3DMakeRotation(CGFloat(M_PI), 0, 1, 0)
            case AVCaptureDevicePosition.Back:
                videoIO.view.layer.transform = CATransform3DMakeRotation(0, 0, 1, 0)
            default:
                break
            }
            #else
            switch camera.position {
            case AVCaptureDevicePosition.Front:
                videoIO.view.layer?.transform = CATransform3DMakeRotation(CGFloat(M_PI), 0, 1, 0)
            case AVCaptureDevicePosition.Back:
                videoIO.view.layer?.transform = CATransform3DMakeRotation(0, 0, 1, 0)
            default:
                break
            }
            #endif
            videoDataOutput.setSampleBufferDelegate(videoIO, queue: videoIO.lockQueue)
        } catch let error as NSError {
            logger.error("\(error)")
        }
    }

    public func attachScreen(screen:ScreenCaptureSession?) {
        guard let screen:ScreenCaptureSession = screen else {
            return
        }
        currentCamera = nil
        videoIO.encoder.setValuesForKeysWithDictionary([
            "width": screen.attributes["Width"]!,
            "height": screen.attributes["Height"]!,
        ])
        currentScreen = screen
    }

    #if os(iOS)
    func onOrientationChanged(notification:NSNotification) {
        var deviceOrientation:UIDeviceOrientation = .Unknown
        if let device:UIDevice = notification.object as? UIDevice {
            deviceOrientation = device.orientation
        }
        if let orientation:AVCaptureVideoOrientation = AVMixer.getAVCaptureVideoOrientation(deviceOrientation) {
            self.orientation = orientation
        }
    }
    #endif
}

// MARK: - Runnable
extension AVMixer: Runnable {
    var running:Bool {
        return session.running
    }

    public func startRunning() {
        #if os(iOS)
        videoIO.view.layer.setValue(session, forKey: "session")
        #endif
        session.startRunning()
        #if os(iOS)
        if let orientation:AVCaptureVideoOrientation = AVMixer.getAVCaptureVideoOrientation(UIDevice.currentDevice().orientation) {
            self.orientation = orientation
        }
        #endif
    }

    public func stopRunning() {
        session.stopRunning()
    }
}
