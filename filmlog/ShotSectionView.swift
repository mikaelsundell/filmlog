// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI

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
                                radius: 2,
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
