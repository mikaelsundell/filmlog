// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import AVFoundation
import Metal
import MetalKit
import CoreVideo

class CameraMetalRenderer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, MTKViewDelegate {
    private(set) weak var mtkView: MTKView?
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var pipeline: MTLRenderPipelineState!
    private var textureCache: CVMetalTextureCache!
    private var yTexture: MTLTexture?
    private var cbcrTexture: MTLTexture?

    // Simple fullscreen quad
    private var vertexBuffer: MTLBuffer!

    func attach(to view: MTKView) {
        self.mtkView = view
        guard let device = view.device else { return }
        self.device = device
        self.queue = device.makeCommandQueue()

        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)

        let lib = try! device.makeDefaultLibrary(bundle: .main)
        let vfn = lib.makeFunction(name: "fullscreenVS")!
        let ffn = lib.makeFunction(name: "nv12ToLinear709FS")!

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("failed to create pipeline: \(error.localizedDescription)")
        }

        let verts: [Float] = [
            -1, -1,  0, 1,
             1, -1,  1, 1,
            -1,  1,  0, 0,
             1,  1,  1, 0
        ]
        vertexBuffer = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Float>.size, options: [])
        view.delegate = self
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer),
              let cache = textureCache else { return }

        let width  = CVPixelBufferGetWidthOfPlane(pb, 0)
        let height = CVPixelBufferGetHeightOfPlane(pb, 0)
        var yTexRef: CVMetalTexture?
        var cTexRef: CVMetalTexture?

        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil,
                                                  .r8Unorm, width, height, 0, &yTexRef)
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil,
                                                  .rg8Unorm, width/2, height/2, 1, &cTexRef)

        if let yRef = yTexRef, let cRef = cTexRef {
            yTexture = CVMetalTextureGetTexture(yRef)
            cbcrTexture = CVMetalTextureGetTexture(cRef)
        }
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let queue = queue,
              let pipeline = pipeline,
              let yTex = yTexture,
              let uvTex = cbcrTexture else {
            return
        }

        struct Uniforms {
            var viewSize: SIMD2<Float>
            var videoSize: SIMD2<Float>
        }

        var uniforms = Uniforms(
            viewSize: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            videoSize: SIMD2(Float(yTex.width), Float(yTex.height))
        )

        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)!
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        enc.setFragmentTexture(yTex, index: 0)
        enc.setFragmentTexture(uvTex, index: 1)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
}
