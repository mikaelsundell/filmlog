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
                        let width = geometry.size.width
                        let height = geometry.size.height

                        let imageSize = image.size
                        let adjustedSize = imageSize.isLandscape ? imageSize.switchOrientation() : imageSize

                        let padding: CGFloat = 10
                        let iw = width - padding * 2
                        let ih = height - padding * 2
                        let fit = min(iw / adjustedSize.width, ih / adjustedSize.height)

                        let frameWidth = adjustedSize.width * fit
                        let frameHeight = adjustedSize.height * fit
                        let frameSize = CGSize(width: frameWidth, height: frameHeight)

                        let rotation: Angle = imageSize.isLandscape ? .degrees(90) : .degrees(0)

                        ZStack {
                            ZStack {
                                ZStack {
                                    Image(uiImage: image)
                                        .scaleEffect(fit)
                                        .rotationEffect(rotation) // to potrait
                                }
                                .clipped()
                                .ignoresSafeArea()
                            }
                            .frame(width: width, height: height)
                            .position(x: width / 2, y: height / 2)
                            .ignoresSafeArea()

                            MaskView(
                                frameSize: frameSize,
                                aspectSize: frameSize,
                                inner: 0.4,
                                outer: 0.95,
                                geometry: geometry
                            )
                            .position(x: width / 2, y: height / 2)
                            
                            let aperture = CameraUtils.aperture(for: shot.aperture)
                            let colorFilter = CameraUtils.colorFilter(for: shot.colorFilter)
                            let ndFilter = CameraUtils.colorFilter(for: shot.ndFilter)
                            let filmSize = CameraUtils.filmSize(for: shot.filmSize)
                            let filmStock = CameraUtils.filmStock(for: shot.filmStock)
                            let shutter = CameraUtils.shutter(for: shot.shutter)
                            let focalLength = CameraUtils.focalLength(for: shot.focalLength)
                            
                            let colorTempText: String = !colorFilter.isNone
                                ? "\(Int(filmStock.colorTemperature + colorFilter.colorTemperatureShift))K (\(colorFilter.name))"
                                : " WB: Auto"

                            let exposureCompensation = colorFilter.exposureCompensation + ndFilter.exposureCompensation
                            let exposureText: String = (shot.deviceCameraMode != "auto")
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
                        }.ignoresSafeArea()
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
