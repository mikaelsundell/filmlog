// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Metal
import MetalKit
import simd

final class CameraRenderer: NSObject, MTKViewDelegate {
    public var shaderControls = PBRShaderControls()
    
    private let renderContext: RenderContext
    private let pbrRenderer: PBRRenderer
    private let camera: OrbitCamera

    init(view: MTKView) {
        guard let device = view.device else {
            fatalError("MTKView has no Metal device")
        }

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }

        self.camera = OrbitCamera(
            eye: SIMD3<Float>(0.0, -2.0, 1.0),
            target: SIMD3<Float>(0.0,  0.0, 0.65)
        )

        view.sampleCount = 1
        view.clearColor = MTLClearColor(
            red: 0.05,
            green: 0.05,
            blue: 0.05,
            alpha: 1.0
        )
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float

        self.renderContext = RenderContext(
            device: device,
            commandQueue: commandQueue,
            colorPixelFormat: view.colorPixelFormat,
            depthPixelFormat: view.depthStencilPixelFormat,
            sampleCount: view.sampleCount
        )

        self.pbrRenderer = PBRRenderer(renderContext: renderContext)

        super.init()

        view.delegate = self
        (view as? ModelView)?.camera = camera

        loadModel(named: "elf")
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else {
            return
        }

        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor =
            MTLClearColorMake(0.2, 0.2, 0.2, 1.0)

        guard let cmd = renderContext.commandQueue.makeCommandBuffer() else {
            return
        }

        let aspect = Float(
            view.drawableSize.width /
            max(view.drawableSize.height, 1.0)
        )

        let projection = simd_float4x4(
            perspectiveFov: .pi / 3,
            aspect: aspect,
            nearZ: 0.1,
            farZ: 100.0
        )

        pbrRenderer.cameraData = PBRRenderer.CameraData(
            projection: projection,
            viewMatrix: camera.viewMatrix,
            worldPosition: camera.position
        )
        
        pbrRenderer.shaderControls = shaderControls

        pbrRenderer.draw(
            with: cmd,
            descriptor: descriptor,
            drawableSize: view.drawableSize
        )

        cmd.present(drawable)
        cmd.commit()
    }

    func loadModel(named name: String) {
        guard let url = Bundle.main.url(
            forResource: "\(name)_basic_pbr",
            withExtension: "usdz"
        ) else {
            fatalError("\(name)_basic_pbr.usdz not found in app bundle")
        }
        pbrRenderer.loadModel(from: url)
    }
}
