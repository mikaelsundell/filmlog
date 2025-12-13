// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Metal
import MetalKit

final class MetalRenderer: NSObject, MTKViewDelegate {
    var shaderControls = MetalShaderControls()
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pbrRenderer: MetalPBRRenderer!
    private let camera: OrbitCamera
    
    init(mtkView: MTKView) {
        guard let device = mtkView.device else {
            fatalError("MTKView has no Metal device")
        }

        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        self.camera = OrbitCamera(
            eye: SIMD3<Float>(0.0, -2.0, 1.0),
            target: SIMD3<Float>(0.0,  0.0, 0.65)
        )

        super.init()

        mtkView.sampleCount = 4
        mtkView.clearColor = MTLClearColor(red: 0.01, green: 0.01, blue: 0.01, alpha: 1.0)
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.colorPixelFormat = .bgra8Unorm_srgb

        (mtkView as? MetalView)?.camera = camera
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        pbrRenderer = MetalPBRRenderer(device: device, mtkView: view)
        
        guard let url = Bundle.main.url(
            forResource: "shark_basic_pbr",
            withExtension: "usdz"
        ) else {
            fatalError("base_basic_pbr.usdz not found in app bundle")
        }

        pbrRenderer.loadModel(from: url)
    }

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor
        else { return }

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!

        if let pbrRenderer = pbrRenderer {
            pbrRenderer.shaderControls = shaderControls
            pbrRenderer.viewMatrix = camera.viewMatrix
            pbrRenderer.worldPosition = camera.position
            pbrRenderer.draw(with: encoder, in: view)
        }
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
