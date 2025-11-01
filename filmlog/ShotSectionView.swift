// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI

struct ImageMetadataView: View {
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

struct ShotSectionView: View {
    @Bindable var shot: Shot
    var isLocked: Bool = false
    var onImagePicked: (UIImage) -> Void

    @State private var showCamera = false
    @State private var showFullImage = false
    @State private var showDeleteAlert = false
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Color.black
                if let image = shot.imageData?.thumbnail {
                    GeometryReader { geometry in
                        let container = geometry.size
                        let imageSize = image.size
                        
                        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
                        let displayedSize = imageSize * scale

                        let filmSize = CameraUtils.filmSize(for: shot.filmSize)
                        let aspectRatio = CameraUtils.aspectRatio(for: shot.aspectRatio)
                        let aspectFrame = Projection.frameForAspectRatio(
                            size: displayedSize.toLandscape(), // match camera
                            aspectRatio: aspectRatio.ratio > 0.0 ? aspectRatio.ratio : filmSize.aspectRatio
                        )

                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .contentShape(Rectangle())
                                .onTapGesture { showFullImage = true }

                            MaskView(
                                frameSize: imageSize.isLandscape ? displayedSize : displayedSize.toPortrait(),
                                aspectSize: imageSize.isLandscape ? aspectFrame : aspectFrame.toPortrait(),
                                inner: 0.4,
                                outer: 0.995,
                                geometry: geometry
                            )
                        }
                    }
                    .id(shot.id)
                } else {
                    Text("No image")
                        .foregroundColor(.secondary)
                        .padding(6)
                        
                }
            }
            .frame(height: 220)
            .cornerRadius(2)
            .padding(.top, 4)
            .clipped()

            if let metadata = shot.imageData?.metadata, !metadata.isEmpty {
                ImageMetadataView(imageData: shot.imageData)
            }

            if !isLocked {
                HStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.accentColor)
                                    .offset(y: -1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDeleteAlert = true
                    } label: {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(shot.imageData == nil)
                    .alert("Delete this image?", isPresented: $showDeleteAlert) {
                        Button("Delete", role: .destructive) {
                            shot.deleteImage(context: modelContext)
                            try? modelContext.save()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This action cannot be undone.")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            ShotViewfinderView(shot: shot) { image in
                onImagePicked(image)
            }
        }
        .fullScreenCover(isPresented: $showFullImage) {
            ShotImageView(shot: shot)
        }
    }
}
