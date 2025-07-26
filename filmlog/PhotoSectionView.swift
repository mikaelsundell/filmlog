// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI

struct PhotoSectionView: View {
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
                if let data = image.jpegData(compressionQuality: 0.9) {
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
