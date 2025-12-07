// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import UniformTypeIdentifiers

struct ShotViewfinderView: View {
    @Bindable var shot: Shot
    var onCapture: (UIImage) -> Void
    
    @State private var captureOrientation: UIDeviceOrientation? = nil
    @State private var captureLevel: OrientationUtils.Level? = nil
    @State private var capturedImage: UIImage? = nil
    @State private var isCaptured = false
    @State private var focusPoint: CGPoint? = nil
    @State private var showGalleryPicker = false
    @State private var showARPicker: Bool = false
    @State private var showExport = false
    
    @AppStorage("isFullscreen") private var isFullscreen = true
    @Environment(\.dismiss) private var dismiss

    @StateObject private var cameraModel = CameraModel()
    
    enum ActiveControls: String {
        case none
        case guides
        case overlay
        case image
        case ar
        case filter
        case exposure
    }
    
    enum ControlTypes {
        case none
        case opacityPicker
        case effectPicker
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
    
    @AppStorage("gridMode") private var gridModeRawValue: Int = ToggleMode.off.rawValue
    private var gridMode: ToggleMode {
        get { ToggleMode(rawValue: gridModeRawValue) ?? .off }
        set { gridModeRawValue = newValue.rawValue }
    }
    
    @AppStorage("levelMode") private var levelModeRawValue: Int = ToggleMode.off.rawValue
    private var levelMode: ToggleMode {
        get { ToggleMode(rawValue: levelModeRawValue) ?? .off }
        set { levelModeRawValue = newValue.rawValue }
    }
    
    @AppStorage("textMode") private var textMode: Bool = true
    
    @AppStorage("lutType") private var selectedLutTypeValue: String = LUTType.kodakNeutral.rawValue
    
    @State private var overlayMode: Bool = false
    @AppStorage("overlayOpacity") private var overlayOpacity: Double = 0.5
    @State private var overlayImage: UIImage? = nil

    @State private var arMode: Bool = false
    @State private var arFile: URL? = nil
    @State private var arActive: Bool = false
    
    @AppStorage("lensType") private var selectedLensRawValue: String = LensType.wide.rawValue

    @AppStorage("cameraMode") private var cameraMode: CameraMode = .auto
    
