// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import AVFoundation

struct ShotViewfinderView: View {
    @Bindable var shot: Shot
    
    var onCapture: (UIImage) -> Void
    @State private var capturedImage: UIImage? = nil
    @State private var isCaptured = false
    
    @AppStorage("isFullscreen") private var isFullscreen = false
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var focusPoint: CGPoint? = nil
    @State private var imageDataToExport: Data? = nil
    @State private var showExport = false
    
    @StateObject private var cameraModel = CameraModel()
    
    enum ActiveControls: String {
        case none
        case overlay
        case metadata
        case image
        case look
        case filter
        case exposure
    }
    
    enum ControlTypes {
        case none
        case lookPicker
        case colorPicker
        case ndPicker
        case shutterPicker
        case aperturePicker
    }

    @State private var activeControls: ActiveControls = .none
    @State private var activeControlType: ControlTypes? = nil
    
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
    
    @AppStorage("metaDataMode") private var metaDataMode: Bool = true
    
    @AppStorage("lensType") private var selectedLensRawValue: String = LensType.wide.rawValue
    @AppStorage("lutType") private var selectedLutTypeValue: String = LUTType.kodakNeutral.rawValue
    
    @AppStorage("cameraMode") private var cameraMode: CameraMode = .auto
    
    @ObservedObject private var orientationObserver = OrientationObserver()
  
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            GeometryReader { geometry in
                ZStack {
                    let aspectRatio = CameraUtils.aspectRatio(for: shot.aspectRatio)
                    let filmSize = CameraUtils.filmSize(for: shot.filmSize)
                
                    let projectedFrame = Projection.projectedFrame(
                        size: geometry.size.switchOrientation(), // project for camera
                        focalLength: CameraUtils.focalLength(for: shot.focalLength).length,
                        aspectRatio: filmSize.aspectRatio,
                        width: filmSize.width,
                        fieldOfView: cameraModel.fieldOfView
                    )

                    let projectedAspectRatio = Projection.frameForAspectRatio(
                        size: projectedFrame, // is camera
                        aspectRatio: aspectRatio.ratio > 0.0 ? aspectRatio.ratio : filmSize.aspectRatio
                    )
                    
                    let width = geometry.size.width
                    let height = geometry.size.height
                    let projectedSize = projectedFrame.switchOrientation()
                    
                    let (fit): (CGFloat) = {
                        if isFullscreen {
                            let padding: CGFloat = 10
                            let iw = width - padding * 2
                            let ih = height - padding * 2
                            let f = min(iw / projectedSize.width, ih / projectedSize.height)
                            return (f)
                        } else {
                            return (1.0)
                        }
                    }()

                    let frameSize = projectedSize * fit
                    let frameAspectRatio = projectedAspectRatio.switchOrientation() * fit
                    
                    ZStack {
                        Canvas { context, size in
                            let spacing: CGFloat = 20
                            let lineWidth: CGFloat = 6
                            var path = Path()
                            for x in stride(from: -size.height, to: size.width, by: spacing) {
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                            }
                            
                            context.stroke(path, with: .color(.gray.opacity(0.4)), lineWidth: lineWidth)
                        }
                        .frame(width: frameSize.width, height: frameSize.height)
                        .position(x: width / 2, y: height / 2)
                        .allowsHitTesting(false)
                        
                        if let image = capturedImage, isCaptured {
                            ZStack {
                                let scale = (height * fit) / image.size.width; // is camera
                                ZStack {
                                    Image(uiImage: image)
                                        .scaleEffect(scale)
                                        .rotationEffect(.degrees(90)) // to potrait
                                }
                                .clipped()
                                .ignoresSafeArea()
                            }
                            .frame(width: width, height: height)
                            .position(x: width / 2, y: height / 2)
                            .ignoresSafeArea()
                            
                        } else {
                            ZStack {
                                let scale = (width * fit) / width;
                                ZStack {
                                    CameraMetalPreview(renderer: cameraModel.renderer) // is portait
                                        .scaleEffect(scale)
                                }
                            }
                            .position(x: width / 2, y: height / 2)
                            .ignoresSafeArea()
                        }
                        
                        MaskView(
                            frameSize: frameSize,
                            aspectSize: frameAspectRatio,
                            inner: 0.4,
                            outer: 0.95,
                            geometry: geometry
                        )
                        
                        if centerMode != .off && (activeControls == .overlay || activeControls == .none) {
                            CenterView(
                                centerMode: centerMode,
                                size: projectedAspectRatio * fit, // draw for camera
                                geometry: geometry
                            )
                            .rotationEffect(.degrees(90)) // to potrait
                            .position(x: width / 2, y: height / 2)
                        }
                        
                        if symmetryMode != .off && (activeControls == .overlay || activeControls == .none) {
                            SymmetryView(
                                symmetryMode: symmetryMode,
                                size: projectedAspectRatio * fit, // draw for camera
                                geometry: geometry
                            )
                            .rotationEffect(.degrees(90)) // to potrait
                            .position(x: width / 2, y: height / 2)
                        }
                        
                        if levelMode != .off && (activeControls == .overlay || activeControls == .none) {
                            LevelIndicatorView(
                                level: orientationObserver.level,
                                orientation: orientationObserver.orientation,
                                levelMode: levelMode
                            )
                        }
                        
                        if metaDataMode && (activeControls == .metadata || activeControls == .none) {
                            let aperture = CameraUtils.aperture(for: shot.aperture)
                            let colorFilter = CameraUtils.colorFilter(for: shot.colorFilter)
                            let ndFilter = CameraUtils.colorFilter(for: shot.ndFilter)
                            let filmSize = CameraUtils.filmSize(for: shot.filmSize)
                            let filmStock = CameraUtils.filmStock(for: shot.filmStock)
                            let shutter = CameraUtils.filmStock(for: shot.shutter)
                            let focalLength = CameraUtils.focalLength(for: shot.focalLength)
                            
                            let colorTempText: String = !colorFilter.isNone
                                ? "\(Int(filmStock.colorTemperature + colorFilter.colorTemperatureShift))K (\(colorFilter.name))"
                                : " WB: Auto"

                            let exposureCompensation = colorFilter.exposureCompensation + ndFilter.exposureCompensation
                            let exposureText: String = (cameraMode != .auto)
                                ? ", E: \(Int(filmStock.speed)) \(shutter.name) \(aperture.name)\(exposureCompensation != 0 ? " (\(String(format: "%+.1f", exposureCompensation)))" : "")"
                                : ", E: Auto"
                            
                            let text =
                                "\(Int(filmSize.width)) mm x \(Int(filmSize.height)) mm, " +
                                "\(String(format: "%.1f", filmSize.angleOfView(focalLength: focalLength.length).horizontal))°, " +
                                "\(colorTempText)\(exposureText)"
                            
                            TextView(
                                text: text,
                                alignment: .top,
                                orientation: orientationObserver.orientation,
                                geometry: geometry
                            )
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: isCaptured)
                    
                    if activeControls == .none {
                        let scale = (width * fit) / width;
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { gesture in
                                        let tapPoint = gesture.location
                                        let adjustedPoint = CGPoint(
                                            x: tapPoint.x / scale,
                                            y: tapPoint.y / scale
                                        )
                                        let top = CGRect(x: 0, y: 0, width: geometry.size.width, height: 140)
                                        let bottom = CGRect(x: 0,y: geometry.size.height - 140, width: geometry.size.width, height: 140)
                                        if !top.contains(tapPoint) && !bottom.contains(tapPoint) {
                                            cameraModel.focus(
                                                at: adjustedPoint,
                                                viewSize: CGSize(width: geometry.size.width / scale, height: geometry.size.height / scale)
                                            )
                                            focusPoint = tapPoint
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
                                .frame(width: 32, height: 32)
                                .position(x: point.x, y: point.y)
                                .transition(.opacity)
                                .animation(.easeOut(duration: 0.3), value: focusPoint)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            
            if activeControls == .overlay {
                ControlsView(
                    isVisible: .constant(true),
                    buttons: [
                        ControlButton(
                            icon: "gyroscope",
                            label: "Gyroscope",
                            action: {
                                levelModeRawValue = levelMode.next().rawValue
                            },
                            background: levelMode.color,
                            rotation: orientationObserver.orientation.rotationAngle
                        ),
                        ControlButton(
                            icon: "grid",
                            label: "Symmetry",
                            action: {
                                symmetryModeRawValue = symmetryMode.next().rawValue
                            },
                            background: symmetryMode.color,
                            rotation: orientationObserver.orientation.rotationAngle
                        ),
                        ControlButton(
                            icon: "plus.circle.fill",
                            label: "Center",
                            action: {
                                centerModeRawValue = centerMode.next().rawValue
                            },
                            background: centerMode.color,
                            rotation: orientationObserver.orientation.rotationAngle
                        )
                    ]
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(2)
            }
            
            if activeControls == .metadata {
                ControlsView(
                    isVisible: .constant(true),
                    buttons: [
                        ControlButton(
                            icon: "textformat",
                            label: "Metadata",
                            action: {
                                metaDataMode.toggle()
                            },
                            background: (metaDataMode) ? Color.blue.opacity(0.4) : Color.clear,
                            rotation: orientationObserver.orientation.rotationAngle
                        ),
                    ]
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(2)
            }
            
            if activeControls == .look {
                ControlsView(
                    isVisible: .constant(true),
                    buttons: [
                        ControlButton(
                            icon: "paintpalette",
                            label: "Look",
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    activeControlType = (activeControlType == .lookPicker) ? nil : .lookPicker
                                }
                            },
                            background: (activeControlType == .lookPicker) ? Color.blue.opacity(0.4) : Color.clear,
                            rotation: orientationObserver.orientation.rotationAngle
                        )
                    ],
                    showOverlay: activeControlType == .lookPicker
                ) {
                    CircularPickerView(
                        selectedLabel: selectedLutTypeValue,
                        labels: LUTType.allCases.map { $0.rawValue },
                        onChange: { selected in
                            selectedLutTypeValue = selected
                            if let lutType = LUTType(rawValue: selected) {
                                cameraModel.renderer.setLutType(lutType)
                            }
                        },
                        onRelease: { _ in }
                    )
                    .frame(width: 240, height: 240)
                    .rotationEffect(orientationObserver.orientation.rotationAngle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(2)
            }
            
            if activeControls == .filter {
                ControlsView(
                    isVisible: .constant(true),
                    buttons: [
                        ControlButton(
                            icon: "camera.filters",
                            label: "Color",
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    activeControlType = (activeControlType == .colorPicker) ? nil : .colorPicker
                                }
                            },
                            background: (activeControlType == .colorPicker) ? Color.blue.opacity(0.4) : Color.clear,
                            rotation: orientationObserver.orientation.rotationAngle
                        ),
                        ControlButton(
                            icon: "circle.lefthalf.filled",
                            label: "ND",
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    activeControlType = (activeControlType == .ndPicker) ? nil : .ndPicker
                                }
                            },
                            background: (activeControlType == .ndPicker) ? Color.blue.opacity(0.4) : Color.clear,
                            rotation: orientationObserver.orientation.rotationAngle
                        )
                    ],
                    showOverlay: activeControlType == .colorPicker || activeControlType == .ndPicker
                ) {
                    if activeControlType == .colorPicker {
                        CircularPickerView(
                            selectedLabel: shot.colorFilter,
                            labels: CameraUtils.colorFilters.map { $0.name },
                            onChange: { selected in
                                shot.colorFilter = selected
                                adjustEVExposure()
                                adjustWhiteBalance()
                            },
                            onRelease: { _ in }
                        )
                        .frame(width: 240, height: 240)
                        .rotationEffect(orientationObserver.orientation.rotationAngle)
                    } else if activeControlType == .ndPicker {
                        CircularPickerView(
                            selectedLabel: shot.ndFilter,
                            labels: CameraUtils.ndFilters.map { $0.name },
                            onChange: { selected in
                                shot.ndFilter = selected
                                adjustEVExposure()
                            },
                            onRelease: { _ in }
                        )
                        .frame(width: 240, height: 240)
                        .rotationEffect(orientationObserver.orientation.rotationAngle)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(2)
            }
            
            if activeControls == .exposure {
                ControlsView(
                    isVisible: .constant(true),
                    buttons: [
                        ControlButton(
                            icon: "plusminus.circle",
                            label: "Shutter",
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    activeControlType = (activeControlType == .shutterPicker) ? nil : .shutterPicker
                                }
                            },
                            background: (activeControlType == .shutterPicker)
                                ? Color.blue.opacity(0.4)
                                : Color.clear,
                            rotation: orientationObserver.orientation.rotationAngle
                        ),

                        ControlButton(
                            icon: "camera.aperture",
                            label: "Aperture",
                            action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    activeControlType = (activeControlType == .aperturePicker) ? nil : .aperturePicker
                                }
                            },
                            background: (activeControlType == .aperturePicker)
                                ? Color.blue.opacity(0.4)
                                : Color.clear,
                            rotation: orientationObserver.orientation.rotationAngle
                        )
                    ],
                    showOverlay: activeControlType == .shutterPicker || activeControlType == .aperturePicker
                ) {
                    if activeControlType == .shutterPicker {
                        CircularPickerView(
                            selectedLabel: shot.shutter,
                            labels: CameraUtils.shutters.map { $0.name },
                            onChange: { selected in
                                shot.shutter = selected
                                adjustEVExposure()
                            },
                            onRelease: { _ in }
                        )
                        .frame(width: 240, height: 240)
                        .rotationEffect(orientationObserver.orientation.rotationAngle)
                    } else if activeControlType == .aperturePicker {
                        CircularPickerView(
                            selectedLabel: shot.aperture,
                            labels: CameraUtils.apertures.map { $0.name },
                            onChange: { selected in
                                shot.aperture = selected
                                adjustEVExposure()
                            },
                            onRelease: { _ in }
                        )
                        .frame(width: 240, height: 240)
                        .rotationEffect(orientationObserver.orientation.rotationAngle)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(2)
            }
            
            if activeControls != .none {
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { gesture in
                                    let tapPoint = gesture.location
                                    let top = CGRect(x: 0, y: 0, width: geometry.size.width, height: 140)
                                    let bottom = CGRect(
                                        x: 0,
                                        y: geometry.size.height - 140,
                                        width: geometry.size.width,
                                        height: 140
                                    )
                                    if !top.contains(tapPoint) && !bottom.contains(tapPoint) {
                                        activeControls = .none
                                        activeControlType = nil
                                    }
                                }
                        )
                        .ignoresSafeArea()
                        .zIndex(1)
                }
            }
            
            ZStack {
                Color.clear
                VStack {
                    HStack {
                        toolsControls()
                        
                        Button(action: {
                            if isCaptured {
                                capturedImage = nil
                                isCaptured = false
                            } else {
                                dismiss()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 36, height: 36)
                                Image(systemName: isCaptured ? "chevron.down" : "xmark")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.black)
                                    .offset(y: isCaptured ? 2 : 0)
                            }
                            .padding(6)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .rotationEffect(orientationObserver.orientation.rotationAngle)
                            .animation(.easeInOut(duration: 0.2), value: isCaptured)
                        }
                        .frame(width: 42)
                        
                        cameraControls()
                    }
                    .padding(.top, 42)
                    .padding(.horizontal)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            
            if (activeControls == .none) {
                HStack {
                    focalLengthControls()
                    
                    Button(action: {
                        if isCaptured, let image = capturedImage {
                            captureImage(image: image)
                            dismiss()
                        } else {
                            cameraModel.capturePhoto { cgImage in
                                if let cgImage = cgImage {
                                    let image = UIImage(cgImage: cgImage)
                                    capturedImage = image
                                    isCaptured = true
                                }
                            }
                        }
                    }) {
                        if isCaptured {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: 48, height: 48)
                                
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                    .rotationEffect(orientationObserver.orientation.rotationAngle)
                            }
                        } else {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: 48, height: 48)
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 36, height: 36)
                            }
                        }
                    }
                    .frame(width: 60)
                    
