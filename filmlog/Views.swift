// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI
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

enum CameraMode: String, CaseIterable {
    case auto = "AE"
    case manual = "EV"
}

struct LevelAndPitch: Equatable {
    var roll: Double
    var pitch: Double
}

class OrientationObserver: ObservableObject {
    @Published var orientation: UIDeviceOrientation = UIDevice.current.orientation
    @Published var levelAndPitch = LevelAndPitch(roll: 0.0, pitch: 0.0)
    
    private var smoothedRoll: Double = 0.0
    private var smoothedPitch: Double = 0.0
    private let alpha = 0.15
    
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
                
                let roll = angle
                let pitch = atan2(-g.z, sqrt(g.x * g.x + g.y * g.y)) * 180 / .pi
                self.smoothedRoll += self.alpha * (roll - self.smoothedRoll)
                self.smoothedPitch += self.alpha * (pitch - self.smoothedPitch)
                
                DispatchQueue.main.async {
                    self.levelAndPitch = LevelAndPitch(roll: self.smoothedRoll, pitch: self.smoothedPitch)
                }
            }
        }
    }
}

struct ExportFileView: UIViewControllerRepresentable {
    let imageData: Data
    let suggestedName: String

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
        try? imageData.write(to: tempURL)

        let picker = UIDocumentPickerViewController(forExporting: [tempURL])
        picker.shouldShowFileExtensions = true
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

struct FrameHelper {
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

struct FrameOverlay: View {
    let aspectRatio: String
    let colorFilter: String
    let ndFilter: String
    let focalLength: String
    let aperture: String
    let shutter: String
    let filmSize: String
    let filmStock: String
    let horizontalFov: CGFloat
    let orientation: UIDeviceOrientation
    let cameraMode: CameraMode
    let centerMode: ToggleMode
    let symmetryMode: ToggleMode
    let showOnlyText: Bool
    
