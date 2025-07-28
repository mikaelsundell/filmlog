// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import AVFoundation
import Combine
import CoreMotion

class OrientationObserver: ObservableObject {
    @Published var orientation: UIDeviceOrientation = UIDevice.current.orientation
    @Published var levelAngle: Double = 0.0
    @Published var pitchAngle: Double = 0.0
    
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
                
                if g.x.isNaN || g.y.isNaN || g.z.isNaN { return }
                
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
                self.pitchAngle = atan2(-g.z, sqrt(g.x * g.x + g.y * g.y)) * 180 / .pi
            }
        }
    }
}

struct ShotHelper {
    static func frameSize(containerSize: CGSize,
                          focalLength: CGFloat,
                          filmSize: CameraOptions.FilmSize,
                          horizontalFov: CGFloat) -> CGSize {
        let filmAspect = CGFloat(filmSize.aspectRatio)
        let filmHFov = 2 * atan(CGFloat(filmSize.width) / (2 * focalLength))
        let frameHorizontal = containerSize.width * (tan(filmHFov / 2) / tan((horizontalFov * .pi / 180) / 2))
        let frameVertical = frameHorizontal / filmAspect
        return CGSize(width: frameHorizontal, height: frameVertical)
    }
    
    static func ratioSize(frameSize: CGSize,
                          frameRatio: CGFloat) -> CGSize {
        let width = frameSize.width
        let height = width / frameRatio
        return CGSize(width: width, height: height)
    }
}

struct ShotOverlay: View {
    let aspectRatio: CGFloat
    let focalLength: CGFloat
    let filmSize: CameraOptions.FilmSize
    let horizontalFov: CGFloat
    let orientation: UIDeviceOrientation
    let showSymmetry: Bool
    
