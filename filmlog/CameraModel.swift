// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import ARKit
import AVFoundation
import MetalKit
import UIKit

enum ARState {
    case idle
    case scanning
    case refining
    case ready
    case placed
}

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
        case .captureFailed(let reason): return "Offscreen capture failed: \(reason)"
        case .saveFailed(let reason): return "Offscreen save failed: \(reason)"
        case .permissionDenied: return "Camera permission denied. Please enable it in Settings."
        }
    }
}

private struct CameraFormat {
    let format: AVCaptureDevice.Format
    let dimensions: CMVideoDimensions
    let pixelCount: Int
    let fov: Float
    let minFps: Double
    let maxFps: Double
    let isHDR: Bool
}

class CameraModel: NSObject, ObservableObject {
    @Published var viewFov: CGFloat = 50
    @Published var offscreenFov: CGFloat = 50
    @Published var offscreenAspectRatio: CGFloat = 4.0 / 3.0
    @Published var lensType: LensType = .wide
    @Published var arState: ARState = .idle
    @Published var planeWorldTransform: simd_float4x4?
    @Published var viewSize: CGSize = .zero
    @Published var captureAR = false

    let captureSession = AVCaptureSession()
    let sessionQueue = DispatchQueue(label: "camera.session.queue")

    private var cameraFormats: [LensType: [CameraFormat]] = [:]
    private var viewFormat: CameraFormat?
    private var offscreenFormat: CameraFormat?
    private var restoreFormat: AVCaptureDevice.Format?
    
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoOutputQueue = DispatchQueue(label: "camera.video.output.queue",
                                                 qos: .userInitiated)
    
    private let offscreenDataOutput = AVCaptureVideoDataOutput()
    private let offscreenOutputQueue = DispatchQueue(label: "camera.offscreen.output.queue",
                                                 qos: .userInitiated)
    
    private var drawOffscreenCompletion: ((CGImage?) -> Void)?
    private let offscreenCounterQueue = DispatchQueue(label: "offscreen.counter.queue")
    private var _offscreenFrameCounter = 0
    private var offscreenFrameCounter: Int {
        get { offscreenCounterQueue.sync { _offscreenFrameCounter } }
        set { offscreenCounterQueue.sync { _offscreenFrameCounter = newValue } }
    }
    private var didDrawOffscreen = false
    private var resumeARDrawOffscreen = false
    
    private(set) var renderer: CameraRenderer?
    
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
    
    deinit {
        if let ar = arSession {
            ar.pause()
            arSession = nil
        }
    }
    
    func attach(to view: MTKView) {
        guard let device = view.device else {
            fatalError("MTKView has no metal device")
        }
        if let renderer {
            renderer.attach(to: view)
            self.renderer = renderer
            return
        }

        let renderer = CameraRenderer(device: device)
        renderer.attach(to: view)
        self.renderer = renderer
    }
    
    @objc private func willEnterForeground() {
        sessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    @objc private func didEnterBackground() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }
    
    func stop() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
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
            guard let device = self.captureSession.inputs
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
            guard let device = self.captureSession.inputs
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
            guard let device = self.captureSession.inputs
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
            guard let device = self.captureSession.inputs
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
            guard let device = self.captureSession.inputs
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
            guard let device = self.captureSession.inputs
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
            guard let device = self.captureSession.inputs
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
    
    func switchLUT(_ type: LUTType) {
        guard let renderer else { return }
        renderer.setLutType(type)
    }
    
    func pauseAR() {
        sessionQueue.async {
            DispatchQueue.main.async {
                self.captureAR = false
            }
        }
    }
    
    func resumeAR() {
        sessionQueue.async {
            guard let arSession = self.arSession else { return }

            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            config.environmentTexturing = .automatic
            config.isLightEstimationEnabled = true

            arSession.run(config, options: [])
            DispatchQueue.main.async {
                self.captureAR = true
            }
        }
    }
    
    func captureOffscreen(completion: @escaping (CGImage?) -> Void) {
        resumeARDrawOffscreen = (arSession != nil)
        pauseRendering()
        if resumeARDrawOffscreen {
            pauseAR()
        }
        sessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
        drawOffscreenCompletion = completion
        didDrawOffscreen = false
        enableOffscreenOutput(true)
    }
    
