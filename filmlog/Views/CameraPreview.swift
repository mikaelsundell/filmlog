// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import MetalKit

struct CameraPreview: UIViewRepresentable {
    typealias UIViewType = MTKView

    @ObservedObject var cameraModel: CameraModel

    init(cameraModel: CameraModel) {
        self.cameraModel = cameraModel
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.framebufferOnly = false
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.preferredFramesPerSecond = 30
        cameraModel.attachRenderer(to: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