    var body: some View {
        GeometryReader { geo in
            let frameSize = ShotHelper.frameSize(
                containerSize: geo.size.switchOrientation(), // to native
                focalLength: focalLength,
                filmSize: filmSize,
                horizontalFov: horizontalFov
            )
            
            let ratioSize = ShotHelper.ratioSize(
                frameSize: frameSize,
                frameRatio: aspectRatio > 0.0 ? aspectRatio : filmSize.aspectRatio
            )
            
            let targetSize = frameSize.switchOrientation() // to potrait
            let targetRatio = ratioSize.switchOrientation() // to potrait
            
            ZStack {
                Color.black.opacity(0.6)
                .mask {
                    Rectangle()
                        .fill(Color.white)
                        .overlay(
                            Rectangle()
                                .frame(width: targetSize.width, height: targetSize.height)
                                .blendMode(.destinationOut)
                        )
                        .compositingGroup()
                }
                .animation(.easeInOut(duration: 0.3), value: targetSize)
                
                if showSymmetry {
                    Canvas { context, size in
                        context.translateBy(x: size.width / 2, y: size.height / 2)
                        context.rotate(by: .degrees(-90))
                        context.translateBy(x: -ratioSize.width / 2, y: -ratioSize.height / 2)

                        let w = ratioSize.width
                        let h = ratioSize.height
                        let d = CGSize(width: w - 1, height: h - 1)
                        let angle = .pi / 2 - atan(d.width / d.height)
                        let length = d.height * tan(angle)
                        let hypo = d.height * cos(angle)
                        let cross = CGSize(width: hypo * sin(angle), height: hypo * cos(angle))

                        var lines = Path()
                        lines.move(to: .zero) // diagonals
                        lines.addLine(to: CGPoint(x: w, y: h))

                        lines.move(to: CGPoint(x: 0, y: h))
                        lines.addLine(to: CGPoint(x: w, y: 0))
                        
                        lines.move(to: .zero) // reciprocals
                        lines.addLine(to: CGPoint(x: length, y: h))
                        
                        lines.move(to: CGPoint(x: 0, y: h))
                        lines.addLine(to: CGPoint(x: length, y: 0))
                        
                        lines.move(to: CGPoint(x: w, y: 0))
                        lines.addLine(to: CGPoint(x: w - length, y: h))
                        
                        lines.move(to: CGPoint(x: w, y: h))
                        lines.addLine(to: CGPoint(x: w - length, y: 0))
                        
                        lines.move(to: CGPoint(x: cross.width, y: 0)) // cross
                        lines.addLine(to: CGPoint(x: cross.width, y: h))
                        
                        lines.move(to: CGPoint(x: w - cross.width, y: 0))
                        lines.addLine(to: CGPoint(x: w - cross.width, y: h))
                        
                        lines.move(to: CGPoint(x: 0, y: cross.height))
                        lines.addLine(to: CGPoint(x: w, y: cross.height))
                        
                        lines.move(to: CGPoint(x: 0, y: h - cross.height))
                        lines.addLine(to: CGPoint(x: w, y: h - cross.height))
                        
                        context.stroke(lines, with: .color(.white.opacity(0.25)), lineWidth: 2)
                        
                        var extended = Path()
                        
                        extended.move(to: CGPoint(x: length, y: 0)) // inner cross
                        extended.addLine(to: CGPoint(x: length, y: ratioSize.height))
                        
                        extended.move(to: CGPoint(x: ratioSize.width - length, y: 0))
                        extended.addLine(to: CGPoint(x: ratioSize.width - length, y: ratioSize.height))
                        
                        let dashStyle = StrokeStyle(
                            lineWidth: 1,
                            lineCap: .butt,
                            dash: [5, 3]
                        )
                        
                        context.stroke(extended, with: .color(.white.opacity(0.25)), style: dashStyle)

                    }
                    .frame(width: targetRatio.width, height: targetRatio.height)
                }

                Rectangle()
                    .stroke(Color.blue, lineWidth: 2)
                    .frame(width: targetRatio.width, height: targetRatio.height)
    
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: targetSize.width, height: targetSize.height)
                
                VStack(spacing: 4) {
                    Text("\(Int(filmSize.width)) mm x \(Int(filmSize.height)) mm " +
                         "\(String(format: "%.2f", filmSize.aspectRatio)) @ " +
                         "\(String(format: "%.1f", filmSize.angleOfView(focalLength: focalLength).horizontal))°")
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .rotationEffect(orientation.angle)
                }
                .offset(offset(for: orientation, geo: geo))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
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
    var pitchAngle: Double
    let orientation: UIDeviceOrientation
    
    @State private var smoothedRoll: Double = 0.0
    @State private var smoothedPitch: Double = 0.0
    
    let totalWidthRatio: CGFloat = 0.8
    let gapRatio: CGFloat = 0.05
    let sideRatio: CGFloat = 0.10
    let lineHeight: CGFloat = 2
    
    var body: some View {
        GeometryReader { geo in
            let alpha = 0.15
            let snappedRoll = (smoothedRoll / 2).rounded() * 2
            let snappedPitch = smoothedPitch.clamped(to: -30...30) // limit range
            
            let isRollAligned = abs(snappedRoll) <= 2
            let isPitchAligned = abs(snappedPitch) <= 2
            
            let fullWidth = geo.size.width * totalWidthRatio
            let gap = fullWidth * gapRatio
            let sideWidth = fullWidth * sideRatio
            let centerWidth = fullWidth - (2 * sideWidth) - (2 * gap)
            
            let maxOffset: CGFloat = 50
            let pitchOffset = CGFloat(snappedPitch / 30) * maxOffset
            
            ZStack {
                Rectangle()
                    .fill(isPitchAligned ? Color.green.opacity(0.8) : Color.white.opacity(0.8))
                    .frame(width: sideWidth, height: lineHeight)
                    .position(x: geo.size.width / 2 - (centerWidth / 2 + gap + sideWidth / 2),
                              y: geo.size.height / 2 - pitchOffset)
                
                Rectangle()
                    .fill(isPitchAligned ? Color.green.opacity(0.8) : Color.white.opacity(0.8))
                    .frame(width: sideWidth, height: lineHeight)
                    .position(x: geo.size.width / 2 + (centerWidth / 2 + gap + sideWidth / 2),
                              y: geo.size.height / 2 - pitchOffset)
                
                Rectangle()
                    .fill(isRollAligned ? Color.green : Color.white)
                    .frame(width: centerWidth, height: lineHeight)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .rotationEffect(.degrees(snappedRoll))
            }
            .rotationEffect(orientation.angle)
            .animation(.easeInOut(duration: 0.15), value: snappedRoll)
            .animation(.easeInOut(duration: 0.15), value: snappedPitch)
            .onChange(of: levelAngle) { _, newValue in
                smoothedRoll += alpha * (newValue - smoothedRoll)
            }
            .onChange(of: pitchAngle) { _, newValue in
                smoothedPitch += alpha * (newValue - smoothedPitch)
            }
            .onAppear {
                smoothedRoll = levelAngle
                smoothedPitch = pitchAngle
            }
            
            ZStack {
                VStack(spacing: 4) {
                    Text("Roll: \(Int(snappedRoll))°, Pitch: \(Int(snappedPitch))°")
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .rotationEffect(orientation.angle)
                }
                .offset(offset(for: orientation, geo: geo))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .ignoresSafeArea()
    }

    private func offset(for orientation: UIDeviceOrientation, geo: GeometryProxy) -> CGSize {
        switch orientation {
        case .landscapeLeft: return CGSize(width: -geo.size.width / 2 + 25, height: 0)
        case .landscapeRight: return CGSize(width: geo.size.width / 2 - 25, height: 0)
        case .portraitUpsideDown: return CGSize(width: 0, height: -geo.size.height / 2 + 120)
        default: return CGSize(width: 0, height: geo.size.height / 2 - 120)
        }
    }
}

struct ShotViewfinderView: View {
    @Bindable var shot: Shot
    
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraModel = CameraModel()
    @AppStorage("showSymmetry") private var showSymmetry: Bool = false
    @AppStorage("showLevel") private var showLevel: Bool = false
    @AppStorage("selectedLens") private var selectedLensRawValue: String = CameraLensType.wide.rawValue
    
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
                        orientation: orientationObserver.orientation,
                        showSymmetry: showSymmetry
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    
                    if showLevel {
                        LevelIndicator(
                            levelAngle: orientationObserver.levelAngle,
                            pitchAngle: orientationObserver.pitchAngle,
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
                    .rotationEffect(orientationObserver.orientation.angle)
            }

            Button(action: {
                showSymmetry.toggle()
            }) {
                Image(systemName: "square.grid.3x3")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(showSymmetry ? Color.blue.opacity(0.7) : Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }

            Button(action: {
                showLevel.toggle()
            }) {
                Image(systemName: "gyroscope")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(showLevel ? Color.blue.opacity(0.7) : Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }

            Spacer()
        }
        .frame(width: 120)
    }
    
    @ViewBuilder
    private func exposureControls() -> some View {
        HStack(spacing: 8) {
            Spacer()
            
            Button(action: { resetExposure() }) {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }
            
            Button(action: { increaseExposure() }) {
                Image(systemName: "plus.circle")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }
            
            Button(action: { decreaseExposure() }) {
                Image(systemName: "minus.circle")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }
        }
        .frame(width: 120)
    }

    private func captureImage(image: UIImage) {
        let containerSize = UIScreen.main.bounds.size
        let filmSize = CameraOptions.filmSizes.first(where: { $0.label == shot.filmSize })?.value ?? CameraOptions.FilmSize.defaultFilmSize
        let focalLength = CameraOptions.focalLengths.first(where: { $0.label == shot.lensFocalLength })?.value ?? 0
        let frameSize = ShotHelper.frameSize(
            containerSize: containerSize.switchOrientation(), // to native
            focalLength: focalLength,
            filmSize: filmSize,
            horizontalFov: cameraModel.horizontalFov
        )
        let targetSize = frameSize.switchOrientation() // to potrait
        let croppedImage = cropImage(image, targetSize: targetSize, containerSize: containerSize, orientation: orientationObserver.orientation)
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
        
        let targetSize = targetSize.switchOrientation() // to potrait
        let targetCropWidth = targetSize.width * scaleX
        let targetCropHeight = targetSize.height * scaleY
        
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
            let newLens = lenses[nextIndex]
            cameraModel.switchCamera(to: newLens)
            selectedLensRawValue = newLens.rawValue
        }
    }
    
    func increaseExposure() {
        cameraModel.currentExposureBias += 0.25 // +0.25 ev
        cameraModel.adjustExposure(to: cameraModel.currentExposureBias)
    }

    func decreaseExposure() {
        cameraModel.currentExposureBias -= 0.25 // -0.25 ev
        cameraModel.adjustExposure(to: cameraModel.currentExposureBias)
    }

    func resetExposure() {
        cameraModel.currentExposureBias = 0.0
        cameraModel.adjustExposure(to: 0.0)
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
