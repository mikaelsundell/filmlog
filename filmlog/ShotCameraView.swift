// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import AVFoundation
import Combine
import CoreMotion

class OrientationObserver: ObservableObject {
    @Published var orientation: UIDeviceOrientation = UIDevice.current.orientation
    @Published var levelAngle: Double = 0.0  // Horizon angle
    
    private var cancellable: AnyCancellable?
    private var motionManager = CMMotionManager()
    
    init() {
        cancellable = NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .compactMap { _ -> UIDeviceOrientation? in
                let current = UIDevice.current.orientation
                return current.isValidInterfaceOrientation ? current : nil
            }
            .sink { [weak self] newOrientation in
                self?.orientation = newOrientation
            }
        
        startMotionUpdates()
    }
    
    private func startMotionUpdates() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.02
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self = self, let motion = motion else { return }
                let g = motion.gravity
                
                var angle: Double = 0
                
                switch self.orientation {
                case .portrait:
                    angle = atan2(g.x, g.y) * 180 / .pi
                    if angle > 90 { angle -= 180 }
                    if angle < -90 { angle += 180 }
                case .portraitUpsideDown:
                    angle = atan2(-g.x, -g.y) * 180 / .pi
                    if angle > 90 { angle -= 180 }
                    if angle < -90 { angle += 180 }
                case .landscapeLeft:
                    angle = atan2(g.y, -g.x) * 180 / .pi
                case .landscapeRight:
                    angle = atan2(-g.y, g.x) * 180 / .pi
                default:
                    angle = atan2(g.x, g.y) * 180 / .pi
                }
                
                self.levelAngle = angle
            }
        }
    }
    
    var rotationAngle: Angle {
        switch orientation {
        case .landscapeLeft: return .degrees(90)
        case .landscapeRight: return .degrees(-90)
        case .portraitUpsideDown: return .degrees(180)
        default: return .degrees(0)
        }
    }
}

struct ShotHelper {
    static func calculateFrame(containerSize: CGSize,
                               focalLength: CGFloat,
                               filmSize: CameraOptions.FilmSize,
                               horizontalFov: CGFloat) -> CGSize {
        let filmAspect = CGFloat(filmSize.aspectRatio)
        let filmHFov = 2 * atan(CGFloat(filmSize.width) / (2 * focalLength))
        let frameHorizontal = containerSize.height * (tan(filmHFov / 2) / tan((horizontalFov * .pi / 180) / 2))
        let frameVertical = frameHorizontal / filmAspect
        
        print("frameVertical: \(frameVertical) x \(frameHorizontal)")
        
        return CGSize(width: frameVertical, height: frameHorizontal)
    }
    
    static func calculateAspectFrame(containerSize: CGSize,
                                     frameSize: CGSize,
                                     aspectRatio: CGFloat,
                                     orientation: UIDeviceOrientation) -> CGSize? {
        
        guard aspectRatio > 0 else { return nil }
        if orientation.isLandscape {
            let height = frameSize.height
            let width = height / aspectRatio
            return CGSize(width: width, height: height)
        } else {
            let width = frameSize.width
            let height = width / aspectRatio
            return CGSize(width: width, height: height)
        }
    }
}

struct ShotOverlay: View {
    let aspectRatio: CGFloat
    let focalLength: CGFloat
    let filmSize: CameraOptions.FilmSize
    let horizontalFov: CGFloat
    let orientation: UIDeviceOrientation
    
    var body: some View {
        GeometryReader { geo in
            let frameSize = ShotHelper.calculateFrame(
                containerSize: geo.size,
                focalLength: focalLength,
                filmSize: filmSize,
                horizontalFov: horizontalFov
            )
            
            let aspectSize = ShotHelper.calculateAspectFrame(
                containerSize: geo.size,
                frameSize: frameSize,
                aspectRatio: aspectRatio,
                orientation: orientation
            )

            ZStack {
                Color.black.opacity(0.6)
                .mask {
                    Rectangle()
                        .fill(Color.white)
                        .overlay(
                            Rectangle()
                                .frame(width: frameSize.width, height: frameSize.height)
                                .blendMode(.destinationOut)
                        )
                        .compositingGroup()
                }
                .animation(.easeInOut(duration: 0.3), value: frameSize)

                if let aspectSize {
                    Rectangle()
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: aspectSize.width, height: aspectSize.height)
                }
                
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: frameSize.width, height: frameSize.height)
                
                VStack(spacing: 4) {
                    Text("\(Int(filmSize.width)) mm x \(Int(filmSize.height)) mm " +
                         "\(String(format: "%.2f", filmSize.aspectRatio)) @ " +
                         "\(String(format: "%.1f", filmSize.angleOfView(focalLength: focalLength).horizontal))°")
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .rotationEffect(rotationAngle(for: orientation))
                }
                .offset(offset(for: orientation, geo: geo))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
    
    private func rotationAngle(for orientation: UIDeviceOrientation) -> Angle {
        switch orientation {
        case .landscapeLeft: return .degrees(90)
        case .landscapeRight: return .degrees(-90)
        case .portraitUpsideDown: return .degrees(180)
        default: return .degrees(0)
        }
    }

    private func offset(for orientation: UIDeviceOrientation, geo: GeometryProxy) -> CGSize {
        switch orientation {
        case .landscapeLeft: return CGSize(width: geo.size.width / 2 - 25, height: 0)
        case .landscapeRight: return CGSize(width: -geo.size.width / 2 + 25, height: 0)
        case .portraitUpsideDown: return CGSize(width: 0, height: geo.size.height / 2 - 120)
        default: return CGSize(width: 0, height: -geo.size.height / 2 + 120)
        }
    }
}

struct LevelIndicator: View {
    var levelAngle: Double
    var orientationAngle: Angle
    var orientation: UIDeviceOrientation
    
