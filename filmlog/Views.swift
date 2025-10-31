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

enum VerticalAlignment {
    case top
    case bottom
}

struct Projection {
    static func projectedFrame(size: CGSize,
                          focalLength: Double,
                          aspectRatio: Double,
                          width: Double,
                          fieldOfView: CGFloat) -> CGSize {
        guard focalLength > 0, fieldOfView > 0 else {
            return .zero
        }
        let hfov = 2 * atan(CGFloat(width) / (2 * focalLength))
        let width = size.width * (tan(hfov / 2) / tan((fieldOfView * .pi / 180) / 2))
        let height = width / CGFloat(aspectRatio)
        if width.isFinite && height.isFinite && width > 0 && height > 0 {
            return CGSize(width: width, height: height)
        } else {
            return .zero
        }
    }

    static func frameForAspectRatio(size: CGSize, aspectRatio: CGFloat) -> CGSize {
        let sizeAspectRatio = size.width / size.height
        if sizeAspectRatio > aspectRatio {
            let height = size.height
            let width = height * aspectRatio
            return CGSize(width: width, height: height)
        } else {
            let width = size.width
            let height = width / aspectRatio
            return CGSize(width: width, height: height)
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

struct CenterView: View {
    let centerMode: ToggleMode
    let size: CGSize
    let geometry: GeometryProxy

    var body: some View {
        Canvas { context, canvasSize in
            let width = canvasSize.width
            let height = canvasSize.height
            
            let center = CGPoint(x: width / 2, y: height / 2)
            let diagonal = sqrt(geometry.size.width * geometry.size.width + // based on geomtry
                                geometry.size.height * geometry.size.height)
            let markerSize: CGFloat = diagonal * 0.04

            var lines = Path()
            lines.move(to: CGPoint(x: center.x - markerSize / 2, y: center.y))
            lines.addLine(to: CGPoint(x: center.x + markerSize / 2, y: center.y))
            lines.move(to: CGPoint(x: center.x, y: center.y - markerSize / 2))
            lines.addLine(to: CGPoint(x: center.x, y: center.y + markerSize / 2))

            let opacity = centerMode == .full ? 0.8 : 0.5
            let lineWidth: CGFloat = centerMode == .full ? 2 : 1

            context.stroke(lines, with: .color(.white.opacity(opacity)), lineWidth: lineWidth)
        }
        .frame(width: size.width, height: size.height)
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
        .onChange(of: selectedMode) { newValue, _ in
            if let mode = newValue {
                internalSelectedMode = mode
            } else {
                internalSelectedMode = ""
            }
        }
    }
}

struct ControlButton {
    let icon: String
    let label: String
    let action: () -> Void
    var background: Color = Color.black.opacity(0.6)
    var rotation: Angle = .zero
}

struct ControlsView<Overlay: View>: View {
    @Binding var isVisible: Bool
    let buttons: [ControlButton]
    var showOverlay: Bool = false
    @ViewBuilder var overlay: () -> Overlay

    private let height: CGFloat = 125
    init(
        isVisible: Binding<Bool>,
        buttons: [ControlButton],
        showOverlay: Bool = false,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self._isVisible = isVisible
        self.buttons = buttons
        self.showOverlay = showOverlay
        self.overlay = overlay
    }

    var body: some View {
        if isVisible {
            ZStack {
                if showOverlay {
                    VStack {
                        Spacer()
                        overlay()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(1)
                        Spacer()
                    }
                    .ignoresSafeArea()
                }
                VStack(spacing: 0) {
                    Spacer()
                    ZStack {
                        Color.clear
                            .frame(height: height)
                        HStack(spacing: 32) {
                            ForEach(buttons, id: \.label) { button in
                                Button(action: button.action) {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Circle()
                                                .fill(button.background)
                                                .frame(width: 48, height: 48)
                                            
                                            Image(systemName: button.icon)
                                                .font(.system(size: 20, weight: .medium))
                                                .foregroundColor(.white)
                                                .frame(width: 48, height: 48)
                                                .background(button.background)
                                                .clipShape(Circle())
                                                .animation(.easeInOut(duration: 0.25), value: button.background)
                                        }
                                        .contentShape(Circle())
                                        .animation(.easeInOut(duration: 0.25), value: button.background)

                                        Text(button.label)
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                    }
                                    .frame(width: 64)
                                    .rotationEffect(button.rotation)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .offset(y: -10)
                    }
                }
            }
            .ignoresSafeArea()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

extension ControlsView where Overlay == EmptyView {
    init(
        isVisible: Binding<Bool>,
        buttons: [ControlButton]
    ) {
        self.init(isVisible: isVisible, buttons: buttons, showOverlay: false) { EmptyView() }
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

struct LevelIndicatorView: View {
    var level: OrientationUtils.Level
    let orientation: UIDeviceOrientation
    let levelMode: ToggleMode
    
    let totalWidthRatio: CGFloat = 0.8
    let gapRatio: CGFloat = 0.05
    let sideRatio: CGFloat = 0.10
    
    var body: some View {
        GeometryReader { geo in
            let normalized = OrientationUtils.normalizeLevel(from: level)
            
            let isRollAligned = abs(normalized.roll) <= 1
            let isTiltAligned = abs(normalized.tilt) <= 1
            
            let fullWidth = geo.size.width * totalWidthRatio
            let gap = fullWidth * gapRatio
            let sideWidth = fullWidth * sideRatio
            let centerWidth = fullWidth - (2 * sideWidth) - (2 * gap)
            
            let maxOffset: CGFloat = 50
            let tiltOffset = CGFloat(normalized.tilt / 30) * maxOffset
            
            ZStack {
                let opacity = levelMode == .full ? 0.8 : 0.5
                let lineHeight: CGFloat = levelMode == .full ? 2 : 1

                Rectangle()
                    .fill((isTiltAligned ? Color.green : Color.white).opacity(opacity))
                    .frame(width: sideWidth, height: lineHeight)
                    .position(
                        x: geo.size.width / 2 - (centerWidth / 2 + gap + sideWidth / 2),
                        y: geo.size.height / 2 - tiltOffset
                    )

                Rectangle()
                    .fill((isTiltAligned ? Color.green : Color.white).opacity(opacity))
                    .frame(width: sideWidth, height: lineHeight)
                    .position(
                        x: geo.size.width / 2 + (centerWidth / 2 + gap + sideWidth / 2),
                        y: geo.size.height / 2 - tiltOffset
                    )

                Rectangle()
                    .fill((isRollAligned ? Color.green : Color.white).opacity(opacity))
                    .frame(width: centerWidth, height: lineHeight)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .rotationEffect(.degrees(normalized.roll))
            }
            .rotationEffect(orientation.toLandscape)
            .animation(.easeInOut(duration: 0.15), value: normalized.roll)
            .animation(.easeInOut(duration: 0.15), value: normalized.tilt)
            
            ZStack {
                VStack(spacing: 4) {
                    Text("Roll: \(Int(normalized.roll))° · Tilt: \(Int(normalized.tilt))°")
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .rotationEffect(orientation.toLandscape)
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

struct MaskView: View {
    let frameSize: CGSize
    let aspectSize: CGSize
    let inner: CGFloat
    let outer: CGFloat
    let geometry: GeometryProxy
    
    var body: some View {
        let width = geometry.size.width
        let height = geometry.size.height
        
        ZStack {
            Color(Color.black)
                .opacity(outer)
                .mask(
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: geometry.size))
                        p.addRect(CGRect(
                            x: (width - frameSize.width) / 2,
                            y: (height - frameSize.height) / 2,
                            width: frameSize.width,
                            height: frameSize.height)
                        )
                    }
                    .fill(style: FillStyle(eoFill: true))
                )

            Color(Color.black)
                .opacity(inner)
                .mask(
                    Path { p in
                        p.addRect(CGRect(
                            x: (width - frameSize.width) / 2,
                            y: (height - frameSize.height) / 2,
                            width: frameSize.width,
                            height: frameSize.height)
                        )
                        p.addRect(CGRect(
                            x: (width - aspectSize.width) / 2,
                            y: (height - aspectSize.height) / 2,
                            width: aspectSize.width,
                            height: aspectSize.height)
                        )
                    }
                    .fill(style: FillStyle(eoFill: true))
                )

            Rectangle()
                .stroke(.gray, lineWidth: 1)
                .frame(width: frameSize.width, height: frameSize.height)
                .position(x: width / 2, y: height / 2)

            Rectangle()
                .stroke(.blue, lineWidth: 2)
                .frame(width: aspectSize.width, height: aspectSize.height)
                .position(x: width / 2, y: height / 2)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

struct SymmetryView: View {
    let symmetryMode: ToggleMode
    let size: CGSize
    let geometry: GeometryProxy
    
    var body: some View {
        Canvas { context, canvasSize in
            let width = canvasSize.width
            let height = canvasSize.height
            
            let d = CGSize(width: width - 1, height: height - 1)
            let angle = .pi / 2 - atan(d.width / d.height)
            let length = d.height * tan(angle)
            let hypo = d.height * cos(angle)
            let cross = CGSize(width: hypo * sin(angle), height: hypo * cos(angle))
            
            var lines = Path()
            lines.move(to: .zero) // diagonals
            lines.addLine(to: CGPoint(x: width, y: height))
            
            lines.move(to: CGPoint(x: 0, y: height))
            lines.addLine(to: CGPoint(x: width, y: 0))
            
            lines.move(to: .zero) // reciprocals
            lines.addLine(to: CGPoint(x: length, y: height))
            
            lines.move(to: CGPoint(x: 0, y: height))
            lines.addLine(to: CGPoint(x: length, y: 0))
            
            lines.move(to: CGPoint(x: width, y: 0))
            lines.addLine(to: CGPoint(x: width - length, y: height))
            
            lines.move(to: CGPoint(x: width, y: height))
            lines.addLine(to: CGPoint(x: width - length, y: 0))
            
            lines.move(to: CGPoint(x: cross.width, y: 0)) // cross
            lines.addLine(to: CGPoint(x: cross.width, y: height))
            
            lines.move(to: CGPoint(x: width - cross.width, y: 0))
            lines.addLine(to: CGPoint(x: width - cross.width, y: height))
            
            lines.move(to: CGPoint(x: 0, y: cross.height))
            lines.addLine(to: CGPoint(x: width, y: cross.height))
            
            lines.move(to: CGPoint(x: 0, y: height - cross.height))
            lines.addLine(to: CGPoint(x: width, y: height - cross.height))
            
            let opacity = symmetryMode == .full ? 0.8 : 0.5
            let lineWidth: CGFloat = symmetryMode == .full ? 2 : 1
            
            context.stroke(lines, with: .color(.white.opacity(opacity)), lineWidth: lineWidth)
        }
        .frame(width: size.width, height: size.height)
        .drawingGroup() 
    }
}

struct TextView: View {
    let text: String
    let alignment: VerticalAlignment
    let orientation: UIDeviceOrientation
    let geometry: GeometryProxy

    var body: some View {
        VStack(spacing: 4) {
            Text(text)
            .font(.caption2)
            .padding(4)
            .background(Color.black.opacity(0.6))
            .foregroundColor(.white)
            .cornerRadius(4)
            .rotationEffect(orientation.toLandscape)
        }
        .offset(offset(for: alignment, orientation: orientation, geo: geometry))
    }

    private func offset(
        for alignment: VerticalAlignment,
        orientation: UIDeviceOrientation,
        geo: GeometryProxy
    ) -> CGSize {
        let verticalOffset: CGFloat = alignment == .top
            ? -geo.size.height / 2 + 120
            :  geo.size.height / 2 - 120

        var offset = CGSize(width: 0, height: verticalOffset)

        switch orientation {
        case .landscapeLeft:
            offset = CGSize(width: geo.size.width / 2 - 25,
                            height: 0)
            if alignment == .bottom {
                offset.width *= -1
            }
        case .landscapeRight:
            offset = CGSize(width: -geo.size.width / 2 + 25,
                            height: 0)
            if alignment == .bottom {
                offset.width *= -1
            }
        case .portraitUpsideDown:
            offset.height *= -1
        default:
            break
        }
        return offset
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
                let scaled = image.resize(maxDimension: 512)
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

class OrientationObserver: ObservableObject {
    @Published var orientation: UIDeviceOrientation = UIDevice.current.orientation
    @Published var level = OrientationUtils.Level(roll: 0.0, tilt: 0.0)
    
    private var smoothedRoll: Double = 0.0
    private var smoothedTilt: Double = 0.0
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
                let tilt = atan2(-g.z, sqrt(g.x * g.x + g.y * g.y)) * 180 / .pi
                self.smoothedRoll += self.alpha * (roll - self.smoothedRoll)
                self.smoothedTilt += self.alpha * (tilt - self.smoothedTilt)
                
                DispatchQueue.main.async {
                    self.level = OrientationUtils.Level(roll: self.smoothedRoll, tilt: self.smoothedTilt)
                }
            }
        }
    }
}
