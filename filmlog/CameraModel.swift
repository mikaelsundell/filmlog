// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
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

final class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let output = AVCapturePhotoOutput()
    let session = AVCaptureSession()

    var onImageCaptured: ((Result<UIImage, CameraError>) -> Void)?

    @Published var horizontalFov: CGFloat = 0
    @Published var aspectRatio: CGFloat = 0
    @Published var lensType: LensType = .wide
    @Published var currentExposureBias: Float = 0.0 {
        didSet {
            UserDefaults.standard.set(currentExposureBias, forKey: "exposureBias")
        }
    }
    
    private var saveCapturedToFile = false

    func configure(completion: (() -> Void)? = nil) {
        Task {
            do {
                try await checkCameraPermission()
                DispatchQueue.main.async {
                    if let raw = UserDefaults.standard.string(forKey: "selectedLens"),
                       let storedLens = LensType(rawValue: raw) {
                        self.lensType = storedLens
                    }
                    self.currentExposureBias = UserDefaults.standard.float(forKey: "exposureBias")
                }
                configureCamera(for: lensType, completion: completion)
            } catch {
                DispatchQueue.main.async {
                    self.onImageCaptured?(.failure(.permissionDenied))
                }
            }
        }
    }

    private func configureCamera(for lens: LensType, completion: (() -> Void)? = nil) {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

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
                    self.onImageCaptured?(.failure(.configurationFailed("Device not available for \(lens.rawValue).")))
                }
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)

                if #available(iOS 16.0, *) {
                    let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                    self.output.maxPhotoDimensions = dimensions
                } else {
                    self.output.isHighResolutionCaptureEnabled = true
                }
            } else {
                DispatchQueue.main.async {
                    self.onImageCaptured?(.failure(.configurationFailed("Cannot add photo output.")))
                }
                self.session.commitConfiguration()
                return
            }

            self.session.commitConfiguration()
            if !self.session.isRunning {
                self.session.startRunning()
            }

            self.updateDeviceInfo(device)
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    func switchCamera(to lens: LensType) {
        lensType = lens
        UserDefaults.standard.set(lens.rawValue, forKey: "selectedLens")
        configureCamera(for: lens)
    }
    
    func adjustWhiteBalance(kelvin: Double) {
        print("adjustWhitebalace: \(kelvin)")
        sessionQueue.async {
            guard let device = self.session.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first else { return }

            do {
                try device.lockForConfiguration()
                
                let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(kelvin), tint: 0)
                var gains = device.deviceWhiteBalanceGains(for: temperatureAndTint)
                gains = self.normalizedGains(gains, for: device)

                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                print("failed to set WB: \(error.localizedDescription)")
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
    
    func adjustAutoExposure(ev: Float) {
        print("adjustAutoExposure: \(ev)")
        sessionQueue.async {
            guard let device = self.session.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first else { return }

            do {
                try device.lockForConfiguration()
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
        print("adjustEVExposure: \(exposureCompensation)")
        sessionQueue.async {
            guard let device = self.session.inputs
                .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
                .first else {
                    print("adjustEVExposure: No device found")
                    return
                }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isExposureModeSupported(.custom) {
                    device.exposureMode = .custom
                }

                let Ndev = Double(device.lensAperture)
                
                // apply exposureCompensation here (in ev stops)
                let EVtarget = (log2((fstop * fstop) / shutter) - log2(speed / 100.0)) - exposureCompensation

                let minSpeed = Double(device.activeFormat.minISO)
                let maxSpeed = Double(device.activeFormat.maxISO)
                let minShutter = device.activeFormat.minExposureDuration.seconds
                let maxShutter = device.activeFormat.maxExposureDuration.seconds

                var actualShutter = max(min(1.0 / 125.0, maxShutter), minShutter)
                let ISOcalc = 100.0 * Ndev * Ndev / (pow(2.0, EVtarget) * actualShutter)

                let ISOtoApply: Double
                if ISOcalc > maxSpeed {
                    actualShutter = min(max(100.0 * Ndev * Ndev / (pow(2.0, EVtarget) * maxSpeed),
                                            minShutter), maxShutter)
                    ISOtoApply = maxSpeed
                } else if ISOcalc < minSpeed {
                    actualShutter = min(max(100.0 * Ndev * Ndev / (pow(2.0, EVtarget) * minSpeed),
                                            minShutter), maxShutter)
                    ISOtoApply = minSpeed
                } else {
                    ISOtoApply = ISOcalc
                }
                
                let exposureDuration = CMTimeMakeWithSeconds(actualShutter, preferredTimescale: 1_000_000_000)
                device.setExposureModeCustom(duration: exposureDuration, iso: Float(ISOtoApply), completionHandler: nil)

                if device.isWhiteBalanceModeSupported(.locked) {
                    device.whiteBalanceMode = .locked
                }

                device.isSubjectAreaChangeMonitoringEnabled = false

                #if DEBUG
                print("""
                adjustEVExposure:
                - EVtarget (with compensation): \(EVtarget)
                - Compensation: \(exposureCompensation)
                - ISO: \(ISOtoApply)
                - Shutter: \(actualShutter)s
                """)
                #endif
                
            } catch {
                print("failed to adjust EV exposure error: \(error.localizedDescription)")
            }
        }
    }

    func focus(at point: CGPoint, viewSize: CGSize) {
        let focusPoint = CGPoint(x: point.y / viewSize.height, y: 1.0 - point.x / viewSize.width)
        guard let device = AVCaptureDevice.default(for: .video) else { return }
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

    func capturePhoto() {
        saveCapturedToFile = false
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        output.capturePhoto(with: settings, delegate: self)
    }

    func capturePhotoAndSave() {
        saveCapturedToFile = true
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        if #available(iOS 16.0, *) {
            // maxPhotoDimensions already set in configure
        } else {
            settings.isHighResolutionPhotoEnabled = true
        }
        output.capturePhoto(with: settings, delegate: self)
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

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.onImageCaptured?(.failure(.captureFailed(error.localizedDescription)))
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async {
                self.onImageCaptured?(.failure(.captureFailed("Could not process photo data.")))
            }
            return
        }

        if saveCapturedToFile {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            if let jpegData = image.jpegData(compressionQuality: 1.0) {
                let filename = FileManager.default.temporaryDirectory.appendingPathComponent("capture.jpg")
                do {
                    try jpegData.write(to: filename)
                    print("📸 Saved photo to file: \(filename.path)")
                } catch {
                    DispatchQueue.main.async {
                        self.onImageCaptured?(.failure(.saveFailed(error.localizedDescription)))
                    }
                    return
                }
            }
        }

        DispatchQueue.main.async {
            self.onImageCaptured?(.success(image))
        }
    }
}