    @State private var smoothedAngle: Double = 0.0
    
    let totalWidthRatio: CGFloat = 0.8
    let gapRatio: CGFloat = 0.05
    let sideRatio: CGFloat = 0.10
    let lineHeight: CGFloat = 2
    
    var body: some View {
        GeometryReader { geo in
            let alpha = 0.15
            let snapped = (smoothedAngle / 2).rounded() * 2
            let isAligned = abs(snapped) <= 2
            
            let fullWidth = geo.size.width * totalWidthRatio
            let gap = fullWidth * gapRatio
            let sideWidth = fullWidth * sideRatio
            let centerWidth = fullWidth - (2 * sideWidth) - (2 * gap)
            
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: sideWidth, height: lineHeight)
                    .position(x: geo.size.width / 2 - (centerWidth / 2 + gap + sideWidth / 2),
                              y: geo.size.height / 2)
                
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: sideWidth, height: lineHeight)
                    .position(x: geo.size.width / 2 + (centerWidth / 2 + gap + sideWidth / 2),
                              y: geo.size.height / 2)
                
                Rectangle()
                    .fill(isAligned ? Color.green : Color.white)
                    .frame(width: centerWidth, height: lineHeight)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .rotationEffect(.degrees(snapped))
            }
            .rotationEffect(orientationAngle)
            .animation(.easeInOut(duration: 0.15), value: snapped)
            .animation(.easeInOut(duration: 0.2), value: isAligned)
            .onChange(of: levelAngle) { _, newValue in
                smoothedAngle = smoothedAngle + alpha * (newValue - smoothedAngle)
            }
            .onAppear {
                smoothedAngle = levelAngle
            }
        }
        .ignoresSafeArea()
    }
}

struct ShotCameraView: View {
    @Bindable var shot: Shot
    
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraModel = CameraModel()
    @State private var showLenses = false
    @State private var showAspectRatios = false
    @State private var isLevelOn = false
    @State private var isSymmetryOn = false
    
