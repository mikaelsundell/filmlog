// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI

struct PhotoMetadataView: View {
    var focalLength: String
    var aspectRatio: String
    var aperture: String
    var shutter: String
    var location: (latitude: Double, longitude: Double)?
    var deviceRoll: Double?
    var deviceTilt: Double?

    init(imageData: ImageData?) {
        func stringValue(_ key: String) -> String {
            if case let .string(value)? = imageData?.metadata[key] { return value }
            return ""
        }
        func doubleValue(_ key: String) -> Double? {
            if case let .double(value)? = imageData?.metadata[key] { return value }
            return nil
        }

        self.focalLength = stringValue("focalLength")
        self.aspectRatio = stringValue("aspectRatio")
        self.aperture = stringValue("aperture")
        self.shutter = stringValue("shutter")

        if let lat = doubleValue("latitude"),
           let lon = doubleValue("longitude") {
            self.location = (lat, lon)
        } else {
            self.location = nil
        }

        self.deviceRoll = doubleValue("deviceRoll")
        self.deviceTilt = doubleValue("deviceTilt")
    }

    var hasMetadata: Bool {
        !focalLength.isEmpty ||
        !aspectRatio.isEmpty ||
        !aperture.isEmpty ||
        !shutter.isEmpty ||
        location != nil ||
        deviceRoll != nil ||
        deviceTilt != nil
    }

    var body: some View {
        Group {
            if hasMetadata {
                VStack(alignment: .leading, spacing: 6) {
                    let items = [focalLength, aspectRatio, aperture, shutter].filter { !$0.isEmpty }
                    if !items.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            ForEach(Array(items.enumerated()), id: \.offset) { index, value in
                                if index > 0 {
                                    Text("· \(value)")
                                } else {
                                    Text(value)
                                }
                            }

                            Spacer()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }

                    if let roll = deviceRoll, let tilt = deviceTilt {
                        HStack(spacing: 6) {
                            Image(systemName: "gyroscope")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(String(format: "Roll: %.1f°, Tilt: %.1f°", roll, tilt))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }

                    if let loc = location {
                        HStack(spacing: 6) {
                            Text(String(format: "Lat: %.4f, Lon: %.4f", loc.latitude, loc.longitude))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                openInMaps(latitude: loc.latitude, longitude: loc.longitude)
                            } label: {
                                Image(systemName: "map")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("No metadata")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.1))
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func openInMaps(latitude: Double, longitude: Double) {
        if let url = URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)") {
            UIApplication.shared.open(url)
        }
    }
}

struct ShotSectionView: View {
    @Bindable var shot: Shot
    var isLocked: Bool = false
    var onImagePicked: (UIImage) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var showCamera = false
    @State private var showFullImage = false
    @State private var showDeleteAlert = false
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.9))
                    .overlay(
                        Rectangle()
                            .stroke(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                    )

                if let uiImage = shot.imageData?.thumbnail {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                        .onTapGesture { showFullImage = true }
                } else {
                    Text("No image")
                        .foregroundColor(.secondary)
                        .padding(6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .cornerRadius(0)
            .clipped()

            if let metadata = shot.imageData?.metadata, !metadata.isEmpty {
                PhotoMetadataView(imageData: shot.imageData)
            }

            if !isLocked {
                HStack(spacing: 20) {
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
                    .alert("Delete this shot?", isPresented: $showDeleteAlert) {
                        Button("Delete", role: .destructive) {
                            onDelete?()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This action cannot be undone.")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
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
