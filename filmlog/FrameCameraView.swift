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

struct FrameOverlay: View {
    let isLandscape: Bool
    let aspectRatio: CGFloat
    let focalLength: CGFloat
    let filmSize: CameraOptions.FilmSize
    let horizontalFOV: CGFloat

    private var filmWidth: CGFloat { CGFloat(filmSize.width) }
    private var filmHeight: CGFloat { CGFloat(filmSize.height) }
    private var filmAspect: CGFloat { CGFloat(filmSize.aspectRatio) }

    var body: some View {
        let filmHFOV = 2 * atan(filmWidth / (2 * focalLength))
        
        GeometryReader { geo in
            let maxSize = geo.size
            let frameHorizontal = maxSize.height * (tan(filmHFOV / 2) / tan((horizontalFOV * .pi / 180) / 2))
            let frameVertical = frameHorizontal / filmAspect

            ZStack {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1)
                    .frame(width: frameVertical, height: frameHorizontal)
                
                VStack(spacing: 4) {
                    Text("Film: \(Int(filmSize.width))x\(Int(filmSize.height)) (\(String(format: "%.2f", filmSize.aspectRatio)))")
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .rotationEffect(isLandscape ? .degrees(-90) : .degrees(0))
                }
                .offset(
                    x: isLandscape ? -maxSize.width / 2 + 40 : 0,
                    y: isLandscape ? 0 : -maxSize.height / 2 + 150
                )
            }
            .frame(width: maxSize.width, height: maxSize.height)
            .position(x: maxSize.width / 2, y: maxSize.height / 2)
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
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .onAppear {
            cameraModel.configure()
            cameraModel.onImageCaptured = { result in
                switch result {
                case .success(let image):
                    onCapture(image)
                    dismiss()
                case .failure(let error):
                    print("camera Error: \(error.localizedDescription)")
                }
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