    @ObservedObject private var orientationObserver = OrientationObserver()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: cameraModel.session)
               .animation(.easeInOut(duration: 0.3), value: orientationObserver.orientation)
               .ignoresSafeArea()
            
            GeometryReader { geometry in
                ZStack {
                    CameraPreview(session: cameraModel.session)
                        .animation(.easeInOut(duration: 0.3), value: orientationObserver.orientation)
                        .ignoresSafeArea()
                    
                    ShotOverlay(
                        aspectRatio: CameraOptions.aspectRatios.first(where: { $0.label == shot.aspectRatio })?.value ?? 0,
                        focalLength: CameraOptions.focalLengths.first(where: { $0.label == shot.lensFocalLength })?.value ?? 0,
                        filmSize: CameraOptions.filmSizes.first(where: { $0.label == shot.filmSize })?.value ?? CameraOptions.FilmSize.defaultFilmSize,
                        horizontalFov: cameraModel.horizontalFov,
                        orientation: orientationObserver.orientation
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    
                    if isLevelOn {
                        LevelIndicator(
                            levelAngle: orientationObserver.levelAngle,
                            orientationAngle: orientationObserver.rotationAngle,
                            orientation: orientationObserver.orientation
                        )
                    }
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            
            ZStack {
                Color.clear
                VStack {
                    HStack {
                        toolsControls()
                        
                        Spacer()
                        
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        Spacer()

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
                
                Spacer()

                Button(action: { cameraModel.capturePhoto() }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 48, height: 48)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 36, height: 36)
                    }
                }
                .frame(width: 64)

                Spacer()

                aspectRatioControls()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .onAppear {
            cameraModel.configure()
            cameraModel.onImageCaptured = { result in
                switch result {
                case .success(let image):
                    captureImage(image: image)
                case .failure(let error):
                    print("camera error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @ViewBuilder
    private func focalLengthControls() -> some View {
        HStack(spacing: 4) {
            Button(action: {
                if let currentIndex = CameraOptions.focalLengths.firstIndex(where: { $0.label == shot.lensFocalLength }),
                   currentIndex > 0 {
                    shot.lensFocalLength = CameraOptions.focalLengths[currentIndex - 1].label
                }
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            Button(action: { showLenses.toggle() }) {
                Text("\(shot.lensFocalLength)")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .frame(width: 50)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(4)
                    .rotationEffect(orientationObserver.rotationAngle)
            }
            Button(action: {
                if let currentIndex = CameraOptions.focalLengths.firstIndex(where: { $0.label == shot.lensFocalLength }),
                   currentIndex < CameraOptions.focalLengths.count - 1 {
                    shot.lensFocalLength = CameraOptions.focalLengths[currentIndex + 1].label
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
        HStack(spacing: 0) {
            Button(action: {
                if let currentIndex = CameraOptions.aspectRatios.firstIndex(where: { $0.label == shot.aspectRatio }),
                   currentIndex > 0 {
                    shot.aspectRatio = CameraOptions.aspectRatios[currentIndex - 1].label
                }
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            Button(action: { showAspectRatios.toggle() }) {
                Text("\(shot.aspectRatio)")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .frame(width: 50)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(4)
                    .rotationEffect(orientationObserver.rotationAngle)
            }
            Button(action: {
                if let currentIndex = CameraOptions.aspectRatios.firstIndex(where: { $0.label == shot.aspectRatio }),
                   currentIndex < CameraOptions.aspectRatios.count - 1 {
                    shot.aspectRatio = CameraOptions.aspectRatios[currentIndex + 1].label
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
        HStack(spacing: 8) {
            Button(action: { toggleLens() }) {
                Text(lensLabel(for: cameraModel.currentLens))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.rotationAngle)
            }

            Button(action: {
                isSymmetryOn.toggle()
            }) {
                Text("S")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(isSymmetryOn ? Color.blue.opacity(0.7) : Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.rotationAngle)
            }

            Button(action: {
                isLevelOn.toggle()
            }) {
                Text("L")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(isLevelOn ? Color.blue.opacity(0.7) : Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.rotationAngle)
            }

            Spacer()
        }
        .frame(width: 120)
    }
    
    @ViewBuilder
    private func exposureControls() -> some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: { increaseExposure() }) {
                Text("+")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.rotationAngle)
            }
            Button(action: { decreaseExposure() }) {
                Text("-")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.rotationAngle)
            }
        }
        .frame(width: 120)
    }

    private func captureImage(image: UIImage) {
        let containerSize = UIScreen.main.bounds.size
        let filmSize = CameraOptions.filmSizes.first(where: { $0.label == shot.filmSize })?.value ?? CameraOptions.FilmSize.defaultFilmSize
        let focalLength = CameraOptions.focalLengths.first(where: { $0.label == shot.lensFocalLength })?.value ?? 0
        let frameSize = ShotHelper.calculateFrame(
            containerSize: containerSize,
            focalLength: focalLength,
            filmSize: filmSize,
            horizontalFov: cameraModel.horizontalFov
        )
        let croppedImage = cropImage(image, targetSize: frameSize, containerSize: containerSize, orientation: orientationObserver.orientation)
        onCapture(croppedImage)
        dismiss()
    }
    
    private func cropImage(_ image: UIImage,
                           targetSize: CGSize,
                           containerSize: CGSize,
                           orientation: UIDeviceOrientation) -> UIImage {
        
        guard let cgImage = image.cgImage else { return image }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        let landscapeContainerSize = containerSize.landscape()
        let containerRatio = landscapeContainerSize.width / landscapeContainerSize.height
        
        let newHeight = width / containerRatio
        let offsetY = max((height - newHeight) / 2, 0)
        let landscapeRect = CGRect(x: 0, y: offsetY, width: width, height: newHeight)
        
        guard let nativeImage = cgImage.cropping(to: landscapeRect) else { return image }
        
        let cropWidth = CGFloat(nativeImage.width)
        let cropHeight = CGFloat(nativeImage.height)
        
        let scaleX = cropWidth / landscapeContainerSize.width
        let scaleY = cropHeight / landscapeContainerSize.height
        
        let landscapeTargetSize = targetSize.landscape()
        let targetCropWidth = landscapeTargetSize.width * scaleX
        let targetCropHeight = landscapeTargetSize.height * scaleY
        
        let cropX = max((cropWidth - targetCropWidth) / 2, 0)
        let cropY = max((cropHeight - targetCropHeight) / 2, 0)
        let cropRect = CGRect(x: cropX, y: cropY, width: targetCropWidth, height: targetCropHeight)
        
        guard let targetImage = nativeImage.cropping(to: cropRect) else {
            return UIImage(cgImage: nativeImage, scale: image.scale, orientation: cropOrientation(for: orientation))
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
    
    private func lensLabel(for lens: CameraLensType) -> String {
        switch lens {
        case .ultraWide: return "x0.5"
        case .wide: return "x1"
        }
    }
    
    private func toggleLens() {
        let lenses: [CameraLensType] = [.ultraWide, .wide]
        if let currentIndex = lenses.firstIndex(of: cameraModel.currentLens) {
            let nextIndex = (currentIndex + 1) % lenses.count
            cameraModel.switchCamera(to: lenses[nextIndex])
        }
    }

    func increaseExposure() {
        cameraModel.adjustExposure(by: 0.25) // +0.25 EV
    }
    
    func decreaseExposure()
    {
        cameraModel.adjustExposure(by: -0.25) // -0.25 EV
    }

}

extension CGSize {
    func landscape() -> CGSize {
        return CGSize(width: self.height, height: self.width)
    }
}