                    aspectRatioControls()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
        .onAppear {
            cameraModel.configure { result in
                switch result {
                case .success:
                    let saved = LensType(rawValue: selectedLensRawValue) ?? .wide
                    if cameraModel.lensType != saved {
                        cameraModel.switchCamera(to: saved)
                    }
                    switchExposure()
                    if let lutType = LUTType(rawValue: selectedLutTypeValue) {
                        cameraModel.renderer.setLutType(lutType)
                    }
                case .failure(let error):
                    print("camera error: \(error.localizedDescription)")
                }
            }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onChange(of: activeControls) { _, newValue in
            switch newValue {
            case .look:
                withAnimation(.easeInOut(duration: 0.3)) {
                    activeControlType = .lookPicker
                }
            case .filter:
                withAnimation(.easeInOut(duration: 0.3)) {
                    activeControlType = .colorPicker
                }
            case .exposure:
                withAnimation(.easeInOut(duration: 0.3)) {
                    activeControlType = .shutterPicker
                }
            default:
                activeControlType = nil
            }
        }
        .onChange(of: cameraMode) { _, newMode in
            switchExposure()
        }
        .onDisappear {
            cameraModel.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    @ViewBuilder
    private func focalLengthControls() -> some View {
        HStack(spacing: 0) {
            Button(action: {
                if let currentIndex = CameraUtils.focalLengths.firstIndex(where: { $0.name == shot.focalLength }) {
                    let newIndex = (currentIndex - 1 + CameraUtils.focalLengths.count) % CameraUtils.focalLengths.count
                    shot.focalLength = CameraUtils.focalLengths[newIndex].name
                }
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            
            Text("\(shot.focalLength)")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(width: 55)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.4))
                .cornerRadius(4)
                .rotationEffect(orientationObserver.orientation.rotationAngle)
            
            Button(action: {
                if let currentIndex = CameraUtils.focalLengths.firstIndex(where: { $0.name == shot.focalLength }) {
                    let newIndex = (currentIndex + 1) % CameraUtils.focalLengths.count
                    shot.focalLength = CameraUtils.focalLengths[newIndex].name
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
                if let currentIndex = CameraUtils.aspectRatios.firstIndex(where: { $0.name == shot.aspectRatio }) {
                    let newIndex = (currentIndex - 1 + CameraUtils.aspectRatios.count) % CameraUtils.aspectRatios.count
                    shot.aspectRatio = CameraUtils.aspectRatios[newIndex].name
                }
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            
            Text("\(shot.aspectRatio)")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(width: 55)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.4))
                .cornerRadius(4)
                .rotationEffect(orientationObserver.orientation.rotationAngle)
            
            Button(action: {
                if let currentIndex = CameraUtils.aspectRatios.firstIndex(where: { $0.name == shot.aspectRatio }) {
                    let newIndex = (currentIndex + 1) % CameraUtils.aspectRatios.count
                    shot.aspectRatio = CameraUtils.aspectRatios[newIndex].name
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
            Button(action: {
                toggleLens()
            }) {
                Text(lensLabel(for: cameraModel.lensType))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.rotationAngle)
            }
            
            Button(action: {
                activeControls = (activeControls == .overlay) ? .none : .overlay
            }) {
                Image(systemName: "viewfinder.circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(activeControls == .overlay ? Color.blue.opacity(0.4) : Color.clear)
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.rotationAngle)
            }
            
            Button(action: {
                activeControls = (activeControls == .metadata) ? .none : .metadata
            }) {
                Image(systemName: "textformat")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(activeControls == .metadata ? Color.blue.opacity(0.4) : Color.clear)
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.rotationAngle)
            }
            
            Button(action: {
                activeControls = (activeControls == .look) ? .none : .look
            }) {
                Image(systemName: "paintpalette")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(activeControls == .look ? Color.blue.opacity(0.4) : Color.clear)
                .clipShape(Circle())
                .rotationEffect(orientationObserver.orientation.rotationAngle)
            }
        }
        .frame(width: 145)
    }
    
    @ViewBuilder
    private func cameraControls() -> some View {
        HStack(spacing: 6) {
            Button(action: {
                cameraMode = (cameraMode == .auto) ? .manual : .auto
                if activeControls == .filter || activeControls == .exposure {
                    activeControls = .none
                    activeControlType = nil
                }
            }) {
                Text(cameraLabel(for: cameraMode))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(cameraMode == .manual ? Color.blue.opacity(0.4) : Color.clear)
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.rotationAngle)
            }
            
            Button(action: {
                activeControls = (activeControls == .filter) ? .none : .filter
            }) {
                Image(systemName: "camera.filters")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(activeControls == .filter ? Color.blue.opacity(0.4) : Color.clear)
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.rotationAngle)
            }
            .disabled(cameraMode == .auto)
            .opacity(cameraMode == .auto ? 0.4 : 1.0)

            Button(action: {
                activeControls = (activeControls == .exposure) ? .none : .exposure
            }) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(activeControls == .exposure ? Color.blue.opacity(0.4) : Color.clear)
                    .clipShape(Circle())
                    .rotationEffect(orientationObserver.orientation.rotationAngle)
            }
            .disabled(cameraMode == .auto)
            .opacity(cameraMode == .auto ? 0.4 : 1.0)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isFullscreen.toggle()
                }
            }) {
                Image(systemName: isFullscreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
                .rotationEffect(orientationObserver.orientation.rotationAngle)
            }
        }
        .frame(width: 145)
    }
    
    private func captureImage(image: UIImage) {
        let containerSize = image.size
        let filmSize = CameraUtils.filmSize(for: shot.filmSize)
        let projectedSize = Projection.projectedFrame(
            size: containerSize, //.switchOrientation(), // to native // TODO: verify this one!
            focalLength: CameraUtils.focalLength(for: shot.focalLength).length,
            aspectRatio: filmSize.aspectRatio,
            width: filmSize.width,
            fieldOfView: cameraModel.fieldOfView
        )
        let croppedImage = cropImage(
            image,
            frameSize: projectedSize,
            containerSize: containerSize,
            orientation: orientationObserver.orientation
        )
        //shot.deviceRoll
        //shot.deviceTilt
        shot.deviceAspectRatio = Double(image.size.width / image.size.height)
        shot.deviceFieldOfView = cameraModel.fieldOfView
        shot.deviceLens = cameraModel.lensType.rawValue
        onCapture(croppedImage)
    }
    
    private func cropImage(_ image: UIImage,
                           frameSize: CGSize,
                           containerSize: CGSize,
                           orientation: UIDeviceOrientation) -> UIImage {
        
        guard let cgImage = image.cgImage else { return image }
        let size = containerSize
        let width = CGFloat(size.width)
        let height = CGFloat(size.height)
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
        
        /*
         guard let targetImage = nativeImage.cropping(to: cropRect) else {
         return UIImage(cgImage: nativeImage,
         scale: image.scale,
         orientation: imageOrientation(for: orientation) // correct orientation for UI views
         )
         }
         
         return UIImage(cgImage: targetImage, scale: image.scale, orientation: imageOrientation(for: orientation))*/
        
        guard let targetImage = nativeImage.cropping(to: cropRect) else {
            let fallbackImage = UIImage(
                cgImage: nativeImage,
                scale: image.scale,
                orientation: imageOrientation(for: orientation)
            )
            
            print("📸 cropImage (FALLBACK)")
            print(" - Native size: \(nativeImage.width)x\(nativeImage.height)")
            print(" - Crop rect: \(cropRect)")
            print(" - Returning fallback UIImage")
            print("   • Size: \(fallbackImage.size.width)x\(fallbackImage.size.height)")
            print("   • Scale: \(fallbackImage.scale)")
            print("   • Orientation: \(fallbackImage.imageOrientation.rawValue) -> \(orientationDescription(fallbackImage.imageOrientation))")
            
            return fallbackImage
        }
        
        let croppedUIImage = UIImage(
            cgImage: targetImage,
            scale: image.scale,
            orientation: imageOrientation(for: orientation)
        )
        
        print("📸 cropImage (SUCCESS)")
        print(" - Native size: \(nativeImage.width)x\(nativeImage.height)")
        print(" - Crop rect: \(cropRect)")
        print(" - Cropped CGImage size: \(targetImage.width)x\(targetImage.height)")
        print(" - Returning UIImage")
        print("   • Size: \(croppedUIImage.size.width)x\(croppedUIImage.size.height)")
        print("   • Scale: \(croppedUIImage.scale)")
        print("   • Orientation: \(croppedUIImage.imageOrientation.rawValue) -> \(orientationDescription(croppedUIImage.imageOrientation))")
        
        
        
        return croppedUIImage
    }
    
    private func orientationDescription(_ orientation: UIImage.Orientation) -> String {
        switch orientation {
        case .up: return "up (default)"
        case .down: return "down (180° rotated)"
        case .left: return "left (90° CCW)"
        case .right: return "right (90° CW)"
        case .upMirrored: return "upMirrored"
        case .downMirrored: return "downMirrored"
        case .leftMirrored: return "leftMirrored"
        case .rightMirrored: return "rightMirrored"
        @unknown default: return "unknown"
        }
    }
    
    private func imageOrientation(for deviceOrientation: UIDeviceOrientation) -> UIImage.Orientation {
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
        cameraModel.adjustEVExposure(
            fstop: CameraUtils.aperture(for: shot.aperture).fstop,
            speed: CameraUtils.filmStock(for: shot.filmStock).speed,
            shutter: CameraUtils.shutter(for: shot.shutter).shutter,
            exposureCompensation: CameraUtils.colorFilter(for: shot.colorFilter).exposureCompensation + CameraUtils.ndFilter(for: shot.ndFilter).exposureCompensation
        )
    }
    
    func adjustWhiteBalance() {
        let colorFilter = CameraUtils.colorFilter(for: shot.colorFilter)
        if !colorFilter.isNone {
            cameraModel.adjustWhiteBalance(kelvin: CameraUtils.filmStock(for: shot.filmStock).colorTemperature + colorFilter.colorTemperatureShift)
        } else {
            cameraModel.resetWhiteBalance()
        }
    }
    
    func resetWhiteBalance() {
        cameraModel.resetWhiteBalance()
    }
}
