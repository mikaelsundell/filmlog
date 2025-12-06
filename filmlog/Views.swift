// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI
import Combine
import CoreMotion
import UIKit

enum ToggleMode: Int, CaseIterable {
    case off = 0
    case partial = 1
    case full = 2
    var color: Color {
        switch self {
        case .off: return Color.clear
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

struct TagPickerView: View {
    @Binding var selectedTags: Set<Tag>
    let allTags: [Tag]

    var body: some View {
        List(allTags) { tag in
            TagRow(tag: tag, isSelected: selectedTags.contains(tag)) {
                if selectedTags.contains(tag) {
                    selectedTags.remove(tag)
                } else {
                    selectedTags.insert(tag)
                }
            }
        }
    }
}

struct TagRow: View {
    let tag: Tag
    let isSelected: Bool
    let toggleSelection: () -> Void

    var body: some View {
        Button(action: toggleSelection) {
            HStack {
                Text(tag.name)
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
    let action: () -> Void
    var foreground: Color = .white
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
                        HStack(spacing: 8) {
                            ForEach(buttons.indices, id: \.self) { index in
                                let button = buttons[index]
                                Button(action: button.action) {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Circle()
                                                .fill(button.background)
                                                .frame(width: 32, height: 32)

                                            Image(systemName: button.icon)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(button.foreground)
                                        }
                                        .animation(.easeInOut(duration: 0.25), value: button.background)
                                    }
                                    .frame(width: 52)
                                    .rotationEffect(button.rotation)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 32)
                                .fill(Color.black.opacity(0.4))
                                .padding(.horizontal, -12)
                                .padding(.vertical, -8)
                        )
                        .padding(.bottom, 42)
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

class FitAwareScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var width: CGFloat = 0
        var height: CGFloat = 0
        var currentLineWidth: CGFloat = 0
        var currentLineHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentLineWidth + size.width + spacing > maxWidth {
                // move to next line
                height += currentLineHeight + lineSpacing
                currentLineWidth = 0
                currentLineHeight = 0
            }
            currentLineWidth += size.width + spacing
            currentLineHeight = max(currentLineHeight, size.height)
        }
        height += currentLineHeight
        width = maxWidth
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var currentLineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += currentLineHeight + lineSpacing
                currentLineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            currentLineHeight = max(currentLineHeight, size.height)
        }
    }
}

struct MetadataView: View {
    let imageData: ImageData?
    let metadata: [String: DataValue]

    init(imageData: ImageData?) {
        self.imageData = imageData
        self.metadata = imageData?.metadata ?? [:]
    }

    var body: some View {
        Group {
            if !metadata.isEmpty {
                let aperture = CameraUtils.aperture(for: stringValue("aperture"))
                let colorFilter = CameraUtils.colorFilter(for: stringValue("colorFilter"))
                let ndFilter = CameraUtils.ndFilter(for: stringValue("ndFilter"))
                let filmSize = CameraUtils.filmSize(for: stringValue("filmSize"))
                let filmStock = CameraUtils.filmStock(for: stringValue("filmStock"))
                let shutter = CameraUtils.shutter(for: stringValue("shutter"))
                let focalLength = CameraUtils.focalLength(for: stringValue("focalLength"))

                let exposureCompensation = colorFilter.exposureCompensation + ndFilter.exposureCompensation
                let exposureText: String =
                    "\(aperture.name) \(shutter.name)" +
                    (exposureCompensation != 0
                        ? " (\(exposureCompensation >= 0 ? "+" : "")\(String(format: "%.1f", exposureCompensation)))"
                        : "")
                
                let infoText =
                    "\(Int(filmSize.width))x\(Int(filmSize.height))mm " +
                    "(\(String(format: "%.1f", filmSize.angleOfView(focalLength: focalLength.length).horizontal))°) " +
                    "· \(String(format: "%.0f", filmStock.speed)) · \(exposureText)"
                
                let colorText: String =
                    "\(Int(filmStock.colorTemperature))K" +
                    (colorFilter.colorTemperatureShift != 0
                        ? " (\(colorFilter.colorTemperatureShift >= 0 ? "+" : "")\(colorFilter.colorTemperatureShift))"
                        : "")

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Metadata – \(focalLength.name.isEmpty ? "—" : focalLength.name)\(stringValue("aspectRatio") == "-" || stringValue("aspectRatio").isEmpty ? "" : " (\(stringValue("aspectRatio")))")")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Divider()
                        .frame(maxWidth: .infinity)
                        .overlay(Color.white.opacity(0.1))

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(infoText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Spacer()
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(colorText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Spacer()
                    }
                    
                    if let roll = doubleValue("deviceRoll"),
                       let tilt = doubleValue("deviceTilt") {
                        HStack(spacing: 6) {
                            Text("Roll: \(Int(roll))° · Tilt: \(Int(tilt))°")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }

                    if let lat = doubleValue("latitude"),
                       let lon = doubleValue("longitude") {
                        let location = (latitude: lat, longitude: lon)
                        
                        HStack(spacing: 6) {
                            Text(String(format: "Lat: %.4f, Lon: %.4f", location.latitude, location.longitude))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                openInMaps(latitude: location.latitude, longitude: location.longitude)
                            } label: {
                                Image(systemName: "map")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.1))
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
    }
    
    private func openInMaps(latitude: Double, longitude: Double) {
        if let url = URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)") {
            UIApplication.shared.open(url)
        }
    }

    private func stringValue(_ key: String) -> String {
        if case let .string(value) = metadata[key] {
            return value
        }
        return ""
    }

    private func doubleValue(_ key: String) -> Double? {
        if case let .double(value) = metadata[key] {
            return value
        }
        return nil
    }

    private func intValue(_ key: String) -> Int {
        if case let .double(value) = metadata[key] {
            return Int(value)
        }
        return 0
    }
}

extension View {
    func asArray() -> [AnyView] { [AnyView(self)] }
}

extension TupleView {
    func asArray() -> [AnyView] {
        Mirror(reflecting: self).children.compactMap { $0.value as? AnyView }
    }
}

struct AspectRatioView: View {
    let frameSize: CGSize
    let aspectSize: CGSize
    let radius: CGFloat
    let geometry: GeometryProxy
    
    var body: some View {
        let width = geometry.size.width
        let height = geometry.size.height
        ZStack {
            if !frameSize.isApproximatelyEqual(to: aspectSize, tolerance: 1.0) {
                Rectangle()
                    .stroke(.blue, lineWidth: 1)
                    .frame(width: aspectSize.width, height: aspectSize.height)
                    .position(x: width / 2, y: height / 2)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
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
    let radius: CGFloat
    let geometry: GeometryProxy
    
    var body: some View {
        let width = geometry.size.width
        let height = geometry.size.height
        let inner = 0.4
        let outer = 0.090
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
            
            if !frameSize.isApproximatelyEqual(to: aspectSize, tolerance: 1.0) {
                Rectangle()
                    .stroke(.blue, lineWidth: 1)
                    .frame(width: aspectSize.width, height: aspectSize.height)
                    .position(x: width / 2, y: height / 2)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

struct GridView: View {
    let gridMode: ToggleMode
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
            
            let opacity = gridMode == .full ? 0.8 : 0.4
            let lineWidth: CGFloat = gridMode == .full ? 2 : 1
            
            context.stroke(lines, with: .color(.white.opacity(opacity)), lineWidth: lineWidth)
        }
        .frame(width: size.width, height: size.height)
        .drawingGroup() 
    }
}

struct OverlayImageView: View {
    let image: UIImage
    let aspectSize: CGSize
    let geometry: GeometryProxy
    let cornerRadius: CGFloat
    var opacity: Double = 0.5
    var blendMode: BlendMode = .normal

    var body: some View {
        let width = geometry.size.width
        let height = geometry.size.height
        let imageSize = image.size
        let size = imageSize.isLandscape ? imageSize.switchOrientation() : imageSize // to potrait
        
        let padding: CGFloat = 0
        let iw = aspectSize.width - padding * 2
        let ih = aspectSize.height - padding * 2
        let fit = min(iw / size.width, ih / size.height)
        
        let rotation: Angle = imageSize.isLandscape ? .degrees(90) : .degrees(0)
        
        Image(uiImage: image)
            .scaleEffect(fit)
            .rotationEffect(rotation)
            .frame(width: aspectSize.width, height: aspectSize.height)
            .clipped()
            .cornerRadius(cornerRadius)
            .position(x: width / 2, y: height / 2)
            .opacity(opacity)
            .blendMode(blendMode)
            .contentShape(Rectangle())
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

class MotionObserver: ObservableObject {
    @Published var orientation: UIDeviceOrientation = UIDevice.current.orientation
    @Published var level = OrientationUtils.Level(roll: 0.0, tilt: 0.0)
    
    private var smoothedRoll: Double = 0.0
    private var smoothedTilt: Double = 0.0
    private let alpha = 0.15
    
    private var isRunning = false
    
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
        guard !isRunning else { return }
                isRunning = true
        
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
    
    func stopMotionUpdates() {
        guard isRunning else { return }
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
    }
    
}

class OrientationObserver: ObservableObject {
    @Published var orientation: UIDeviceOrientation = UIDevice.current.orientation
    
    private var cancellable: AnyCancellable?
    
    init() {
        cancellable = NotificationCenter.default.publisher(
            for: UIDevice.orientationDidChangeNotification
        )
        .compactMap { _ in
            let o = UIDevice.current.orientation
            return o.isValidInterfaceOrientation ? o : nil
        }
        .removeDuplicates()
        .sink { [weak self] newOrientation in
            self?.orientation = newOrientation
        }
    }
}

struct PagedImageViewer: UIViewControllerRepresentable {
    let images: [UIImage]

    @Binding var index: Int
    @Binding var showControls: Bool
    @Binding var viewSize: CGSize
    @Binding var viewFit: Bool
    @Binding var viewReady: Bool
    
    @State private var pageSizes: [Int: CGSize] = [:]

    init(images: [UIImage],
         index: Binding<Int>,
         showControls: Binding<Bool>,
         viewSize: Binding<CGSize>,
         viewFit: Binding<Bool>,
         viewReady: Binding<Bool>) {
        self.images = images
        self._index = index
        self._showControls = showControls
        self._viewSize = viewSize
        self._viewFit = viewFit
        self._viewReady = viewReady
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator

        if let scrollView = controller.view.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
            scrollView.delegate = context.coordinator
            context.coordinator.pageScrollView = scrollView
        }

        let initialVC = context.coordinator.makePageController(for: index)
        controller.setViewControllers([initialVC], direction: .forward, animated: false)

        DispatchQueue.main.async {
            viewReady = true
        }
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        if let currentVC = controller.viewControllers?.first,
           currentVC.view.tag != index {
            let newVC = context.coordinator.makePageController(for: index)
            controller.setViewControllers([newVC], direction: .forward, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIScrollViewDelegate {
        var parent: PagedImageViewer
        weak var pageScrollView: UIScrollView?

        init(_ parent: PagedImageViewer) {
            self.parent = parent
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.viewReady = false
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            DispatchQueue.main.async {
                if let saved = self.parent.pageSizes[self.parent.index] {
                    self.parent.viewSize = saved
                }
                self.parent.viewReady = true
            }
        }

        func makePageController(for index: Int) -> UIViewController {
            let vc = UIHostingController(
                rootView:
                    ZoomableScrollView(
                        image: parent.images[index],
                        pageIndex: index,
                        currentIndex: parent.$index,
                        showControls: parent.$showControls,
                        viewFit: parent.$viewFit,
                        viewReady: parent.$viewReady,
                        viewSize: .constant(.zero),   // <- no longer used
                        onInitialSize: { size in
                            if self.parent.pageSizes[index] == nil {
                                self.parent.pageSizes[index] = size
                            }
                            if index == self.parent.index {
                                self.parent.viewSize = size
                            }
                        }
                    )
                    .ignoresSafeArea()
            )

            vc.view.tag = index
            return vc
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController)
            -> UIViewController? {
            guard parent.images.count > 1 else { return nil }
            guard let index = index(of: viewController) else { return nil }

            let prev = (index - 1 + parent.images.count) % parent.images.count
            return makePageController(for: prev)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController)
            -> UIViewController? {
            guard parent.images.count > 1 else { return nil }
            guard let index = index(of: viewController) else { return nil }

            let next = (index + 1) % parent.images.count
            return makePageController(for: next)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {

            if completed,
               let visible = pageViewController.viewControllers?.first,
               let newIndex = index(of: visible) {

                parent.index = newIndex

                DispatchQueue.main.async {
                    if let saved = self.parent.pageSizes[newIndex] {
                        self.parent.viewSize = saved
                    }
                }
            }
        }

        private func index(of vc: UIViewController) -> Int? {
            vc.view.tag
        }
    }
}

struct VisualEffectView: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage
    let pageIndex: Int
    
    @Binding var currentIndex: Int
    @Binding var showControls: Bool
    @Binding var viewFit: Bool
    @Binding var viewReady: Bool
    @Binding var viewSize: CGSize
    
    let onInitialSize: (CGSize) -> Void
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = FitAwareScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black

        // we force landscape no matter if the image is
        // in potrait or landscape orientation.
        
        let raw = image.asLandscape ?? image
        let imageView = UIImageView(image: raw)
        
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.layer.cornerRadius = 8
        imageView.layer.masksToBounds = true
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap))
        tap.numberOfTapsRequired = 1
        scrollView.addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        tap.require(toFail: doubleTap)

        scrollView.onLayout = { [weak scrollView] in
            guard let scrollView else { return }
            context.coordinator.performInitialFit(in: scrollView)
        }

        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        if context.coordinator.hasInitialFit && pageIndex != currentIndex {
            return
        }

        guard let imageView = context.coordinator.imageView else { return }
        let size = imageView.frame.size

        if size.width < 10 || size.height < 10 {
            return
        }

        if size.width == scrollView.bounds.width &&
           size.height == scrollView.bounds.height {
            return
        }
        
        if context.coordinator.hasInitialFit == false {
            return
        }

        if viewReady && pageIndex == currentIndex {
            viewSize = size
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pageIndex: pageIndex,
            showControls: $showControls,
            viewSize: $viewSize,
            viewFit: $viewFit,
            viewReady: $viewReady,
            onInitialSize: onInitialSize
        )
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        let pageIndex: Int

        @Binding var showControls: Bool
        @Binding var viewSize: CGSize
        @Binding var viewFit: Bool
        @Binding var viewReady: Bool

        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?

        var hasInitialFit: Bool = false
        
        let onInitialSize: (CGSize) -> Void  // <-- store callback here

        init(pageIndex: Int,
             showControls: Binding<Bool>,
             viewSize: Binding<CGSize>,
             viewFit: Binding<Bool>,
             viewReady: Binding<Bool>,
             onInitialSize: @escaping (CGSize) -> Void) {
            self.pageIndex = pageIndex
            _showControls = showControls
            _viewSize = viewSize
            _viewFit = viewFit
            _viewReady = viewReady
            self.onInitialSize = onInitialSize
        }

        func performInitialFit(in scrollView: UIScrollView) {
            guard !hasInitialFit else { return }
            guard let imageView, let image = imageView.image else { return }

            let scrollSize = scrollView.bounds.size
            guard scrollSize.width > 0, scrollSize.height > 0 else { return }

            let scaleX = scrollSize.width / image.size.width
            let scaleY = scrollSize.height / image.size.height
            let fitScale = min(scaleX, scaleY)

            let newWidth = image.size.width * fitScale
            let newHeight = image.size.height * fitScale

            imageView.frame = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
            scrollView.contentSize = imageView.frame.size

            scrollView.minimumZoomScale = 1.0
            scrollView.zoomScale = 1.0

            DispatchQueue.main.async {
                self.viewSize = CGSize(width: newWidth, height: newHeight)
                self.viewFit = true
            }

            let size = CGSize(width: newWidth, height: newHeight)

            DispatchQueue.main.async {
                self.onInitialSize(size)       // <-- Call the parent callback here
            }

            hasInitialFit = true
            centerImage()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()
            let zoom = scrollView.zoomScale
            let isViewFit = abs(zoom - 1.0) < 0.01
            if isViewFit != viewFit {
                viewFit = isViewFit
            }
        }

        func centerImage() {
            guard let scrollView, let imageView else { return }
            let offsetX = max((scrollView.bounds.width - imageView.frame.width) * 0.5, 0)
            let offsetY = max((scrollView.bounds.height - imageView.frame.height) * 0.5, 0)
            scrollView.contentInset = UIEdgeInsets(
                top: offsetY, left: offsetX,
                bottom: offsetY, right: offsetX
            )
        }

        @objc func handleTap() {
            showControls.toggle()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if abs(scrollView.zoomScale - 1.0) > 0.01 {
                scrollView.setZoomScale(1.0, animated: true)
                centerImage()
                return
            }
            let location = recognizer.location(in: imageView)
            zoom(to: location)
        }

        private func zoom(to point: CGPoint) {
            guard let scrollView else { return }
            let zoomScale: CGFloat = 2.5
            let size = scrollView.bounds.size
            let width = size.width / zoomScale
            let height = size.height / zoomScale
            let rect = CGRect(
                x: point.x - width/2,
                y: point.y - height/2,
                width: width,
                height: height
            )

            scrollView.zoom(to: rect, animated: true)
        }
    }
}
