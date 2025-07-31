// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import AVFoundation
import Combine
import CoreMotion

enum ToggleMode: Int, CaseIterable {
    case off = 0
    case partial = 1
    case full = 2
    var color: Color {
        switch self {
        case .off: return Color.black.opacity(0.4)
        case .partial: return Color.blue.opacity(0.4)
        case .full: return Color.blue.opacity(1.0)
        }
    }
    func next() -> ToggleMode {
        let all = Self.allCases
        return all[(self.rawValue + 1) % all.count]
    }
}

enum ExposureMode: String, CaseIterable {
    case autoExposure = "AE"
    case evExposure = "EV"
}

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
                DispatchQueue.main.async {
                    self.levelAngle = angle
                    self.pitchAngle = atan2(-g.z, sqrt(g.x * g.x + g.y * g.y)) * 180 / .pi
                }
                
            }
        }
    }
}

struct ShotHelper {
    static func frameSize(containerSize: CGSize,
                          focalLength: Double,
                          aspectRatio: Double,
                          width: Double,
                          horizontalFov: CGFloat) -> CGSize {
        guard focalLength > 0, horizontalFov > 0 else {
            return .zero
        }
        let filmHFov = 2 * atan(CGFloat(width) / (2 * focalLength))
        let frameHorizontal = containerSize.width * (tan(filmHFov / 2) / tan((horizontalFov * .pi / 180) / 2))
        let frameVertical = frameHorizontal / CGFloat(aspectRatio)
        if frameHorizontal.isFinite && frameVertical.isFinite && frameHorizontal > 0 && frameVertical > 0 {
            return CGSize(width: frameHorizontal, height: frameVertical)
        } else {
            return .zero
        }
    }

    static func ratioSize(frameSize: CGSize,
                          frameRatio: CGFloat) -> CGSize {
        let width = frameSize.width
        let height = width / frameRatio
        return CGSize(width: width, height: height)
    }
}

struct ShotOverlay: View {
    let aspectRatio: String
    let filter: String
    let focalLength: String
    let aperture: String
    let shutter: String
    let filmSize: String
    let filmStock: String
    let horizontalFov: CGFloat
    let orientation: UIDeviceOrientation
    let exposureMode: ExposureMode
    let centerMode: ToggleMode
    let symmetryMode: ToggleMode
    