    var body: some View {
        GeometryReader { geo in
            let aspectRatioValue = CameraUtils.aspectRatios.first(where: { $0.label == aspectRatio })?.value ?? CameraUtils.AspectRatio.defaultAspectRatio
            let focalLengthValue = CameraUtils.focalLengths.first(where: { $0.label == focalLength })?.value ?? CameraUtils.FocalLength.defaultFocalLength
            let filmSizeValue = CameraUtils.filmSizes.first(where: { $0.label == filmSize })?.value ?? CameraUtils.FilmSize.defaultFilmSize
            let filmStockValue = CameraUtils.filmStocks.first(where: { $0.label == filmStock })?.value ?? CameraUtils.FilmStock.defaultFilmStock

            let frameSize = FrameHelper.frameSize(
                containerSize: geo.size.switchOrientation(), // to native
                focalLength: focalLengthValue.length,
                aspectRatio: filmSizeValue.aspectRatio,
                width: filmSizeValue.width,
                horizontalFov: horizontalFov
            )
            
            let ratioSize = FrameHelper.ratioSize(
                frameSize: frameSize,
                frameRatio: aspectRatioValue.ratio > 0.0 ? aspectRatioValue.ratio : filmSizeValue.aspectRatio
            )
            
            let targetSize = frameSize.switchOrientation() // to potrait
            let targetRatio = ratioSize.switchOrientation() // to potrait
            
            
            ZStack {
                
                if !showOnlyText {
                    
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
                    
                }
                
                VStack(spacing: 4) {
                    let colorFilterData = CameraUtils.colorFilters.first(where: { $0.label == colorFilter }) ?? ("-", CameraUtils.Filter.defaultFilter)
                    let colorTempText: String = (colorFilter != "-" && colorFilterData.0 != "-")
                        ? "\(Int(filmStockValue.colorTemperature + colorFilterData.1.colorTemperatureShift))K (\(colorFilter))"
                        : "Auto K"

                    let ndFilterData = CameraUtils.ndFilters.first(where: { $0.label == ndFilter }) ?? ("-", CameraUtils.Filter.defaultFilter)
                    let exposureCompensation = colorFilterData.value.exposureCompensation + ndFilterData.value.exposureCompensation
                    let exposureText: String = (cameraMode == .auto)
                        ? ", Auto"
                        : ", M: \(Int(filmStockValue.speed)) \(shutter) \(aperture)\(exposureCompensation != 0 ? " (\(String(format: "%+.1f", exposureCompensation)))" : "")"

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
    var levelAndPitch: LevelAndPitch
    let orientation: UIDeviceOrientation
    let levelMode: ToggleMode
    
    let totalWidthRatio: CGFloat = 0.8
    let gapRatio: CGFloat = 0.05
    let sideRatio: CGFloat = 0.10
    
    var body: some View {
        GeometryReader { geo in
            let snappedRoll = (levelAndPitch.roll / 2).rounded() * 2
            let snappedPitch = levelAndPitch.pitch.clamped(to: -30...30)
            
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

struct CategoryPickerView: View {
    @Binding var selectedCategories: Set<Category>
    let allCategories: [Category]

    var body: some View {
        List(allCategories) { category in
            CategoryRow(category: category, isSelected: selectedCategories.contains(category)) {
                if selectedCategories.contains(category) {
                    selectedCategories.remove(category)
                } else {
                    selectedCategories.insert(category)
                }
            }
        }
    }
}

struct CategoryRow: View {
    let category: Category
    let isSelected: Bool
    let toggleSelection: () -> Void

    var body: some View {
        Button(action: toggleSelection) {
            HStack {
                Text(category.name)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}

struct CircularPickerView: View {
    let selectedLabel: String
    let labels: [String]
    let onChange: (String) -> Void
    let onRelease: (String) -> Void

    var modeLabels: [String]? = nil
    var selectedMode: String? = nil
    var onModeSelect: ((String) -> Void)? = nil

    @State private var currentIndex: Int = 0
    @State private var baseAngle: Angle = .zero
    @State private var internalSelectedMode: String = ""

    private var totalSteps: Int { labels.count }

    private func angle(for index: Int) -> Angle {
        let stepAngle = 360.0 / Double(totalSteps)
        return .degrees(Double(index) * stepAngle)
    }

    private func angleDelta(from start: Double, to end: Double) -> Double {
        var delta = end - start
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    private func index(for angle: Angle) -> Int {
        let normalizedDegrees = (angle.degrees + 360).truncatingRemainder(dividingBy: 360)
        let stepAngle = 360.0 / Double(totalSteps)
        let rawIndex = Int((normalizedDegrees / stepAngle).rounded()) % totalSteps
        return rawIndex
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            VStack(spacing: 16) {
                ZStack {
                    ForEach(labels.indices, id: \.self) { i in
                        let tickAngle = angle(for: i)
                        Rectangle()
                            .fill(Color.primary)
                            .frame(width: 2, height: 10)
                            .offset(y: -size / 2 + 15)
                            .rotationEffect(tickAngle)
                    }

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 42, height: 42)
                        .offset(y: -size / 2 + 20)
                        .rotationEffect(angle(for: currentIndex))

                    Text(labels[currentIndex])
                        .font(.title2).bold()
                }
                .frame(width: size, height: size)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let startVector = CGVector(dx: value.startLocation.x - center.x,
                                                       dy: value.startLocation.y - center.y)
                            let currentVector = CGVector(dx: value.location.x - center.x,
                                                         dy: value.location.y - center.y)

                            let startDegrees = atan2(startVector.dy, startVector.dx) * 180 / .pi
                            let currentDegrees = atan2(currentVector.dy, currentVector.dx) * 180 / .pi
                            let deltaDegrees = angleDelta(from: startDegrees, to: currentDegrees)
                            let delta = Angle(degrees: deltaDegrees)

                            let totalAngle = baseAngle + delta
                            let index = index(for: totalAngle)

                            if index != currentIndex {
                                currentIndex = index
                                onChange(labels[index])
                            }
                        }
                        .onEnded { _ in
                            baseAngle = angle(for: currentIndex)
                            onRelease(labels[currentIndex])
                        }
                )

                if let modeLabels = modeLabels, !modeLabels.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(modeLabels, id: \.self) { label in
                            Button(action: {
                                internalSelectedMode = label
                                onModeSelect?(label)
                            }) {
                                Text(label)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        internalSelectedMode == label
                                        ? Color.accentColor
                                        : Color.clear
                                    )
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            if let idx = labels.firstIndex(of: selectedLabel) {
                currentIndex = idx
                baseAngle = angle(for: idx)
            } else {
                currentIndex = 0
                baseAngle = .zero
            }

            if let mode = selectedMode {
                internalSelectedMode = mode
            } else {
                internalSelectedMode = ""
            }
        }
        .onChange(of: selectedLabel) { newValue, _ in
            if let idx = labels.firstIndex(of: newValue) {
                currentIndex = idx
                baseAngle = angle(for: idx)
            }
        }
        .onChange(of: selectedMode) { newValue, _ in
            if let mode = newValue {
                internalSelectedMode = mode
            } else {
                internalSelectedMode = ""
            }
        }
        .onChange(of: labels) { _, _ in
            if currentIndex >= labels.count {
                currentIndex = 0
                baseAngle = .zero
            }
        }
    }
}

struct PhotoPickerView: View {
    var image: UIImage?
    var label: String
    var isLocked: Bool = false
    var onImagePicked: (UIImage) -> Void   // not Data

    @State private var showCamera = false
    @State private var showFullImage = false
    @State private var selectedItem: PhotosPickerItem? = nil

    var body: some View {
        VStack(spacing: 8) {
            if let uiImage = image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .clipped()
                    .cornerRadius(10)
                    .onTapGesture {
                        showFullImage = true
                    }
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 180)
                    .overlay(Text("No image").foregroundColor(.gray))
                    .cornerRadius(10)
            }

            if !isLocked {
                HStack(spacing: 16) {
                    Button {
                        showCamera = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "camera")
                                .foregroundColor(.white)
                            Text("Take photo")
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo")
                                .foregroundColor(.white)
                            Text("From library")
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                let scaled = image.resized(maxDimension: 512)
                onImagePicked(scaled)
                showCamera = false
            }
        }
        .fullScreenCover(isPresented: $showFullImage) {
            if let uiImage = image {
                FullScreenImageView(image: uiImage)
            }
        }
        .onChange(of: selectedItem) {
            if let selectedItem {
                Task {
                    if let data = try? await selectedItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        onImagePicked(uiImage)
                    }
                }
            }
        }
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
