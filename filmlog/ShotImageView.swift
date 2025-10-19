// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI

struct ShotImageView: View {
    @Bindable var shot: Shot
    
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject private var orientationObserver = OrientationObserver()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            GeometryReader { geometry in
                ZStack {
                    if let image = shot.imageData?.original {
                        let landscapeImage = image.size.width > image.size.height
                            ? UIImage(cgImage: image.cgImage!, scale: image.scale, orientation: .right)
                            : image
                        
                        /*
                        ImageOverlay(
                            aspectRatio: CameraUtils.aspectRatio(for: shot.aspectRatio),
                            colorFilter: CameraUtils.colorFilter(for: shot.colorFilter),
                            ndFilter: CameraUtils.ndFilter(for: shot.ndFilter),
                            focalLength: CameraUtils.focalLength(for: shot.focalLength),
                            aperture: CameraUtils.aperture(for: shot.aperture),
                            shutter: CameraUtils.shutter(for: shot.shutter),
                            filmSize: CameraUtils.filmSize(for: shot.filmSize),
                            filmStock: CameraUtils.filmStock(for: shot.filmStock),
                            fieldOfView: shot.deviceFieldOfView,
                            cameraMode: shot.deviceCameraMode,
                            image: landscapeImage,
                            orientation: orientationObserver.orientation
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                         */
                    }
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            
            ZStack {
                Color.clear
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .frame(width: 42)
                        Spacer()
                    }
                    .padding(.top, 42)
                    .padding(.horizontal)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            HStack {
                Spacer()

                Circle()
                    .fill(Color.clear)
                    .frame(width: 48, height: 48)
                    .frame(width: 60)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .onAppear {
            
            if let image = shot.imageData?.original {
                print("📸 Debug Image Info:")
                print(" - Size: \(image.size.width)x\(image.size.height)")
                print(" - Scale: \(image.scale)")
                print(" - Orientation: \(image.imageOrientation.rawValue)")
                
                switch image.imageOrientation {
                case .up: print("   -> Orientation: up (default, no rotation)")
                case .down: print("   -> Orientation: down (180° rotated)")
                case .left: print("   -> Orientation: left (90° CCW)")
                case .right: print("   -> Orientation: right (90° CW)")
                case .upMirrored: print("   -> Orientation: upMirrored")
                case .downMirrored: print("   -> Orientation: downMirrored")
                case .leftMirrored: print("   -> Orientation: leftMirrored")
                case .rightMirrored: print("   -> Orientation: rightMirrored")
                @unknown default: print("   -> Orientation: unknown")
                }
            } else {
                print("⚠️ No image found in shot.imageData?.original")
            }
            
            
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
