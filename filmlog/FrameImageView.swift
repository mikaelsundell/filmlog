// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI

struct FrameImageView: View {
    var image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .onAppear {
                    debugPrintImageInfo(image: image, geometry: geometry)
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .padding()
                    .foregroundColor(.white)
            }
        }
    }

    /// Debug function to log image info
    private func debugPrintImageInfo(image: UIImage, geometry: GeometryProxy) {
        let sizePoints = image.size
        let scale = image.scale
        let sizePixels = CGSize(width: sizePoints.width * scale, height: sizePoints.height * scale)
        let orientation = image.imageOrientation

        print("""
        📷 FrameImageView Debug Info:
        - UIImage size (points): \(sizePoints.width)x\(sizePoints.height)
        - Scale factor: \(scale)
        - UIImage size (pixels): \(Int(sizePixels.width))x\(Int(sizePixels.height))
        - Orientation: \(orientation)
        - Displayed frame size: \(Int(geometry.size.width))x\(Int(geometry.size.height))
        """)
    }
}