    private func pauseRendering() {
        guard let renderer else { return }
        renderer.pause()
    }

    private func resumeRendering() {
        guard let renderer else { return }
        renderer.resume()
    }
    
    private func mainsFrequency() -> Int {
        let region = Locale.current.region?.identifier ?? "SE"
        let sixtyHz: Set<String> = ["US","CA","MX","BR","KR","TW","PH","SA","LB"]
        return sixtyHz.contains(region) ? 60 : 50
    }
    
    private func enableOffscreenOutput(_ enable: Bool) {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            defer { self.captureSession.commitConfiguration() }

            if enable {
                guard let offscreenFormat = self.offscreenFormat else {
                    print("offscreenFormat not set")
                    return
                }
                self.offscreenDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ]
                self.offscreenDataOutput.alwaysDiscardsLateVideoFrames = true

                if !self.captureSession.outputs.contains(self.offscreenDataOutput),
                   self.captureSession.canAddOutput(self.offscreenDataOutput) {

                    self.captureSession.addOutput(self.offscreenDataOutput)
                    self.offscreenDataOutput.setSampleBufferDelegate(
                        self,
                        queue: self.offscreenOutputQueue
                    )
                }
                guard let device = self.captureSession.inputs
                    .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                    .first else {
                        print("no capture device found")
                        return
                    }

                do {
                    try device.lockForConfiguration()
                    if self.restoreFormat == nil {
                        self.restoreFormat = device.activeFormat
                    }
                    device.activeFormat = offscreenFormat.format
                    device.unlockForConfiguration()
                } catch {
                    print("failed to apply offscreen format: \(error.localizedDescription)")
                    return
                }

                DispatchQueue.main.async {
                    self.updateDeviceOffscreenInfo(device)
                }
            } else {
                if self.captureSession.outputs.contains(self.offscreenDataOutput) {
                    self.captureSession.removeOutput(self.offscreenDataOutput)
                }
            }
        }
    }

    private func configureCamera(
        for lens: LensType,
        completion: ((Result<Void, CameraError>) -> Void)? = nil
    ) {
        sessionQueue.async {
            self.pauseRendering()
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            self.captureSession.inputs.forEach { self.captureSession.removeInput($0) }
            self.captureSession.outputs.forEach { self.captureSession.removeOutput($0) }

            guard let device = AVCaptureDevice.default(
                lens.deviceType,
                for: .video,
                position: .back
            ),
            let input = try? AVCaptureDeviceInput(device: device),
            self.captureSession.canAddInput(input) else {

                self.captureSession.commitConfiguration()
                DispatchQueue.main.async {
                    completion?(
                        .failure(.configurationFailed(
                            "device not available for \(lens.rawValue)"
                        ))
                    )
                }
                return
            }

            self.captureSession.addInput(input)
            self.cacheCameraFormats(for: device, lens: lens)
            self.selectFormats(for: lens)

            guard let viewFormat = self.viewFormat,
                  let offscreenFormat = self.offscreenFormat else {

                self.captureSession.commitConfiguration()
                DispatchQueue.main.async {
                    completion?(
                        .failure(.configurationFailed(
                            "failed to determine camera formats"
                        ))
                    )
                }
                return
            }
            do {
                try device.lockForConfiguration()
                device.activeFormat = viewFormat.format
                device.unlockForConfiguration()
            } catch {
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async {
                    completion?(
                        .failure(.configurationFailed(
                            "failed to apply view format"
                        ))
                    )
                }
                return
            }
            self.videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            self.videoDataOutput.alwaysDiscardsLateVideoFrames = true

            if self.captureSession.canAddOutput(self.videoDataOutput) {
                self.captureSession.addOutput(self.videoDataOutput)
                self.videoDataOutput.setSampleBufferDelegate(
                    self.renderer,
                    queue: self.videoOutputQueue
                )
            } else {
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async {
                    completion?(
                        .failure(.configurationFailed(
                            "cannot add video output"
                        ))
                    )
                }
                return
            }
            self.captureSession.commitConfiguration()
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
            DispatchQueue.main.async {
                self.viewFov = CGFloat(viewFormat.fov)
                self.offscreenFov = CGFloat(offscreenFormat.fov)
                self.offscreenAspectRatio =
                    CGFloat(offscreenFormat.dimensions.width) /
                    CGFloat(offscreenFormat.dimensions.height)
                completion?(.success(()))
                self.resumeRendering()
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
    
    private func cacheCameraFormats(
        for device: AVCaptureDevice,
        lens: LensType
    ) {
        var formats: [CameraFormat] = []
        for format in device.formats {
            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let subtype = CMFormatDescriptionGetMediaSubType(desc)

            // require NV12 full-range
            guard subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else {
                continue
            }

            let ranges = format.videoSupportedFrameRateRanges
            let minFps = ranges.map { $0.minFrameRate }.min() ?? 0
            let maxFps = ranges.map { $0.maxFrameRate }.max() ?? 0

            let info = CameraFormat(
                format: format,
                dimensions: dims,
                pixelCount: Int(dims.width) * Int(dims.height),
                fov: format.videoFieldOfView,
                minFps: minFps,
                maxFps: maxFps,
                isHDR: format.isVideoHDRSupported
            )
            formats.append(info)
        }
        formats.sort { $0.pixelCount > $1.pixelCount }
        cameraFormats[lens] = formats
    }
    
    private func selectFormats(
        for lens: LensType,
        targetFps: Double = 30.0
    ) {
        guard let formats = cameraFormats[lens], !formats.isEmpty else {
            print("no cached camera formats for lens \(lens)")
            return
        }

        // select camera formats by filtering for target fps, grouping by field of view (sensor gate),
        // choosing the largest fov group to avoid crop, then picking the highest-resolution format
        // for offscreen capture and a matching-FOV format for live preview.
        
        let fpsCapable = formats.filter { $0.maxFps >= targetFps }
        let groupedByFov = Dictionary(grouping: fpsCapable) { format in
            round(format.fov * 10) / 10   // bucket by 0.1° to avoid float noise
        }
        guard let bestFovGroup = groupedByFov
            .max(by: { $0.key < $1.key })?
            .value else {
            print("Failed to determine FOV group")
            return
        }
        let offscreen = bestFovGroup.max(by: { $0.pixelCount < $1.pixelCount })!
        let preferredViewWidth = 1920 // default to HD for referred view

        let view =
            bestFovGroup
                .filter { $0.maxFps >= targetFps }
                .sorted { a, b in
                    let da = abs(Int(a.dimensions.width) - preferredViewWidth)
                    let db = abs(Int(b.dimensions.width) - preferredViewWidth)
                    if da != db { return da < db }
                    return a.pixelCount < b.pixelCount
                }
                .first!

        self.offscreenFormat = offscreen
        self.viewFormat = view

        DispatchQueue.main.async {
            self.offscreenAspectRatio =
                CGFloat(offscreen.dimensions.width) /
                CGFloat(offscreen.dimensions.height)

            self.offscreenFov = CGFloat(offscreen.fov)
            self.viewFov = CGFloat(view.fov)
        }
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

    private func updateDeviceViewInfo(_ device: AVCaptureDevice) {
        let fov = CGFloat(device.activeFormat.videoFieldOfView)
        DispatchQueue.main.async {
            self.viewFov = fov
        }
    }
    
    private func updateDeviceOffscreenInfo(_ device: AVCaptureDevice) {
        let fov = CGFloat(device.activeFormat.videoFieldOfView)
        DispatchQueue.main.async {
            self.offscreenFov = fov
        }
    }
}

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {

    // apple explicitly mentions that auto-exposure/auto-white balance needs
    // a few frames to settle, and apps should allow "warm-up time" before using
    // frames for critical processing.

    private static let warmupFrameCount = 20
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let renderer else { return }
        if output === videoDataOutput {
            renderer.captureOutput(output, didOutput: sampleBuffer, from: connection)
        }
        else if output === offscreenDataOutput {
            guard !didDrawOffscreen else { return }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            
            offscreenFrameCounter += 1
            if offscreenFrameCounter < CameraModel.warmupFrameCount {
                return
            }
            didDrawOffscreen = true
            guard let completion = drawOffscreenCompletion else { return }
            drawOffscreenCompletion = nil
            renderer.drawOffscreen(pixelBuffer: pixelBuffer) { cgImage in
                DispatchQueue.main.async {
                    completion(cgImage)
                }
                self.enableOffscreenOutput(false)
                self.offscreenFrameCounter = 0
                
                if let device = self.captureSession.inputs
                    .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                    .first,
                    let format = self.restoreFormat {
                    do {
                        try device.lockForConfiguration()
                        device.activeFormat = format // can be AR or view format
                        device.unlockForConfiguration()
                    } catch {
                        print("failed to restore view format: \(error)")
                    }
                    self.restoreFormat = nil
                }
                if self.resumeARDrawOffscreen {
                    self.resumeARDrawOffscreen = false
                    self.resumeAR()
                }
                self.resumeRendering()
            }
        }
    }
}

extension CameraModel: ARSessionDelegate {
    private struct AssociatedKeys {
        static var arSessionKey: UInt8 = 0
    }

    var arSession: ARSession? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.arSessionKey) as? ARSession }
        set { objc_setAssociatedObject(self, &AssociatedKeys.arSessionKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func startARSession() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            if (self.lensType != .wide) {
                self.selectFormats(for: .wide) // AR is wide
            }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            config.environmentTexturing = .automatic
            config.isLightEstimationEnabled = true

            let arSession = ARSession()
            arSession.delegate = self
            arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
            self.arSession = arSession
        
            DispatchQueue.main.async {
                self.arState = .scanning
                self.captureAR = true
            }
        }
    }

    func stopARSession() {
        sessionQueue.async {
            if let ar = self.arSession {
                ar.pause()
                self.arSession = nil
            }

            self.renderer?.clearARCamera()

            DispatchQueue.main.async {
                self.arState = .idle
                self.captureAR = false
                self.updateARRenderer()
            }
        }
    }
    
    private func updateARRenderer() {
        guard let renderer else { return }
        switch arState {
        case .ready:
            renderer.enableAR()
            break
        case .placed:
            break
        default:
            renderer.disableAR()
        }
    }
    
    func loadARModel(from url: URL) {
        // todo: replace with code for AR, should be full PBR pipeline
        //print("[placeARModel] Loading model:", url.lastPathComponent)
        //renderer.loadModel(from: url)
    }
    
    func placeARModel() {
        guard let renderer else { return }
        
        print("placeARModel")
        
        renderer.placeAR()
        arState = .placed
    }
    
    func fovFromIntrinsics(_ intrinsics: simd_float3x3, resolution: CGSize) -> CGFloat {
        let fx = intrinsics.columns.0.x
        let fovXRadians = 2 * atan(Float(resolution.width) / (2 * fx))
        return CGFloat(fovXRadians * 180 / .pi)
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame)
    {
        guard captureAR, let renderer else { return }
        let pixelBuffer = frame.capturedImage
        renderer.captureAROutput(pixelBuffer: pixelBuffer)
        if arState == .ready || arState == .placed {
            renderer.updateARCamera(frame.camera)
        }
        let intr = frame.camera.intrinsics
        let res = frame.camera.imageResolution
        let fov = fovFromIntrinsics(intr, resolution: res)
        DispatchQueue.main.async {
            self.viewFov = fov
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard let renderer else { return }
        for anchor in anchors {
            if let probe = anchor as? AREnvironmentProbeAnchor {
                if let cubeTexture = probe.environmentTexture {
                    DispatchQueue.main.async {
                        renderer.updateAREnvironmentTexture(cubeTexture)
                    }
                }
            }
            guard let plane = anchor as? ARPlaneAnchor else { continue }
            if plane.alignment == .horizontal {
                DispatchQueue.main.async {
                    self.planeWorldTransform = plane.transform
                    renderer.updateARPlaneTransform(plane.transform)
                }
                if plane.classification == .floor {
                    if arState == .scanning {
                        DispatchQueue.main.async {
                            self.arState = .refining
                        }
                    }
                    if plane.areaXZ > 1.5 {
                        DispatchQueue.main.async {
                            self.arState = .ready
                            self.updateARRenderer()
                        }
                    }
                }
            }
        }
    }
}