    var body: some View {
        GeometryReader { geo in
            let aspectRatioValue = CameraOptions.aspectRatios.first(where: { $0.label == aspectRatio })?.value ?? CameraOptions.AspectRatio.defaultAspectRatio
            let focalLengthValue = CameraOptions.focalLengths.first(where: { $0.label == focalLength })?.value ?? CameraOptions.FocalLength.defaultFocalLength
            let filmSizeValue = CameraOptions.filmSizes.first(where: { $0.label == filmSize })?.value ?? CameraOptions.FilmSize.defaultFilmSize
            let filmStockValue = CameraOptions.filmStocks.first(where: { $0.label == filmStock })?.value ?? CameraOptions.FilmStock.defaultFilmStock

            let frameSize = ShotHelper.frameSize(
                containerSize: geo.size.switchOrientation(), // to native
                focalLength: focalLengthValue.length,
                aspectRatio: filmSizeValue.aspectRatio,
                width: filmSizeValue.width,
                horizontalFov: horizontalFov
            )
            
            let ratioSize = ShotHelper.ratioSize(
                frameSize: frameSize,
                frameRatio: aspectRatioValue.ratio > 0.0 ? aspectRatioValue.ratio : filmSizeValue.aspectRatio
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
                
                let w = ratioSize.width
                let h = ratioSize.height
                
                if centerMode != .off {
                    Canvas { context, size in
                        context.translateBy(x: size.width / 2, y: size.height / 2)
                        context.rotate(by: .degrees(-90))
                        context.translateBy(x: -ratioSize.width / 2, y: -ratioSize.height / 2)

                        let center = CGPoint(x: w / 2, y: h / 2)
                        let diagonal = sqrt(geo.size.width * geo.size.width + geo.size.height * geo.size.height)
                        let size: CGFloat = diagonal * 0.04
                        
                        var lines = Path()
                        
                        lines.move(to: CGPoint(x: center.x - size / 2, y: center.y))
                        lines.addLine(to: CGPoint(x: center.x + size / 2, y: center.y))

                        lines.move(to: CGPoint(x: center.x, y: center.y - size / 2))
                        lines.addLine(to: CGPoint(x: center.x, y: center.y + size / 2))
                        
                        let opacity = centerMode == .full ? 0.8 : 0.5
                        let lineWidth: CGFloat = centerMode == .full ? 2 : 1

                        context.stroke(lines, with: .color(.white.opacity(opacity)), lineWidth: lineWidth)
                    }
                    .frame(width: targetRatio.width, height: targetRatio.height)
                }
                
                if symmetryMode != .off {
                    Canvas { context, size in
                        context.translateBy(x: size.width / 2, y: size.height / 2)
                        context.rotate(by: .degrees(-90))
                        context.translateBy(x: -ratioSize.width / 2, y: -ratioSize.height / 2)


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

                        let opacity = symmetryMode == .full ? 0.8 : 0.5
                        let lineWidth: CGFloat = symmetryMode == .full ? 2 : 1

                        context.stroke(lines, with: .color(.white.opacity(opacity)), lineWidth: lineWidth)
                        
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
                        
                        context.stroke(extended, with: .color(.white.opacity(opacity)), style: dashStyle)
                    }
                    .frame(width: targetRatio.width, height: targetRatio.height)
                }

                ZStack {
                    Color.black.opacity(0.6)
                        .mask {
                            Rectangle()
                                .fill(Color.white)
                                .overlay(
                                    Rectangle()
                                        .frame(width: targetRatio.width, height: targetRatio.height)
                                        .blendMode(.destinationOut)
                                )
                                .compositingGroup()
                        }
                        .frame(width: targetSize.width, height: targetSize.height)

                    Rectangle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: targetRatio.width, height: targetRatio.height)

                    Rectangle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        .frame(width: targetSize.width, height: targetSize.height)
                }
                
                VStack(spacing: 4) {
                    let filterData = CameraOptions.filters.first(where: { $0.label == filter }) ?? ("-", CameraOptions.Filter.defaultFilter)
                    let colorTempText: String = (filter != "-" && filterData.0 != "-")
                        ? "\(Int(filmStockValue.colorTemperature + filterData.1.colorTemperatureShift))K (\(filter))"
                        : "\(Int(filmStockValue.colorTemperature))K"

                    let exposureText: String = (exposureMode == .autoExposure)
                        ? ", AE"
                        : ", EV: \(Int(filmStockValue.speed)) \(shutter) \(aperture)\(filterData.1.exposureCompensation != 0 ? " (\(String(format: "%+.1f", filterData.1.exposureCompensation)))" : "")"
                    
                    Text(
                        "\(Int(filmSizeValue.width)) mm x \(Int(filmSizeValue.height)) mm, " +
                        "\(String(format: "%.1f", filmSizeValue.angleOfView(focalLength: focalLengthValue.length).horizontal))°, " +
                        "\(colorTempText)\(exposureText)"
                    )
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
    let levelMode: ToggleMode
    
    @State private var smoothedRoll: Double = 0.0
    @State private var smoothedPitch: Double = 0.0
    
    let totalWidthRatio: CGFloat = 0.8
    let gapRatio: CGFloat = 0.05
    let sideRatio: CGFloat = 0.10
    
    var body: some View {
        GeometryReader { geo in
            let alpha = 0.15
            let snappedRoll = (smoothedRoll / 2).rounded() * 2
            let snappedPitch = smoothedPitch.clamped(to: -30...30) // limit range
            
            let isRollAligned = abs(snappedRoll) <= 1
            let isPitchAligned = abs(snappedPitch) <= 1
            
            let fullWidth = geo.size.width * totalWidthRatio
            let gap = fullWidth * gapRatio
            let sideWidth = fullWidth * sideRatio
            let centerWidth = fullWidth - (2 * sideWidth) - (2 * gap)
            
            let maxOffset: CGFloat = 50
            let pitchOffset = CGFloat(snappedPitch / 30) * maxOffset
            
            ZStack {
                let opacity = levelMode == .full ? 0.8 : 0.5
                let lineHeight: CGFloat = levelMode == .full ? 2 : 1

                Rectangle()
                    .fill((isPitchAligned ? Color.green : Color.white).opacity(opacity))
                    .frame(width: sideWidth, height: lineHeight)
                    .position(x: geo.size.width / 2 - (centerWidth / 2 + gap + sideWidth / 2),
                              y: geo.size.height / 2 - pitchOffset)

                Rectangle()
                    .fill((isPitchAligned ? Color.green : Color.white).opacity(opacity))
                    .frame(width: sideWidth, height: lineHeight)
                    .position(x: geo.size.width / 2 + (centerWidth / 2 + gap + sideWidth / 2),
                              y: geo.size.height / 2 - pitchOffset)

                Rectangle()
                    .fill((isRollAligned ? Color.green : Color.white).opacity(opacity))
                    .frame(width: centerWidth, height: lineHeight)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .rotationEffect(.degrees(snappedRoll))
            }
            .rotationEffect(orientation.angle)
            .animation(.easeInOut(duration: 0.15), value: snappedRoll)
            .animation(.easeInOut(duration: 0.15), value: snappedPitch)
            .onChange(of: (levelAngle, pitchAngle)) { _, new in
                smoothedRoll += alpha * (new.0 - smoothedRoll)
                smoothedPitch += alpha * (new.1 - smoothedPitch)
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
    
    @State private var isPressed = false
    
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
    
    @AppStorage("exposureMode") private var exposureMode: ExposureMode = .autoExposure

    
    @ObservedObject private var orientationObserver = OrientationObserver()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            
            CameraPreview(session: cameraModel.session)
               .animation(.easeInOut(duration: 0.3), value: orientationObserver.orientation)
               .ignoresSafeArea()
            
            GeometryReader { geometry in
                ZStack {
                    CameraPreview(session: cameraModel.session)
                        .animation(.easeInOut(duration: 0.3), value: orientationObserver.orientation)
                        .ignoresSafeArea()
                    
                    ShotOverlay(
                        aspectRatio: shot.aspectRatio,
                        filter: shot.lensFilter,
                        focalLength: shot.lensFocalLength,
                        aperture: shot.aperture,
                        shutter: shot.shutter,
                        filmSize: shot.filmSize,
                        filmStock: shot.filmStock,
                        horizontalFov: cameraModel.horizontalFov,
                        orientation: orientationObserver.orientation,
                        exposureMode: exposureMode,
                        centerMode: centerMode,
                        symmetryMode: symmetryMode
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    
                    if levelMode != .off {
                        LevelIndicator(
                            levelAngle: orientationObserver.levelAngle,
                            pitchAngle: orientationObserver.pitchAngle,
                            orientation: orientationObserver.orientation,
                            levelMode: levelMode
                        )
                    }
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { gesture in
                            let tapPoint = gesture.location
                            cameraModel.focus(at: tapPoint, viewSize: UIScreen.main.bounds.size)
                        }
                )
                .allowsHitTesting(true)
                .ignoresSafeArea()
            
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
                adjustExposure()
                adjustWhiteBalance()
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
                Text(exposureLabel(for: exposureMode))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }
            


            let evMode = exposureMode == .evExposure
            let opacity = evMode ? 1.0 : 0.4

            Button(action: {
                if let currentIndex = CameraOptions.filters.firstIndex(where: { $0.label == shot.lensFilter }) {
                    let newIndex = (currentIndex + 1) % CameraOptions.filters.count
                    shot.lensFilter = CameraOptions.filters[newIndex].label
                    adjustExposure()
                    adjustWhiteBalance()
                }
            }) {
                Image(systemName: "camera.filters")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.angle)
            }
            .disabled(!evMode)
            .opacity(opacity)
            
            Button(action: {
                if let currentIndex = CameraOptions.shutters.firstIndex(where: { $0.label == shot.shutter }) {
                    let newIndex = (currentIndex + 1) % CameraOptions.shutters.count
                    shot.shutter = CameraOptions.shutters[newIndex].label
                    adjustEVExposure()
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
                if let currentIndex = CameraOptions.apertures.firstIndex(where: { $0.label == shot.aperture }) {
                    let newIndex = (currentIndex + 1) % CameraOptions.apertures.count
                    shot.aperture = CameraOptions.apertures[newIndex].label
                    adjustEVExposure()
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
        let frameSize = ShotHelper.frameSize(
            containerSize: containerSize.switchOrientation(), // to native
            focalLength: focalLength.length,
            aspectRatio: filmSize.aspectRatio,
            width: filmSize.width,
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
    
    private func lensLabel(for lens: LensType) -> String {
        switch lens {
        case .ultraWide: return "x.5"
        case .wide: return "x1"
        }
    }
    
    private func exposureLabel(for exposure: ExposureMode) -> String {
        switch exposure {
        case .autoExposure: return "AE"
        case .evExposure: return "EV"
        }
    }
    
    private func toggleLens() {
        let lenses: [LensType] = [.ultraWide, .wide]
        if let currentIndex = lenses.firstIndex(of: cameraModel.lensType) {
            let nextIndex = (currentIndex + 1) % lenses.count
            let newLens = lenses[nextIndex]
            selectedLensRawValue = newLens.rawValue
            cameraModel.switchCamera(to: newLens)
            adjustExposure()
            adjustWhiteBalance()

        }
    }
    
    private func toggleExposure() {
        let exposures: [ExposureMode] = [.autoExposure, .evExposure]
        if let currentIndex = exposures.firstIndex(of: exposureMode) {
            let nextIndex = (currentIndex + 1) % exposures.count
            exposureMode = exposures[nextIndex]
            adjustExposure()
        }
    }
    
    func adjustExposure() {
        if exposureMode == .autoExposure {
            adjustAutoExposure()
        } else {
            adjustEVExposure()
        }
    }
    
    func adjustAutoExposure() {
        cameraModel.adjustAutoExposure(ev: 0);
    }
    
    func adjustEVExposure() {
        if exposureMode == .autoExposure {
            return
        }
            
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
        let filter = CameraOptions.filters.first(where: { $0.label == shot.lensFilter })?.value ?? CameraOptions.Filter.defaultFilter
        
        cameraModel.adjustWhiteBalance(kelvin: filmStock.colorTemperature + filter.colorTemperatureShift);
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

extension View {
    func onChange<A: Equatable, B: Equatable>(
        of values: (A, B),
        perform action: @escaping ((A, B), (A, B)) -> Void
    ) -> some View {
        self.onChange(of: values.0) { old, new in
            action((values.0, values.1), (values.0, values.1))
        }
        .onChange(of: values.1) { old, new in
            action((values.0, values.1), (values.0, values.1))
        }
    }
}
