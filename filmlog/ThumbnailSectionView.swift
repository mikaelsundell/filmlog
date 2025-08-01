// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI

struct ThumbnailSectionView: View {
    var data: Data?
    var label: String
    var isLocked: Bool = false
    var onImagePicked: (Data) -> Void

    @State private var showCamera = false
    @State private var showFullImage = false
    @State private var selectedItem: PhotosPickerItem? = nil

    var body: some View {
        VStack(spacing: 8) {
            if let data = data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .clipped()
                    .cornerRadius(10)
                    .onTapGesture {
                        showFullImage = true
                    }
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 180)
                    .overlay(Text("No image").foregroundColor(.gray))
                    .cornerRadius(10)
            }

            if !isLocked {
                HStack(spacing: 16) {
                    Button {
                        showCamera = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "camera")
                                .foregroundColor(.white)
                            Text("Take photo")
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo")
                                .foregroundColor(.white)
                            Text("From library")
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                let scaled = image.resized(maxDimension: 512) // for UI only
                if let data = scaled.jpegData(compressionQuality: 0.75) {
                    onImagePicked(data)
                }
                showCamera = false
            }
        }
        .fullScreenCover(isPresented: $showFullImage) {
                if let data = data, let uiImage = UIImage(data: data) {
                    FullScreenImageView(image: uiImage)
                }
        }
        .onChange(of: selectedItem) {
            if let selectedItem {
                Task {
                    if let data = try? await selectedItem.loadTransferable(type: Data.self) {
                        onImagePicked(data)
                    }
                }
            }
        }
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
