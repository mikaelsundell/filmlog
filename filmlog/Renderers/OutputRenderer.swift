// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import MetalKit

class OutputRenderer {
    private(set) weak var mtkView: MTKView?
    private var device: MTLDevice!
    private var pipeline: MTLRenderPipelineState?
    
    init(device: MTLDevice, mtkView: MTKView) {
        self.device = device
        self.mtkView = mtkView
    }
    
    func draw(with encoder: MTLRenderCommandEncoder, in view: MTKView) {
    }
    
    private func makePipeline(pixelFormat: MTLPixelFormat) throws {
        let lib = try device.makeDefaultLibrary(bundle: .main)
        let vfn = lib.makeFunction(name: "cameraVS")!
        let ffn = lib.makeFunction(name: "nv12ToLinear709FS")!

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = pixelFormat
        desc.depthAttachmentPixelFormat = .depth32Float

        pipeline = try device.makeRenderPipelineState(descriptor: desc)
    }
}
