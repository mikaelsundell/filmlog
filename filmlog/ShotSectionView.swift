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
        VStack(spacing: 16) {
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
                                radius: 4,
                                inner: 0.4,
                                outer: 0.995,
                                geometry: geometry
                            )
                        }
                    }
                    .id(shot.id)
                    .padding(3)
                } else {
                    Rectangle()
                    .fill(Color(red: 0.05, green: 0.05, blue: 0.05))
                    .overlay(
                        Text("No image")
                            .foregroundColor(.secondary)
                    )
                    .cornerRadius(4)
                        
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(shot.imageData?.original.map { $0.size.width / $0.size.height } ?? 3/2,
                         contentMode: .fit)
            .clipped()

            if let metadata = shot.imageData?.metadata, !metadata.isEmpty {
                MetadataView(imageData: shot.imageData)
                    .padding(-4)
            }

            if !isLocked {
                HStack(spacing: 16) {
                    Button {
                        showCamera = true
                    } label: {
                        Circle()
                            .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(.accentColor)
                                    .offset(y: -1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDeleteAlert = true
                    } label: {
                        Circle()
                            .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 24, weight: .medium))
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
        .transaction { $0.animation = nil } 
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
