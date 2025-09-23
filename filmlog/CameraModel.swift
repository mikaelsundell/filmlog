// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import AVFoundation
import UIKit

enum LensType: String, CaseIterable {
    case ultraWide = "Ultra Wide"
    case wide = "Wide"

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide: return .builtInWideAngleCamera
        }
    }
}

enum CameraError: Error, LocalizedError {
    case configurationFailed(String)
    case captureFailed(String)
    case saveFailed(String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .configurationFailed(let reason): return "Camera configuration failed: \(reason)"
        case .captureFailed(let reason): return "Photo capture failed: \(reason)"
        case .saveFailed(let reason): return "Photo save failed: \(reason)"
        case .permissionDenied: return "Camera permission denied. Please enable it in Settings."
        }
    }
}

class CameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoOutputQueue = DispatchQueue(label: "camera.video.output.queue",
                                                 qos: .userInitiated)
    
    private let photoDataOutput = AVCaptureVideoDataOutput()
    private let photoOutputQueue = DispatchQueue(label: "camera.photo.output.queue",
                                                 qos: .userInitiated)
    
    private var photoCaptureCompletion: ((CGImage?) -> Void)?
    
    private let photoCounterQueue = DispatchQueue(label: "photo.counter.queue")
    private var _photoFrameCounter = 0
    private var photoFrameCounter: Int {
        get { photoCounterQueue.sync { _photoFrameCounter } }
        set { photoCounterQueue.sync { _photoFrameCounter = newValue } }
    }
    private var didCapturePhoto = false
    
    @Published var horizontalFov: CGFloat = 0
    @Published var aspectRatio: CGFloat = 0
    @Published var lensType: LensType = .wide

    public let renderer = CameraMetalRenderer()
    
    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func willEnterForeground() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    @objc private func didEnterBackground() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    func configure(completion: ((Result<Void, CameraError>) -> Void)? = nil) {
        Task {
            do {
                try await checkCameraPermission()
                configureCamera(for: lensType, completion: completion)
            } catch {
                DispatchQueue.main.async {
                    completion?(.failure(.permissionDenied))
                }
            }
        }
    }
    
    func adjustWhiteBalance(kelvin: Double) {
        sessionQueue.async {
            guard let device = self.session.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first else {
                    print("no capture device found.")
                    return
                }
            let clampedKelvin = max(kelvin, 2000)
            do {
                try device.lockForConfiguration()
                let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: Float(clampedKelvin),
                    tint: 0
                )
                let gains = device.deviceWhiteBalanceGains(for: temperatureAndTint)
                let normalizedGains = self.normalizedGains(gains, for: device)

                device.setWhiteBalanceModeLocked(with: normalizedGains, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                print("failed to set white balance: \(error.localizedDescription)")
            }
        }
    }
    
    func resetWhiteBalance() {
        sessionQueue.async {
            guard let device = self.session.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first else {
                    return
                }

            do {
                try device.lockForConfiguration()
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                } else {
                    print("white balance auto mode not supported.")
                }
                device.unlockForConfiguration()
            } catch {
                print("failed to reset white balance: \(error.localizedDescription)")
            }
        }
    }
    
    func adjustAutoExposure(ev: Float) {
        sessionQueue.async {
            guard let device = self.session.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first else { return }

            do {
                try device.lockForConfiguration()
                
                self.enableAutoFocus()
                
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
    
                let clampedBias = max(min(ev, device.maxExposureTargetBias), device.minExposureTargetBias)
                device.setExposureTargetBias(clampedBias, completionHandler: nil)
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch {
                print("failed to adjust AE exposure: \(error.localizedDescription)")
            }
        }
    }
    
    func adjustEVExposure(fstop: Double, speed: Double, shutter: Double, exposureCompensation: Double = 0.0) {
        sessionQueue.async {
            guard let device = self.session.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first else {
                    print("no device found")
                    return
                }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                self.disableAutoFocus()

                let hz = self.mainsFrequency()
                let flickerThreshold = 1.0 / Double(hz * 2)
                let preferredMinShutter = max(flickerThreshold, 1.0 / 100.0)

                let minISO = Double(device.activeFormat.minISO)
                let maxISO = Double(device.activeFormat.maxISO)
                let minShutter = device.activeFormat.minExposureDuration.seconds
                let maxShutter = device.activeFormat.maxExposureDuration.seconds
                let Ndev = Double(device.lensAperture)

                // can't figure the proper tone mapping path when using
                // custom metal pipeline, there is some sort of ootf or
                // expsure bias at play with the preview layer
                // https://developer.apple.com/forums/thread/795593
                
                let ootfCompensation = 3.0
                
                let simulatedEV = log2((fstop * fstop) / shutter) - log2(speed / 100.0)
                let EVtarget = simulatedEV - exposureCompensation + ootfCompensation
                let evFactor = pow(2.0, EVtarget)
                let numerator = 100.0 * Ndev * Ndev
                
                var finalISO = minISO
                var finalShutter = numerator / (evFactor * finalISO)
                finalShutter = min(max(finalShutter, minShutter), maxShutter)

                if finalShutter > preferredMinShutter {
                    let compensatedISO = numerator / (evFactor * preferredMinShutter)
                    if compensatedISO <= maxISO {
                        finalISO = compensatedISO
                        finalShutter = preferredMinShutter
                    } else {
                        finalISO = maxISO
                        finalShutter = numerator / (evFactor * finalISO)
                        finalShutter = min(max(finalShutter, minShutter), maxShutter)
                    }
                }

                let checkISO = numerator / (evFactor * finalShutter)
                if checkISO > maxISO {
                    finalISO = maxISO
                    finalShutter = numerator / (evFactor * finalISO)
                    finalShutter = min(max(finalShutter, minShutter), maxShutter)
                }

                if finalShutter < flickerThreshold {
                    print("flicker warning: shutter = 1/\(Int(1.0 / finalShutter))s < safe min 1/\(Int(1.0 / flickerThreshold))s")
                }

                let exposureDuration = CMTimeMakeWithSeconds(finalShutter, preferredTimescale: 1_000_000_000)
                device.isSubjectAreaChangeMonitoringEnabled = false
                
                if device.isExposureModeSupported(.custom) {
                    device.exposureMode = .custom
                }
                device.setExposureModeCustom(duration: exposureDuration, iso: Float(finalISO), completionHandler: nil)
                
            } catch {
                print("failed to adjust EV exposure error: \(error.localizedDescription)")
            }
        }
    }
    
    func enableAutoFocus() {
        sessionQueue.async {
            guard let device = self.session.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first else { return }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                device.isSubjectAreaChangeMonitoringEnabled = true

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                } else if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }

                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = true
                }

            } catch {
                print("failed to enable autofocus: \(error.localizedDescription)")
            }
        }
    }
    
    func disableAutoFocus() {
        sessionQueue.async {
            guard let device = self.session.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first else { return }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.isSubjectAreaChangeMonitoringEnabled = false

                if device.isFocusModeSupported(.locked) {
                    if device.isLockingFocusWithCustomLensPositionSupported {
                        let current = device.lensPosition
                        device.setFocusModeLocked(lensPosition: current, completionHandler: nil)
                    } else {
                        device.focusMode = .locked
                    }
                }
                if device.isSmoothAutoFocusEnabled {
                    device.isSmoothAutoFocusEnabled = false
                }
            } catch {
                print("failed to disable autofocus: \(error.localizedDescription)")
            }
        }
    }
    
    func focus(at point: CGPoint, viewSize: CGSize) {
        let focusPoint = CGPoint(x: point.y / viewSize.height, y: 1.0 - point.x / viewSize.width)
        sessionQueue.async {
            guard let device = self.session.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first else {
                print("focus error: no capture device found")
                return
            }
            
            do {
                try device.lockForConfiguration()
                
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = focusPoint
                    device.focusMode = .autoFocus
                }
                device.unlockForConfiguration()
            } catch {
                print("focus error: \(error.localizedDescription)")
            }
        }
    }
    
    func switchCamera(to lens: LensType) {
        lensType = lens
        configureCamera(for: lens)
    }

    func capturePhoto(completion: @escaping (CGImage?) -> Void) {
        photoCaptureCompletion = completion
        didCapturePhoto = false
        enablePhotoOutput(true)
    }

    private func mainsFrequency() -> Int {
        let region = Locale.current.region?.identifier ?? "SE"
        let sixtyHz: Set<String> = ["US","CA","MX","BR","KR","TW","PH","SA","LB"]
        return sixtyHz.contains(region) ? 60 : 50
    }
    
    private func enablePhotoOutput(_ enable: Bool) {
        sessionQueue.async {
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            if enable {
                self.photoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ]
                self.photoDataOutput.alwaysDiscardsLateVideoFrames = true

                if !self.session.outputs.contains(self.photoDataOutput),
                   self.session.canAddOutput(self.photoDataOutput) {
                    self.session.addOutput(self.photoDataOutput)
                    self.photoDataOutput.setSampleBufferDelegate(self, queue: self.photoOutputQueue)
                }

                if let device = self.session.inputs
                    .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                    .first {

                    var previewFps: Double = 30.0
                    let duration = device.activeVideoMinFrameDuration
                    if duration.isValid && duration.seconds > 0 {
                        previewFps = 1.0 / duration.seconds
                    }
                    var bestFormat: AVCaptureDevice.Format?
                    var maxPixels = 0

                    for format in device.formats {
                        let desc = format.formatDescription
                        let dims = CMVideoFormatDescriptionGetDimensions(desc)
                        let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)

                        guard mediaSubType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else { continue }

                        guard let range = format.videoSupportedFrameRateRanges.first else { continue }
                        let maxRate = range.maxFrameRate
                        
                        if maxRate >= previewFps {
                            let pixels = Int(dims.width) * Int(dims.height)
                            if pixels > maxPixels {
                                maxPixels = pixels
                                bestFormat = format
                            }
                        }
                    }
                    if let best = bestFormat {
                        do {
                            try device.lockForConfiguration()
                            device.activeFormat = best
                            device.unlockForConfiguration()
                        } catch {
                            print("failed to set best photo format: \(error.localizedDescription)")
                        }
                    } else {
                        print("no matching NV12 full-range format found.")
                    }
                }
            } else {
                if self.session.outputs.contains(self.photoDataOutput) {
                    self.session.removeOutput(self.photoDataOutput)
                }
            }
        }
    }

    private func configureCamera(for lens: LensType, completion: ((Result<Void, CameraError>) -> Void)? = nil) {
        print("configureCamera")
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            for output in self.session.outputs {
                self.session.removeOutput(output)
            }
            
            guard let device = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                DispatchQueue.main.async {
                    completion?(.failure(.configurationFailed("device not available for \(lens.rawValue).")))
                }
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)

            self.videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            
            self.videoDataOutput.alwaysDiscardsLateVideoFrames = true

            if self.session.canAddOutput(self.videoDataOutput) {
                self.session.addOutput(self.videoDataOutput)
                self.videoDataOutput.setSampleBufferDelegate(self.renderer, queue: self.videoOutputQueue)
            } else {
                print("cannot add videoDataOutput to session.")
                self.session.commitConfiguration()
                return
            }

            self.session.commitConfiguration()

            if !self.session.isRunning {
                self.session.startRunning()
            }

            self.updateDeviceInfo(device)

            DispatchQueue.main.async {
                completion?(.success(()))
            }
        }
    }

    private func normalizedGains(
        _ gains: AVCaptureDevice.WhiteBalanceGains,
        for device: AVCaptureDevice
    ) -> AVCaptureDevice.WhiteBalanceGains {
        var g = gains
        // gains must be >= 1.0 and <= device.maxWhiteBalanceGain
        let maxGain = device.maxWhiteBalanceGain
        g.redGain = max(1.0, min(g.redGain, maxGain))
        g.greenGain = max(1.0, min(g.greenGain, maxGain))
        g.blueGain = max(1.0, min(g.blueGain, maxGain))
        return g
    }

    private func checkCameraPermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { throw CameraError.permissionDenied }
        default:
            throw CameraError.permissionDenied
        }
    }

    private func updateDeviceInfo(_ device: AVCaptureDevice) {
        let fov = CGFloat(device.activeFormat.videoFieldOfView)
        let format = device.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let width = CGFloat(dimensions.width)
        let height = CGFloat(dimensions.height)

        guard height != 0 else { return }
        let aspectRatio = width / height

        DispatchQueue.main.async {
            self.horizontalFov = fov
            self.aspectRatio = aspectRatio
        }
    }
}

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {

    // apple explicitly mentions that auto-exposure/auto-white balance needs
    // a few frames to settle, and apps should allow "warm-up time" before using
    // frames for critical processing.
    
    private static let warmupFrameCount = 10
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        if output === videoDataOutput {
            renderer.captureOutput(output, didOutput: sampleBuffer, from: connection)
        }
        else if output === photoDataOutput {
            guard !didCapturePhoto else { return }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            photoFrameCounter += 1
            if photoFrameCounter < CameraModel.warmupFrameCount {
                return
            }
            
            didCapturePhoto = true
            guard let completion = photoCaptureCompletion else { return }
            photoCaptureCompletion = nil
            renderer.drawImage(pixelBuffer: pixelBuffer) { cgImage in
                DispatchQueue.main.async { completion(cgImage) }
                self.enablePhotoOutput(false)
                self.photoFrameCounter = 0
            }
        }
    }
}
