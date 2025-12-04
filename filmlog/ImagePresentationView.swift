// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI

struct ImagePresentationView: View {
    let images: [ImageData]
    @State private var currentIndex: Int
    var onClose: () -> Void
    
    @State private var showControls: Bool = true
    @State private var viewSize: CGSize = .zero
    @State private var viewFit: Bool = true
    @State private var viewReady: Bool = true
    
    @AppStorage("gridMode") private var gridModeRawValue: Int = 0
    private var gridMode: ToggleMode {
        get { ToggleMode(rawValue: gridModeRawValue) ?? .off }
        set { gridModeRawValue = newValue.rawValue }
    }
    
    @AppStorage("aspectRatioMode") private var aspectRatioMode: Bool = true
    @AppStorage("textMode") private var textMode: Bool = true
    
    init(images: [ImageData], startIndex: Int, onClose: @escaping () -> Void) {
        self.images = images
        _currentIndex = State(initialValue: startIndex)
        self.onClose = onClose
    }
    
    private var uiImages: [UIImage] {
        images.compactMap { $0.original ?? $0.thumbnail }
    }
    
    @ObservedObject private var orientationObserver = OrientationObserver()
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                
                ZStack {
                    if !uiImages.isEmpty {
                        ZStack {
                            // the paged viewer is rotated for use in landscape mode, in a
                            // ui potrait orientation, scale it slightly to fit inside the
                            // safe area.
                            
                            PagedImageViewer(
                                images: uiImages,
                                index: $currentIndex,
                                showControls: $showControls,
                                viewSize: $viewSize,
                                viewFit: $viewFit,
                                viewReady: $viewReady,
                            )
                            .scaleEffect(0.90)
                            .rotationEffect(.degrees(90))
                            .frame(width: height, height: width)
                            .position(x: width / 2, y: height / 2)
                            .clipped()
                            .ignoresSafeArea()
                            
                            if aspectRatioMode {
                                let ratio = aspectRatioMetadataDouble
                                if (ratio > 1.0) {
                                    if viewReady && viewFit {
                                        let displaySize = viewSize * 0.9
                                        let projectedAspectRatio = Projection.frameForAspectRatio(
                                            size: displaySize.toLandscape(), // match camera
                                            aspectRatio: ratio > 0.0 ? ratio : 1.0
                                        )
                                        
                                        let aspectFrame = projectedAspectRatio.toPortrait()
                                        
                                        AspectRatioView(
                                            frameSize: displaySize,
                                            aspectSize: aspectFrame,
                                            radius: 8,
                                            geometry: geometry
                                        )
                                        .clipShape(
                                            RoundedRectangle(cornerRadius: 8)
                                        )
                                    }
                                }
                            }
                        }
                        .overlay {
                            if viewReady && viewFit && gridMode != .off {
                                let displaySize = viewSize.toPortrait() * 0.9
                                
                                GridView(
                                    gridMode: gridMode,
                                    size: displaySize,
                                    geometry: geometry
                                )
                                .allowsHitTesting(false)
                                .position(x: width / 2, y: height / 2)
                                .mask(
                                    RoundedRectangle(cornerRadius: 8)
                                        .frame(width: displaySize.width, height: displaySize.height)
                                        .position(x: width / 2, y: height / 2)
                                )
                            }
                            
                            if (textMode) {
                                TextView(
                                    text: hasCameraMetadata ? cameraMetadataText : imageNameText,
                                    alignment: .top,
                                    orientation: UIDeviceOrientation.landscapeLeft,
                                    geometry: geometry
                                )
                                
                                TextView(
                                    text: hasCameraMetadata ? detailsMetadataText : imageDetailsText,
                                    alignment: .bottom,
                                    orientation: UIDeviceOrientation.landscapeLeft,
                                    geometry: geometry
                                )
                            }
                        }
                    }
                    
                    if showControls {
                        ZStack {
                            Color.clear
                            
                            VStack {
                                Button(action: { onClose() }) {
                                    Circle()
                                        .fill(Color.black.opacity(0.4))
                                        .frame(width: 38, height: 38)
                                        .overlay(
                                            Image(systemName: "xmark")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                        .rotationEffect(orientationObserver.orientation.toLandscape)
                                }
                                
                                Spacer()
                            }
                            .padding(.top, 42)
                        }
                        
                        ZStack {
                            VStack {
                                Spacer()
                                HStack(spacing: 16) {
                                    Button(action: {
                                        aspectRatioMode.toggle()
                                    }) {
                                        ZStack {
                                            Circle()
                                                .fill(aspectRatioMode ? Color.blue.opacity(0.4) : Color.clear)
                                                .frame(width: 32, height: 32)
                                            
                                            Image(systemName: "square")
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundColor(.white)
                                        }
                                        .rotationEffect(orientationObserver.orientation.toLandscape)
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Circle())
                                    
                                    Button(action: {
                                        gridModeRawValue = gridMode.next().rawValue
                                    }) {
                                        ZStack {
                                            Circle()
                                                .fill(gridMode.color)
                                                .frame(width: 32, height: 32)
                                            
                                            Image(systemName: "grid")
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundColor(.white)
                                        }
                                        .rotationEffect(orientationObserver.orientation.toLandscape)
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Circle())
                                    
                                    Button(action: { textMode.toggle() }) {
                                        ZStack {
                                            Circle()
                                                .fill(textMode ? Color.blue.opacity(0.4) : Color.clear)
                                                .frame(width: 32, height: 32)
                                            
                                            Image(systemName: "textformat")
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundColor(.white)
                                        }
                                        .rotationEffect(orientationObserver.orientation.toLandscape)
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Circle())
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 32)
                                        .fill(Color.black.opacity(0.4))
                                )
                            }
                            .padding(.bottom, 42)
                        }
                    }
                }
            }
        }
        .statusBarHidden()
        .ignoresSafeArea()
    }
    
    private var hasCameraMetadata: Bool {
        !images[currentIndex].metadata.isEmpty
    }
    
    private var cameraMetadataText: String {
        let image = images[currentIndex]
        let meta = image.metadata
        
        func getString(_ key: String) -> String {
            if case let .string(value)? = meta[key] { return value }
            return ""
        }
        
        func getDouble(_ key: String) -> Double {
            if case let .double(value)? = meta[key] { return value }
            return 0
        }
        
        let aperture = CameraUtils.aperture(for: getString("aperture"))
        let colorFilter = CameraUtils.colorFilter(for: getString("colorFilter"))
        let ndFilter = CameraUtils.ndFilter(for: getString("ndFilter"))
        let filmSize = CameraUtils.filmSize(for: getString("filmSize"))
        let filmStock = CameraUtils.filmStock(for: getString("filmStock"))
        let shutter = CameraUtils.shutter(for: getString("shutter"))
        let focalLength = CameraUtils.focalLength(for: getString("focalLength"))
        
        let exposureCompensation = colorFilter.exposureCompensation + ndFilter.exposureCompensation
        
        let exposureText: String =
        "\(aperture.name) \(shutter.name)" +
        (exposureCompensation != 0
         ? " (\(exposureCompensation >= 0 ? "+" : "")\(String(format: "%.1f", exposureCompensation)))"
         : "")
        
        let colorText: String =
        !colorFilter.isNone
        ? "\(Int(filmStock.colorTemperature))k" +
        (colorFilter.colorTemperatureShift != 0
         ? " (\(colorFilter.colorTemperatureShift >= 0 ? "+" : "")\(colorFilter.colorTemperatureShift))"
         : "")
        : "Auto"
        
        let angle = filmSize.angleOfView(focalLength: focalLength.length).horizontal
        
        return(
        "\(Int(filmSize.width))x\(Int(filmSize.height))mm " +
        "(\(String(format: "%.1f", angle))°) " +
        "· \(String(format: "%.0f", filmStock.speed)) · " +
        "\(exposureText) · \(colorText)")
    }
    
    private var detailsMetadataText: String {
        let image = images[currentIndex]
        let meta = image.metadata

        func getDouble(_ key: String) -> Double? {
            if case let .double(value)? = meta[key] { return value }
            return nil
        }

        func getString(_ key: String) -> String? {
            if case let .string(value)? = meta[key] { return value }
            return nil
        }

        var focalText: String = ""
        var aspectText: String = ""

        if let focalString = getString("focalLength") {
            let focal = CameraUtils.focalLength(for: focalString)
            if focal.length > 0 {
                focalText = "Focal length: \(Int(focal.length))mm"
            }
        }

        if let aspectString = getString("aspectRatio") {
            let ar = CameraUtils.aspectRatio(for: aspectString)
            if ar.ratio > 0 {
                aspectText = String(format: "(%.2f)", ar.ratio)
            }
        }

        if !focalText.isEmpty, !aspectText.isEmpty {
            focalText += " \(aspectText)"
        }

        let roll = getDouble("deviceRoll")
        let tilt = getDouble("deviceTilt")
        var giroText: String = ""

        if let r = roll, let t = tilt {
            giroText = "Roll: \(Int(r))° · Tilt: \(Int(t))°"
        }

        if !focalText.isEmpty && !giroText.isEmpty {
            return "\(focalText) · \(giroText)"
        } else if !focalText.isEmpty {
            return focalText
        } else {
            return giroText
        }
    }

    private var imageNameText: String {
        let imageData = images[currentIndex]
        
        if let name = imageData.name, !name.isEmpty {
            return name
        }
        return imageData.metadata["filename"].flatMap {
            if case let .string(name) = $0 { return name }
            return nil
        } ?? "Untitled"
    }
    
    private var imageDetailsText: String {
        let imageData = images[currentIndex]

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let timestamp = formatter.string(from: imageData.timestamp)

        if let img = uiImages[safe: currentIndex] {
            let w = Int(img.size.width)
            let h = Int(img.size.height)
            return "\(timestamp) – \(w)x\(h)"
        }

        return timestamp
    }
    
    private var aspectRatioMetadataDouble: Double {
        let meta = images[currentIndex].metadata
    
        guard case let .string(label)? = meta["aspectRatio"] else {
            return 1.0
        }
        let aspect = CameraUtils.aspectRatio(for: label)
        return aspect.ratio == 0 ? 1.0 : aspect.ratio
    }
    
}
