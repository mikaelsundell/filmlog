// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI

struct ShotViewfinderView: View {
    @Bindable var shot: Shot
    
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var focusPoint: CGPoint? = nil
    @State private var imageDataToExport: Data? = nil
    @State private var showExport = false
    
    struct PickerContext {
        var labels: [String]
        var initialSelection: String
        var onSelect: (String) -> Void
    }

    @State private var pickerContext: PickerContext? = nil
    
    @StateObject private var cameraModel = CameraModel()
    
    @AppStorage("centerMode") private var centerModeRawValue: Int = ToggleMode.off.rawValue
    private var centerMode: ToggleMode {
        get { ToggleMode(rawValue: centerModeRawValue) ?? .off }
        set { centerModeRawValue = newValue.rawValue }
    }
    
    @AppStorage("symmetryMode") private var symmetryModeRawValue: Int = ToggleMode.off.rawValue
    private var symmetryMode: ToggleMode {
        get { ToggleMode(rawValue: symmetryModeRawValue) ?? .off }
        set { symmetryModeRawValue = newValue.rawValue }
    }
    
    @AppStorage("levelMode") private var levelModeRawValue: Int = ToggleMode.off.rawValue
    private var levelMode: ToggleMode {
        get { ToggleMode(rawValue: levelModeRawValue) ?? .off }
        set { levelModeRawValue = newValue.rawValue }
    }
    
    @AppStorage("lensType") private var selectedLensRawValue: String = LensType.wide.rawValue
    @AppStorage("cameraMode") private var cameraMode: CameraMode = .auto