    @ObservedObject private var motionObserver = MotionObserver()
  
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            GeometryReader { geometry in
                let container = geometry.size
                Color.clear
                    .onAppear {
                        cameraModel.viewSize = container
                    }
                    .onChange(of: geometry.size) { _, newSize in
                        cameraModel.viewSize = newSize
                    }
                ZStack {
                    let aspectRatio = CameraUtils.aspectRatio(for: shot.aspectRatio)
                    let filmSize = CameraUtils.filmSize(for: shot.filmSize)
                    
                    // convert the portrait container to a landscape camera space and compute the
                    // projected frame as it would appear through the lens. This uses the focal length,
                    // film/sensor physical width, and the camera’s current field of view.

                    let projectedFrame = Projection.projectedFrame(
                        size: container.toLandscape(), // match camera
                        focalLength: CameraUtils.focalLength(for: shot.focalLength).length,
                        aspectRatio: filmSize.aspectRatio,
                        width: filmSize.width,
                        fieldOfView: cameraModel.fieldOfView
                    )

                    let projectedAspectRatio = Projection.frameForAspectRatio(
                        size: projectedFrame, // is camera
                        aspectRatio: aspectRatio.ratio > 0.0 ? aspectRatio.ratio : filmSize.aspectRatio
                    )
                    
                    let width = container.width
                    let height = container.height
                    let projectedSize = projectedFrame.toPortrait()
                    
                    let (scale): (CGFloat) = {
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
                    
                    // apply the scale factor between the projected frame and the container.
                    // Both the projected size and the aspect-corrected frame are in ui portrait
                    // coordinates, matching what mask view expects for rendering.

                    let displaySize = projectedSize * scale
                    let aspectFrame = projectedAspectRatio.toPortrait() * scale
                    
                    ZStack {
                        if isCaptured {
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: displaySize.width, height: displaySize.height)
                                .position(x: width / 2, y: height / 2)
                                .allowsHitTesting(false)
                        } else {
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
                            .frame(width: displaySize.width, height: displaySize.height)
                            .position(x: width / 2, y: height / 2)
                            .allowsHitTesting(false)
                        }

                        if let image = capturedImage, isCaptured {
                            ZStack {
                                let scale = (height * scale) / image.size.width; // is camera
                                ZStack {
                                    Image(uiImage: image)
                                        .scaleEffect(scale)
                                        .rotationEffect(.degrees(90))
                                }
                                .clipped()
                                .ignoresSafeArea()
                            }
                            .frame(width: width, height: height)
                            .position(x: width / 2, y: height / 2)
                            .ignoresSafeArea()
                            
                        } else {
                            ZStack {
                                let scale = (width * scale) / width;
                                ZStack {
                                    // compute the relative scale between the device’s display aspect ratio
                                    // and the camera’s full photo aspect ratio. The rectangle represents
                                    // the photo capture area (typically 4:3) and is scaled accordingly so
                                    // that it visually matches the sensor framing behind the live preview.
                                    
                                    let displayRatio = 1.0 / container.landscapeRatio
                                    let photoRatio = 1.0 / cameraModel.aspectRatio
                                    let scaleRatio = photoRatio / displayRatio
                                    
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.25))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                        )
                                        .scaleEffect(x: scaleRatio)
                                        .animation(.easeOut(duration: 0.3), value: scaleRatio)
                                    
                                    CameraPreview(renderer: cameraModel.renderer)
                                }
                                .scaleEffect((arMode && cameraModel.arState != .placed) ? 1.0 : scale)
                            }
                            .position(x: width / 2, y: height / 2)
                            .ignoresSafeArea()
                        }
                        MaskView(
                            frameSize: displaySize,
                            aspectSize: aspectFrame,
                            radius: 8,
                            geometry: geometry
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: isCaptured)
                    .mask(
                        RoundedRectangle(cornerRadius: 8)
                            .frame(width: displaySize.width, height: displaySize.height)
                            .position(x: width / 2, y: height / 2)
                    )
                    .overlay(
                        Group {
                            if levelMode != .off && (activeControls == .guides || activeControls == .none) {
                                LevelIndicatorView(
                                    level: motionObserver.level,
                                    orientation: motionObserver.orientation,
                                    levelMode: levelMode
                                )
                            }
                            
                            if gridMode != .off && (activeControls == .guides || activeControls == .none) {
                                GridView(
                                    gridMode: gridMode,
                                    size: aspectFrame,
                                    geometry: geometry
                                )
                                .position(x: width / 2, y: height / 2)
                                .allowsHitTesting(false)
                            }
                            
                            if centerMode != .off && (activeControls == .guides || activeControls == .none) {
                                CenterView(
                                    centerMode: centerMode,
                                    size: aspectFrame,
                                    geometry: geometry
                                )
                                .position(x: width / 2, y: height / 2)
                            }
                            
                            if textMode && (activeControls == .guides || activeControls == .none) {
                                let aperture = CameraUtils.aperture(for: shot.aperture)
                                let colorFilter = CameraUtils.colorFilter(for: shot.colorFilter)
                                let ndFilter = CameraUtils.ndFilter(for: shot.ndFilter)
                                let filmSize = CameraUtils.filmSize(for: shot.filmSize)
                                let filmStock = CameraUtils.filmStock(for: shot.filmStock)
                                let shutter = CameraUtils.shutter(for: shot.shutter)
                                let focalLength = CameraUtils.focalLength(for: shot.focalLength)

                                let exposureCompensation = colorFilter.exposureCompensation + ndFilter.exposureCompensation
                                let exposureText: String = (cameraMode != .auto)
                                    ? "\(aperture.name) \(shutter.name)" +
                                      (exposureCompensation != 0
                                        ? " (\(exposureCompensation >= 0 ? "+" : "")\(String(format: "%.1f", exposureCompensation)))"
                                        : "")
                                    : "Auto"
                                
                                let colorText: String = !colorFilter.isNone
                                    ? "\(Int(filmStock.colorTemperature))k" +
                                      (colorFilter.colorTemperatureShift != 0
                                        ? " (\(colorFilter.colorTemperatureShift >= 0 ? "+" : "")\(colorFilter.colorTemperatureShift))"
                                        : "")
                                    : "Auto"
                                
                                let text =
                                    "\(Int(filmSize.width))x\(Int(filmSize.height))mm " +
                                    "(\(String(format: "%.1f", filmSize.angleOfView(focalLength: focalLength.length).horizontal))°) " +
                                    "· \(String(format: "%.0f", filmStock.speed)) · \(exposureText) · \(colorText)"
                                
                                TextView(
                                    text: text,
                                    alignment: .top,
                                    orientation: motionObserver.orientation,
                                    geometry: geometry
                                )
                            }
                            
                            if arMode && (activeControls == .ar || activeControls == .none) {
                                ZStack {
                                    VStack(spacing: 8) {
                                        switch cameraModel.arState {
                                        case .idle:
                                            EmptyView()

                                        case .scanning:
                                            Label("Move phone to find the floor", systemImage: "arkit")
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .background(.ultraThinMaterial, in: Capsule())
                                                .font(.system(size: 13, weight: .semibold))

                                        case .refining:
                                            Label("Scanning surface…", systemImage: "rays")
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .background(.ultraThinMaterial, in: Capsule())
                                                .font(.system(size: 13, weight: .semibold))

                                        case .ready:
                                            Label("Pick AR model", systemImage: "checkmark.circle")
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .background(.ultraThinMaterial, in: Capsule())
                                                .font(.system(size: 13, weight: .semibold))
                                            
                                        case .placed:
                                            EmptyView()
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .rotationEffect(motionObserver.orientation.toLandscape)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                    .transition(.opacity)
                                    .animation(.easeInOut(duration: 0.25), value: cameraModel.arState)
                                }
                            }
                            
                            if overlayMode && (activeControls == .overlay || activeControls == .none) {
                                if let image = overlayImage {
                                    OverlayImageView(
                                        image: image,
                                        aspectSize: aspectFrame,
                                        geometry: geometry,
                                        cornerRadius: 6.0,
                                        opacity: overlayOpacity,
                                        blendMode: .screen
                                    )
                                }
                            }
                        }
                    )
                    
                    if activeControls == .none {
                        let scale = (width * scale) / width;
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
                                        let offset = 100.0
                                        let top = CGRect(x: 0, y: 0, width: geometry.size.width, height: offset)
                                        let bottom = CGRect(x: 0,y: geometry.size.height - offset, width: geometry.size.width, height: offset)
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
            
            if activeControls == .guides {
                ControlsView(
                    isVisible: .constant(true),
                    buttons: [
                        ControlButton(
                            icon: "gyroscope",
                            action: {
                                levelModeRawValue = levelMode.next().rawValue
                            },
                            background: levelMode.color,
                            rotation: motionObserver.orientation.toLandscape
                        ),
                        ControlButton(
                            icon: "grid",
                            action: {
                                gridModeRawValue = gridMode.next().rawValue
                            },
                            background: gridMode.color,
                            rotation: motionObserver.orientation.toLandscape
                        ),
                        ControlButton(
                            icon: "plus.circle.fill",
                            action: {
                                centerModeRawValue = centerMode.next().rawValue
                            },
                            background: centerMode.color,
                            rotation: motionObserver.orientation.toLandscape
                        ),
                        ControlButton(
                            icon: "textformat",
                            action: {
                                textMode.toggle()
                            },
                            background: (textMode) ? Color.blue.opacity(0.4) : Color.clear,
                            rotation: motionObserver.orientation.toLandscape
                        ),
                        ControlButton(
                            icon: "paintpalette",
                            action: {
                                activeControlType = (activeControlType == .effectPicker) ? nil : .effectPicker
                            },
                            background: (activeControlType == .effectPicker) ? Color.blue.opacity(0.4) : Color.clear,
                            rotation: motionObserver.orientation.toLandscape
                        )
                    ],
                    showOverlay: activeControlType == .effectPicker
                ){
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
                   .rotationEffect(motionObserver.orientation.toLandscape)
               }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(2)
            }
            
            if activeControls == .overlay {
                ControlsView(
                    isVisible: .constant(true),
                    buttons: [
                        ControlButton(
                            icon: "photo.on.rectangle",
                            action: { overlayMode.toggle() },
                            background: overlayMode ? Color.blue.opacity(0.4) : Color.clear,
                            rotation: motionObserver.orientation.toLandscape
                        ),
                        ControlButton(
                            icon: overlayImage == nil ? "arrow.down.doc" : "trash",
                            action: {
                                if overlayMode {
                                    if overlayImage == nil {
                                        showGalleryPicker = true
                                    } else {
                                        overlayImage = nil
                                    }
                                }
                            },
                            foreground: overlayMode ? .white : Color.white.opacity(0.4),
                            background: overlayImage == nil
                                ? (overlayMode ? Color.clear : Color.black.opacity(0.4))
                                : (overlayMode ? Color.red.opacity(0.4) : Color.red.opacity(0.15)),
                            rotation: motionObserver.orientation.toLandscape
                        ),
                        ControlButton(
                            icon: "circle.lefthalf.filled",
                            action: {
                                if overlayMode {
                                    activeControlType = (activeControlType == .opacityPicker) ? nil : .opacityPicker
                                }
                            },
                            foreground: overlayMode ? .white : Color.white.opacity(0.2),
                                background: overlayMode
                                    ? (activeControlType == .opacityPicker ? Color.blue.opacity(0.4) : Color.clear)
                                    : Color.black.opacity(0.2),
                            rotation: motionObserver.orientation.toLandscape
                        )
                    ],
                    showOverlay: activeControlType == .opacityPicker
                ) {
                    CircularPickerView(
                        selectedLabel: String(format: "%.0f%%", overlayOpacity * 100),
                        labels: stride(from: 0.0, through: 1.0, by: 0.1)
                            .map { String(format: "%.0f%%", $0 * 100) },
                        onChange: { selected in
                            if overlayMode,
                               let value = Double(selected.replacingOccurrences(of: "%", with: "")) {
                                overlayOpacity = value / 100.0
                            }
                        },
                        onRelease: { _ in }
                    )
                    .frame(width: 240, height: 240)
                    .rotationEffect(motionObserver.orientation.toLandscape)
                }
                .fullScreenCover(isPresented: $showGalleryPicker) {
                    GalleryPicker(selectedImage: $overlayImage)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(2)
            }
            
            if activeControls == .ar {
                ControlsView(
                    isVisible: .constant(true),
                    buttons: [
                        ControlButton(
                            icon: "arkit",
                            action: { arMode.toggle() },
                            background: arMode ? Color.blue.opacity(0.4) : Color.clear,
                            rotation: motionObserver.orientation.toLandscape
                        ),
                        ControlButton(
                            icon: (cameraModel.arState != .ready || arFile == nil)
                                ? "arrow.down.doc"
                                : "xmark.circle.fill",
                            action: {
                                // todo: restore this
                                /*guard cameraModel.arState == .ready else {
                                    return
                                }
                                if arFile == nil {*/
                                    showARPicker = true
                                /*}
                                else {
                                    arFile = nil
                                }*/
                            },
                            foreground:
                                cameraModel.arState == .ready
                                ? .white
                                : .white.opacity(0.2),
                            background:
                                cameraModel.arState != .ready
                                ? .clear
                                : (arFile == nil ? .clear : Color.red.opacity(0.4)),
                            rotation: motionObserver.orientation.toLandscape
                        )
                        
                    ]
                )
                .fullScreenCover(isPresented: $showARPicker) {
                    ARPicker(selectedModel: $arFile)
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
                            action: {
                                activeControlType = (activeControlType == .colorPicker) ? nil : .colorPicker
                            },
                            background: (activeControlType == .colorPicker) ? Color.blue.opacity(0.4) : Color.clear,
                            rotation: motionObserver.orientation.toLandscape
                        ),
                        ControlButton(
                            icon: "circle.lefthalf.filled",
                            action: {
                                activeControlType = (activeControlType == .ndPicker) ? nil : .ndPicker
                            },
                            background: (activeControlType == .ndPicker) ? Color.blue.opacity(0.4) : Color.clear,
                            rotation: motionObserver.orientation.toLandscape
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
                        .rotationEffect(motionObserver.orientation.toLandscape)
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
                        .rotationEffect(motionObserver.orientation.toLandscape)
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
                            action: {
                                activeControlType = (activeControlType == .shutterPicker) ? nil : .shutterPicker
                            },
                            background: (activeControlType == .shutterPicker)
                                ? Color.blue.opacity(0.4)
                                : Color.clear,
                            rotation: motionObserver.orientation.toLandscape
                        ),

                        ControlButton(
                            icon: "camera.aperture",
                            action: {
                                activeControlType = (activeControlType == .aperturePicker) ? nil : .aperturePicker
                            },
                            background: (activeControlType == .aperturePicker)
                                ? Color.blue.opacity(0.4)
                                : Color.clear,
                            rotation: motionObserver.orientation.toLandscape
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
                        .rotationEffect(motionObserver.orientation.toLandscape)
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
                        .rotationEffect(motionObserver.orientation.toLandscape)
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
                                    let offset = 60.0
                                    let top = CGRect(x: 0, y: 0, width: geometry.size.width, height: offset)
                                    let bottom = CGRect(
                                        x: 0,
                                        y: geometry.size.height - offset,
                                        width: geometry.size.width,
                                        height: offset
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
                                    .fill(Color.black.opacity(0.4))
                                    .frame(width: 38, height: 38)
                                
                                Image(systemName: isCaptured ? "chevron.down" : "xmark")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(Color.white)
                                    .offset(y: isCaptured ? 2 : 0)
                                    .animation(.easeInOut(duration: 0.2), value: isCaptured)
                            }
                            .rotationEffect(motionObserver.orientation.toLandscape)
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
                            captureOrientation = motionObserver.orientation
                            captureLevel = motionObserver.level
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
                                    .frame(width: 42, height: 42)
                                
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 38, height: 38)

                                Image(systemName: "arrow.up")
                                    .foregroundColor(Color.accentColor)
                                    .font(.system(size: 18, weight: .bold))
                                    .rotationEffect(motionObserver.orientation.toLandscape)
                            }
                        } else {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: 42, height: 42)
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 32, height: 32)
                            }
                        }
                    }
                    .disabled(arActive)
                    .opacity(arActive ? 0.4 : 1.0)
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
        .onChange(of: arMode) { _, enabled in
            if enabled {
                cameraModel.startARSession()
            } else {
                cameraModel.stopARSession()
                cameraModel.configure()
            }
            updateARActive();
        }
        .onChange(of: cameraModel.arState) { _, _ in
            updateARActive()
        }
        .onChange(of: arFile) { _, newFile in
            guard arMode, let url = newFile else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                cameraModel.placeARModel(from: url)
            }
        }
        .onChange(of: cameraMode) { _, newMode in
            switchExposure()
        }
        .onDisappear {
            cameraModel.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .statusBarHidden()
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
                .cornerRadius(4)
                .rotationEffect(motionObserver.orientation.toLandscape)
            
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
        .disabled(arActive)
        .opacity(arActive ? 0.4 : 1.0)
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
                .cornerRadius(4)
                .rotationEffect(motionObserver.orientation.toLandscape)
            
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
        .disabled(arActive)
        .opacity(arActive ? 0.4 : 1.0)
    }
    
    @ViewBuilder
    private func toolsControls() -> some View {
        HStack(spacing: 6) {
            Button(action: {
                toggleLens()
            }) {
                Text(lensLabel(for: cameraModel.lensType))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .rotationEffect(motionObserver.orientation.toLandscape)
            }
            
            Button(action: {
                activeControls = (activeControls == .guides) ? .none : .guides
            }) {
                Image(systemName: "viewfinder.circle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(activeControls == .guides ? Color.blue.opacity(0.4) : Color.clear)
                    .clipShape(Circle())
                    .rotationEffect(motionObserver.orientation.toLandscape)
            }
            
            Button(action: {
                activeControls = (activeControls == .overlay) ? .none : .overlay
            }) {
                Image(systemName: "photo")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(activeControls == .overlay ? Color.blue.opacity(0.4) : Color.clear)
                    .clipShape(Circle())
                    .rotationEffect(motionObserver.orientation.toLandscape)
            }
            
            Button(action: {
                activeControls = (activeControls == .ar) ? .none : .ar
            }) {
                Image(systemName: "arkit")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    (activeControls == .ar || arMode)
                        ? Color.blue.opacity(0.4)
                        : Color.clear
                )
                .clipShape(Circle())
                .rotationEffect(motionObserver.orientation.toLandscape)
            }
        }
        .frame(width: 145)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.4))
        )
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
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(cameraMode == .manual ? Color.blue.opacity(0.4) : Color.clear)
                    .clipShape(Circle())
                    .rotationEffect(motionObserver.orientation.toLandscape)
            }
            
            Button(action: {
                activeControls = (activeControls == .filter) ? .none : .filter
            }) {
                Image(systemName: "camera.filters")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(activeControls == .filter ? Color.blue.opacity(0.4) : Color.clear)
                    .clipShape(Circle())
                    .rotationEffect(motionObserver.orientation.toLandscape)
            }
            .disabled(cameraMode == .auto)
            .opacity(cameraMode == .auto ? 0.4 : 1.0)

            Button(action: {
                activeControls = (activeControls == .exposure) ? .none : .exposure
            }) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(activeControls == .exposure ? Color.blue.opacity(0.4) : Color.clear)
                    .clipShape(Circle())
                    .rotationEffect(motionObserver.orientation.toLandscape)
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
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .rotationEffect(motionObserver.orientation.toLandscape)
            }
        }
        .frame(width: 145)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.4))
        )
    }
    
    private func updateARActive() {
        arActive = arMode && cameraModel.arState != .placed
    }
    
    private func captureImage(image: UIImage) {
        var image = image
        let containerSize = image.size
        let filmSize = CameraUtils.filmSize(for: shot.filmSize)
        var projectedSize = Projection.projectedFrame(
            size: containerSize,
            focalLength: CameraUtils.focalLength(for: shot.focalLength).length,
            aspectRatio: filmSize.aspectRatio,
            width: filmSize.width,
            fieldOfView: cameraModel.fieldOfView
        )
        
        // if the projected frame is larger than the captured image,
        // scale it down to fit within the container while preserving aspect ratio.
        // The image is then rescaled and composited onto a black canvas to ensure
        // the full projection remains visible without cropping

        if projectedSize.exceeds(containerSize) {
            let scaleFactor = projectedSize.scaleToFit(in: containerSize)
            let scaledSize = projectedSize * scaleFactor
            projectedSize = scaledSize
            if let composed = composeImage(image, scale: scaleFactor, canvasSize: containerSize) {
                image = composed
            }
        }

        let croppedImage = cropImage(
            image,
            frameSize: projectedSize,
            containerSize: containerSize,
            orientation: captureOrientation ?? .portrait
        )

        if let captureLevel {
            let normalized = OrientationUtils.normalizeLevel(from: captureLevel)
            shot.deviceRoll = normalized.roll
            shot.deviceTilt = normalized.tilt
        }
        
        shot.deviceLens = cameraModel.lensType.rawValue
        onCapture(croppedImage)
    }

    private func composeImage(_ image: UIImage, scale: CGFloat, canvasSize: CGSize) -> UIImage? {
        let scaledWidth = image.size.width * scale
        let scaledHeight = image.size.height * scale

        let originX = (canvasSize.width - scaledWidth) / 2
        let originY = (canvasSize.height - scaledHeight) / 2
        let drawRect = CGRect(x: originX, y: originY, width: scaledWidth, height: scaledHeight)

        UIGraphicsBeginImageContextWithOptions(canvasSize, false, image.scale)
        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: canvasSize))
        image.draw(in: drawRect)
        let composedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return composedImage
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
        
        guard let targetImage = nativeImage.cropping(to: cropRect) else {
            let fallbackImage = UIImage(
                cgImage: nativeImage,
                scale: image.scale,
                orientation: imageOrientation(for: orientation)
            )
            return fallbackImage
        }
        
        let croppedUIImage = UIImage(
            cgImage: targetImage,
            scale: image.scale,
            orientation: imageOrientation(for: orientation)
        )
        return croppedUIImage
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
