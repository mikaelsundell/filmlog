// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI

struct FrameSectionView: View {
    @Bindable var frame: Frame
    
    var isLocked: Bool = false
    var onImagePicked: (Data) -> Void

    @State private var showCamera = false
    @State private var showFullImage = false
    @State private var selectedItem: PhotosPickerItem? = nil

    var body: some View {
        VStack(spacing: 8) {
            if let imageData = frame.photoImage?.data, let uiImage = UIImage(data: imageData) {
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
                    .overlay(Text("No Image").foregroundColor(.gray))
                    .cornerRadius(10)
            }

            if !isLocked {
                HStack(spacing: 16) {
                    Button {
                        showCamera = true
                    } label: {
                        Label {
                            Text("Take photo")
                                .foregroundColor(.white)
                        } icon: {
                            Image(systemName: "camera")
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label {
                            Text("From library")
                                .foregroundColor(.white)
                        } icon: {
                            Image(systemName: "photo")
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(frame: frame) { image in
                if let data = image.jpegData(compressionQuality: 0.9) {
                    onImagePicked(data)
                }
            }
        }
        .fullScreenCover(isPresented: $showFullImage) {
            if let imageData = frame.photoImage?.data,
               let uiImage = UIImage(data: imageData) {
                FrameImageView(image: uiImage)
            } else {
                Text("No image available")
                    .font(.headline)
                    .padding()
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