    @ObservedObject private var orientationObserver = OrientationObserver()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            GeometryReader { geometry in
                ZStack {
                    CameraMetalPreview(renderer: cameraModel.renderer)
                    .ignoresSafeArea()
   
                    if let context = pickerContext {
                        CircularPickerView(
                            selectedLabel: context.initialSelection,
                            labels: context.labels,
                            onChange: { selected in
                                context.onSelect(selected)
                            },
                            onRelease: { _ in
                                pickerContext = nil
                            }
                        )
                        .frame(width: 300, height: 300)
                        .padding()
                        .zIndex(2)
                        .rotationEffect(orientationObserver.orientation.angle)
                    }
                    
                    FrameOverlay(
                        aspectRatio: shot.aspectRatio,
                        filter: shot.lensFilter,
                        focalLength: shot.lensFocalLength,
                        aperture: shot.aperture,
                        shutter: shot.shutter,
                        filmSize: shot.filmSize,
                        filmStock: shot.filmStock,
                        horizontalFov: cameraModel.horizontalFov,
                        orientation: orientationObserver.orientation,
                        cameraMode: cameraMode,
                        centerMode: centerMode,
                        symmetryMode: symmetryMode,
                        showOnlyText: pickerContext != nil
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)

                    if pickerContext == nil, levelMode != .off {
                        LevelIndicator(
                            levelAndPitch: orientationObserver.levelAndPitch,
                            orientation: orientationObserver.orientation,
                            levelMode: levelMode
                        )
                    }
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            
            if pickerContext == nil {
                GeometryReader { geo in
                    ZStack {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { gesture in
                                        let tapPoint = gesture.location
                                        guard tapPoint.y >= 0, tapPoint.y <= geo.size.height else {
                                            return
                                        }
                                        let top = CGRect(x: 0, y: 0, width: geo.size.width, height: 100)
                                        let bottom = CGRect(x: 0, y: geo.size.height - 80, width: geo.size.width, height: 80)
                                        if !top.contains(tapPoint) && !bottom.contains(tapPoint) {
                                            focusPoint = tapPoint
                                            cameraModel.focus(at: tapPoint, viewSize: geo.size)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                                focusPoint = nil
                                            }
                                        }
                                    }
                            )
                            .allowsHitTesting(true)
                            .ignoresSafeArea()
                        
                        if let point = focusPoint {
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 40, height: 40)
                                .position(x: point.x, y: point.y - 40)
                                .transition(.opacity)
                                .animation(.easeOut(duration: 0.3), value: focusPoint)
                        }
                    }
                }
            }
            
            ZStack {
                Color.clear
                VStack {
                    HStack {
                        toolsControls()
                        
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .frame(width: 42)

                        exposureControls()
                    }
                    .padding(.top, 42)
                    .padding(.horizontal)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            HStack {
                focalLengthControls()
                
                Button(action: {
                    cameraModel.captureTexture { cgImage in
                        if let cgImage = cgImage {
                            let image = UIImage(cgImage: cgImage)
                            captureImage(image: image) // same as before
                        } else {
                            print("failed to capture texture image")
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 48, height: 48)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 36, height: 36)
                    }
                }
                .frame(width: 60)
                
                aspectRatioControls()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .onAppear {
            cameraModel.configure() {
                let saved = LensType(rawValue: selectedLensRawValue) ?? .wide
                if cameraModel.lensType != saved {
                    cameraModel.switchCamera(to: saved)
                }
                switchExposure()
            }
            cameraModel.onImageCaptured = { result in
                switch result {
                case .success(let image):
                    captureImage(image: image)
                case .failure(let error):
                    print("camera error: \(error.localizedDescription)")
                }
            }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onChange(of: cameraMode) { _, newMode in
            switchExposure()
        }
        
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    @ViewBuilder
    private func focalLengthControls() -> some View {
        HStack(spacing: 6) {
            Button(action: {
                if let currentIndex = CameraOptions.focalLengths.firstIndex(where: { $0.label == shot.lensFocalLength }) {
                    let newIndex = (currentIndex - 1 + CameraOptions.focalLengths.count) % CameraOptions.focalLengths.count
                    shot.lensFocalLength = CameraOptions.focalLengths[newIndex].label
                }
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }

            Text("\(shot.lensFocalLength)")
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(width: 50)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.4))
                .cornerRadius(4)
                .rotationEffect(orientationObserver.orientation.angle)

            Button(action: {
                if let currentIndex = CameraOptions.focalLengths.firstIndex(where: { $0.label == shot.lensFocalLength }) {
                    let newIndex = (currentIndex + 1) % CameraOptions.focalLengths.count
                    shot.lensFocalLength = CameraOptions.focalLengths[newIndex].label
                }
            }) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
        }
    }
    
    @ViewBuilder
    private func aspectRatioControls() -> some View {
        HStack(spacing: 6) {
            Button(action: {
                if let currentIndex = CameraOptions.aspectRatios.firstIndex(where: { $0.label == shot.aspectRatio }) {
                    let newIndex = (currentIndex - 1 + CameraOptions.aspectRatios.count) % CameraOptions.aspectRatios.count
                    shot.aspectRatio = CameraOptions.aspectRatios[newIndex].label
                }
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }

            Text("\(shot.aspectRatio)")
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(width: 50)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.4))
                .cornerRadius(4)
                .rotationEffect(orientationObserver.orientation.angle)

            Button(action: {
                if let currentIndex = CameraOptions.aspectRatios.firstIndex(where: { $0.label == shot.aspectRatio }) {
                    let newIndex = (currentIndex + 1) % CameraOptions.aspectRatios.count
                    shot.aspectRatio = CameraOptions.aspectRatios[newIndex].label
                }
            }) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
        }
    }
    
    @ViewBuilder
    private func toolsControls() -> some View {
        HStack(spacing: 6) {
            Button(action: { toggleLens() }) {
                Text(lensLabel(for: cameraModel.lensType))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }
            
            Button(action: {
                centerModeRawValue = centerMode.next().rawValue
            }) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(centerMode.color)
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }
            
            Button(action: {
                symmetryModeRawValue = symmetryMode.next().rawValue
            }) {
                Image(systemName: "grid")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(symmetryMode.color)
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }

            Button(action: {
                levelModeRawValue = levelMode.next().rawValue
            }) {
                Image(systemName: "gyroscope")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(levelMode.color)
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }
            
            Spacer()

        }
        .frame(width: 145)
    }
    
    @ViewBuilder
    private func exposureControls() -> some View {
        HStack(spacing: 6) {
            Spacer()

            Button(action: { toggleExposure() }) {
                Text(cameraLabel(for: cameraMode))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }
            
            let evMode = cameraMode == .manual
            let opacity = evMode ? 1.0 : 0.4

            Button(action: {
                if evMode {
                    if let context = pickerContext,
                       context.initialSelection == shot.lensFilter,
                       context.labels == CameraOptions.filters.map({ $0.label }) {
                        pickerContext = nil
                    } else {
                        pickerContext = PickerContext(
                            labels: CameraOptions.filters.map { $0.label },
                            initialSelection: shot.lensFilter,
                            onSelect: { selected in
                                shot.lensFilter = selected
                                adjustEVExposure()
                                adjustWhiteBalance()
                            }
                        )
                    }
                }
            }) {
                Image(systemName: "camera.filters")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }
            
            Button(action: {
                if evMode {
                    if let context = pickerContext,
                       context.initialSelection == CameraOptions.shutters.first(where: { $0.label == shot.shutter })?.label,
                       context.labels == CameraOptions.shutters.map({ $0.label }) {
                        pickerContext = nil
                    } else {
                        pickerContext = PickerContext(
                            labels: CameraOptions.shutters.map { $0.label },
                            initialSelection: shot.shutter,
                            onSelect: { selected in
                                shot.shutter = selected
                                adjustEVExposure()
                            }
                        )
                    }
                }
            }) {
                Image(systemName: "plusminus.circle")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }
            .disabled(!evMode)
            .opacity(opacity)

            Button(action: {
                if evMode {
                    if let context = pickerContext,
                       context.initialSelection == CameraOptions.apertures.first(where: { $0.label == shot.aperture })?.label,
                       context.labels == CameraOptions.apertures.map({ $0.label }) {
                        pickerContext = nil
                    } else {
                        pickerContext = PickerContext(
                            labels: CameraOptions.apertures.map { $0.label },
                            initialSelection: shot.aperture,
                            onSelect: { selected in
                                shot.aperture = selected
                                adjustEVExposure()
                            }
                        )
                    }
                }
            }) {
                Image(systemName: "camera.aperture")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }
            .disabled(!evMode)
            .opacity(opacity)
        }
        .frame(width: 145)
    }

    private func captureImage(image: UIImage) {
        let containerSize = UIScreen.main.bounds.size
        let filmSize = CameraOptions.filmSizes.first(where: { $0.label == shot.filmSize })?.value ?? CameraOptions.FilmSize.defaultFilmSize
        let focalLength = CameraOptions.focalLengths.first(where: { $0.label == shot.lensFocalLength })?.value ?? CameraOptions.FocalLength.defaultFocalLength
        let frameSize = FrameHelper.frameSize(
            containerSize: containerSize.switchOrientation(), // to native
            focalLength: focalLength.length,
            aspectRatio: filmSize.aspectRatio,
            width: filmSize.width,
            horizontalFov: cameraModel.horizontalFov
        )
        let croppedImage = cropImage(image, frameSize: frameSize, containerSize: containerSize, orientation: orientationObserver.orientation)
        onCapture(croppedImage)
        dismiss()
    }
    
    private func cropImage(_ image: UIImage,
                           frameSize: CGSize,
                           containerSize: CGSize,
                           orientation: UIDeviceOrientation) -> UIImage {
        
        guard let cgImage = image.cgImage else { return image }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        let size = containerSize.switchOrientation() // to native
        let ratio = size.width / size.height
        
        let newHeight = width / ratio
        let offsetY = max((height - newHeight) / 2, 0)
        let landscapeRect = CGRect(x: 0, y: offsetY, width: width, height: newHeight)
        
        guard let nativeImage = cgImage.cropping(to: landscapeRect) else { return image }
        
        let cropWidth = CGFloat(nativeImage.width)
        let cropHeight = CGFloat(nativeImage.height)
        
        let scaleX = cropWidth / size.width
        let scaleY = cropHeight / size.height
        
        let targetSize = frameSize
        let targetCropWidth = targetSize.width * scaleX
        let targetCropHeight = targetSize.height * scaleY
        
        let cropX = max((cropWidth - targetCropWidth) / 2, 0)
        let cropY = max((cropHeight - targetCropHeight) / 2, 0)
        let cropRect = CGRect(x: cropX, y: cropY, width: targetCropWidth, height: targetCropHeight)
        
        guard let targetImage = nativeImage.cropping(to: cropRect) else {
            return UIImage(cgImage: nativeImage, scale: image.scale, orientation: cropOrientation(for: orientation)) // landscape with orientation
        }
        
        return UIImage(cgImage: targetImage, scale: image.scale, orientation: cropOrientation(for: orientation))
    }
    
    private func cropOrientation(for deviceOrientation: UIDeviceOrientation) -> UIImage.Orientation {
        switch deviceOrientation {
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        case .portraitUpsideDown:
            return .left
        default:
            return .right
        }
    }
    
    func captureScreenshot() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows
            .first(where: \.isKeyWindow) else {
                print("unable to find key window for screenshot")
                return
            }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        print("screenshot saved to Photos")
    }
    
    private func lensLabel(for lens: LensType) -> String {
        switch lens {
        case .ultraWide: return "x.5"
        case .wide: return "x1"
        }
    }
    
    private func cameraLabel(for exposure: CameraMode) -> String {
        switch exposure {
        case .auto: return "A"
        case .manual: return "M"
        }
    }
    
    private func toggleLens() {
        let lenses: [LensType] = [.ultraWide, .wide]
        if let currentIndex = lenses.firstIndex(of: cameraModel.lensType) {
            let nextIndex = (currentIndex + 1) % lenses.count
            let newLens = lenses[nextIndex]
            selectedLensRawValue = newLens.rawValue
            cameraModel.switchCamera(to: newLens)
            switchExposure()
        }
    }
    
    private func toggleExposure() {
        let exposures: [CameraMode] = [.auto, .manual]
        if let currentIndex = exposures.firstIndex(of: cameraMode) {
            let nextIndex = (currentIndex + 1) % exposures.count
            cameraMode = exposures[nextIndex]
            switchExposure()
        }
    }
    
    func switchExposure() {
        if cameraMode == .auto {
            adjustAutoExposure()
            resetWhiteBalance()
        } else {
            adjustEVExposure()
            adjustWhiteBalance();
        }
    }
    
    func adjustAutoExposure() {
        cameraModel.adjustAutoExposure(ev: 0);
    }
    
    func adjustEVExposure() {
        let filmStock = CameraOptions.filmStocks.first(where: { $0.label == shot.filmStock })?.value ?? CameraOptions.FilmStock.defaultFilmStock
        let aperture = CameraOptions.apertures.first(where: { $0.label == shot.aperture })?.value ?? CameraOptions.Aperture.defaultAperture
        let shutter = CameraOptions.shutters.first(where: { $0.label == shot.shutter })?.value ?? CameraOptions.Shutter.defaultShutter
        let filter = CameraOptions.filters.first(where: { $0.label == shot.lensFilter })?.value ?? CameraOptions.Filter.defaultFilter
        
        cameraModel.adjustEVExposure(
            fstop: aperture.fstop,
            speed: filmStock.speed,
            shutter: shutter.shutter,
            exposureCompensation: filter.exposureCompensation
        )
    }
    
    func adjustWhiteBalance() {
        let filmStock = CameraOptions.filmStocks.first(where: { $0.label == shot.filmStock })?.value ?? CameraOptions.FilmStock.defaultFilmStock
        if shot.lensFilter != "-" {
            let filter = CameraOptions.filters.first(where: { $0.label == shot.lensFilter })?.value ?? CameraOptions.Filter.defaultFilter
            cameraModel.adjustWhiteBalance(kelvin: filmStock.colorTemperature + filter.colorTemperatureShift)
        } else {
            cameraModel.resetWhiteBalance()
        }
    }
    
    func resetWhiteBalance() {
        cameraModel.resetWhiteBalance()
    }
}

extension CGSize {
    func switchOrientation() -> CGSize {
        return CGSize(width: self.height, height: self.width)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

extension UIDeviceOrientation {
    var angle: Angle {
        switch self {
        case .landscapeLeft: return .degrees(90)
        case .landscapeRight: return .degrees(-90)
        case .portraitUpsideDown: return .degrees(180)
        default: return .degrees(0)
        }
    }
}
