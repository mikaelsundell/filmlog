// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import MetalKit

struct CameraMetalPreview: UIViewRepresentable {
    let renderer: CameraMetalRenderer

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        // linear sRGB in the renderer; present in sRGB
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.preferredFramesPerSecond = 30
        renderer.attach(to: mtkView)
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) { }
}
