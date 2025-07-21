// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import AVFoundation
import Combine

class OrientationObserver: ObservableObject {
    @Published var isLandscape: Bool = UIDevice.current.orientation.isLandscape
    private var cancellable: AnyCancellable?

    init(position: AVCaptureDevice.Position = .back) {
        cancellable = NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .compactMap { _ in
                let orientation = UIDevice.current.orientation
                guard orientation.isValidInterfaceOrientation else { return nil }
                return orientation.isLandscape
            }
            .assign(to: \.isLandscape, on: self)
    }
}

struct FrameHelper {
    static func calculateFrame(containerSize: CGSize,
                              focalLength: CGFloat,
                              filmSize: CameraOptions.FilmSize,
                              horizontalFOV: CGFloat) -> CGSize {
        let filmWidth = CGFloat(filmSize.width)
        let filmAspect = CGFloat(filmSize.aspectRatio)
        let filmHFOV = 2 * atan(filmWidth / (2 * focalLength))
        let frameHorizontal = containerSize.height * (tan(filmHFOV / 2) / tan((horizontalFOV * .pi / 180) / 2)) // potrait mode, height is native width
        let frameVertical = frameHorizontal / filmAspect
        return CGSize(width: frameVertical, height: frameHorizontal)
    }
}

struct FrameOverlay: View {
    let isLandscape: Bool
    let aspectRatio: CGFloat
    let focalLength: CGFloat
    let filmSize: CameraOptions.FilmSize
    let horizontalFOV: CGFloat

    var body: some View {
        GeometryReader { geo in
            let frameSize = FrameHelper.calculateFrame(
                containerSize: geo.size,
                focalLength: focalLength,
                filmSize: filmSize,
                horizontalFOV: horizontalFOV
            )

            ZStack {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: frameSize.width, height: frameSize.height)

                VStack(spacing: 4) {
                    Text("Film: \(Int(filmSize.width))mm x \(Int(filmSize.height))mm (\(String(format: "%.2f", filmSize.aspectRatio)))")
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .rotationEffect(isLandscape ? .degrees(-90) : .degrees(0))
                }
                .offset(
                    x: isLandscape ? -geo.size.width / 2 + 25 : 0,
                    y: isLandscape ? 0 : -geo.size.height / 2 + 120
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

struct CameraView: View {
    @Bindable var frame: Frame
    
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraModel = CameraModel()
    @State private var showLenses = false
    @State private var showAspectRatios = false
    
    @ObservedObject private var orientationObserver = OrientationObserver()

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: cameraModel.session)
               .animation(.easeInOut(duration: 0.3), value: orientationObserver.isLandscape)
               .ignoresSafeArea()
            
            GeometryReader { geometry in
                ZStack {
                    CameraPreview(session: cameraModel.session)
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 0.3), value: orientationObserver.isLandscape)
                    
                    FrameOverlay(
                        isLandscape: orientationObserver.isLandscape,
                        aspectRatio: cameraModel.aspectRatio,
                        focalLength: CameraOptions.focalLengths.first(where: { $0.label == frame.lensFocalLength })?.value ?? 0,
                        filmSize: CameraOptions.filmSizes.first(where: { $0.label == frame.filmSize })?.value ?? CameraOptions.FilmSize.defaultFilmSize,
                        horizontalFOV: cameraModel.horizontalFOV
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            
            ZStack {
                Color.clear
                VStack {
                    HStack {

                        HStack(spacing: 8) {
                            Button(action: { func1() }) {
                                Text("1")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                            Button(action: { func2() }) {
                                Text("2")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                        }
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

                        HStack(spacing: 8) {
                            Button(action: { func3() }) {
                                Text("3")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                            Button(action: { func4() }) {
                                Text("4")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                        }
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
    
    private func captureImage(image: UIImage) {
        let containerSize = UIScreen.main.bounds.size
        let filmSize = CameraOptions.filmSizes.first(where: { $0.label == frame.filmSize })?.value ?? CameraOptions.FilmSize.defaultFilmSize
        let focalLength = CameraOptions.focalLengths.first(where: { $0.label == frame.lensFocalLength })?.value ?? 0
        let frameSize = FrameHelper.calculateFrame(
            containerSize: containerSize,
            focalLength: focalLength,
            filmSize: filmSize,
            horizontalFOV: cameraModel.horizontalFOV
        )
        let croppedImage = cropImage(image, targetSize: frameSize, containerSize: containerSize, isLandscape: orientationObserver.isLandscape)
        onCapture(croppedImage)
        dismiss()
    }
    
    private func cropImage(_ image: UIImage,
                           targetSize: CGSize,
                           containerSize: CGSize,
                           isLandscape: Bool) -> UIImage {
        
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
            return UIImage(cgImage: nativeImage, scale: image.scale, orientation: .up)
        }
        
        let orientation: UIImage.Orientation = isLandscape ? .up : .right
        return UIImage(cgImage: targetImage, scale: image.scale, orientation: orientation)
    }

    
    @ViewBuilder
    private func focalLengthControls() -> some View {
        HStack(spacing: 4) {
            Button(action: {
                if let currentIndex = CameraOptions.focalLengths.firstIndex(where: { $0.label == frame.lensFocalLength }),
                   currentIndex > 0 {
                    frame.lensFocalLength = CameraOptions.focalLengths[currentIndex - 1].label
                }
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            Button(action: { showLenses.toggle() }) {
                Text("\(frame.lensFocalLength)")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .frame(width: 55)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(4)
                    .rotationEffect(orientationObserver.isLandscape ? .degrees(-90) : .zero)
            }
            Button(action: {
                if let currentIndex = CameraOptions.focalLengths.firstIndex(where: { $0.label == frame.lensFocalLength }),
                   currentIndex < CameraOptions.focalLengths.count - 1 {
                    frame.lensFocalLength = CameraOptions.focalLengths[currentIndex + 1].label
                }
            }) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
        }
    }
    
    @ViewBuilder
    private func aspectRatioControls() -> some View {
        HStack(spacing: 4) {
            Button(action: {
                if let currentIndex = CameraOptions.aspectRatios.firstIndex(where: { $0.label == frame.aspectRatio }),
                   currentIndex > 0 {
                    frame.aspectRatio = CameraOptions.aspectRatios[currentIndex - 1].label
                }
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            Button(action: { showAspectRatios.toggle() }) {
                Text("\(frame.aspectRatio)")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .frame(width: 55)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(4)
                    .rotationEffect(orientationObserver.isLandscape ? .degrees(-90) : .zero)
            }
            Button(action: {
                if let currentIndex = CameraOptions.aspectRatios.firstIndex(where: { $0.label == frame.aspectRatio }),
                   currentIndex < CameraOptions.aspectRatios.count - 1 {
                    frame.aspectRatio = CameraOptions.aspectRatios[currentIndex + 1].label
                }
            }) {
                Image(systemName: "chevron.right")
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
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

    func func1() {
        print("save stream and screenshot")
        cameraModel.capturePhotoAndSave()
        captureScreenshot()
    }
    func func2() { print("func2") }
    func func3() { print("func3") }
    func func4() { print("func4") }
}

extension CGSize {
    func landscape() -> CGSize {
        return CGSize(width: self.height, height: self.width)
    }
}

