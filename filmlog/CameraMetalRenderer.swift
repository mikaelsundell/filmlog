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
    private var offscreenTexture: MTLTexture?
    private var lutTexture: MTLTexture?
    private var vertexBuffer: MTLBuffer!
    private var captureRawData: [UInt8]? = nil
    
    private var pendingCapture: ((CGImage?) -> Void)?

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
        
        if let lutURL = Bundle.main.url(forResource: "CameraDisplay2383", withExtension: "cube") {
            self.lutTexture = setupLut(url: lutURL, device: device)
        } else {
            print("LUT file not found in bundle.")
        }
        
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
    
    func setupOffscreenTexture(device: MTLDevice, size: CGSize) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        offscreenTexture = device.makeTexture(descriptor: descriptor)
    }
    
    func setupLut(url: URL, device: MTLDevice) -> MTLTexture? {
        guard let contents = try? String(contentsOf: url) else {
            print("failed to read contents of LUT file.")
            return nil
        }

        var lutData: [SIMD3<Float>] = []
        var lutSize: Int = 0

        let lines = contents.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.uppercased().hasPrefix("LUT_3D_SIZE") {
                if let size = Int(trimmed.components(separatedBy: .whitespaces).last ?? "") {
                    lutSize = size
                    print("detected LUT size: \(lutSize)x\(lutSize)x\(lutSize)")
                } else {
                    print("could not parse LUT_3D_SIZE from line: \(line)")
                }
                continue
            }

            let comps = trimmed.components(separatedBy: .whitespaces).compactMap { Float($0) }
            if comps.count == 3 {
                lutData.append(SIMD3<Float>(comps[0], comps[1], comps[2]))
            }
        }

        let expectedCount = lutSize * lutSize * lutSize
        if lutSize == 0 || lutData.count != expectedCount {
            print("invalid LUT data: got \(lutData.count) entries, expected \(expectedCount) for size \(lutSize)")
            return nil
        }
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = .rgba32Float
        descriptor.textureType = .type3D
        descriptor.width = lutSize
        descriptor.height = lutSize
        descriptor.depth = lutSize
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            print("failed to create MTLTexture for LUT.")
            return nil
        }

        var rgbaData: [Float] = []
        rgbaData.reserveCapacity(expectedCount * 4)

        for (_, color) in lutData.enumerated() {
            rgbaData += [color.x, color.y, color.z, 1.0]
        }

        texture.replace(
            region: MTLRegionMake3D(0, 0, 0, lutSize, lutSize, lutSize),
            mipmapLevel: 0,
            slice: 0,
            withBytes: rgbaData,
            bytesPerRow: lutSize * 4 * MemoryLayout<Float>.size,
            bytesPerImage: lutSize * lutSize * 4 * MemoryLayout<Float>.size
        )

        return texture
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
    
    func captureTexture(completion: @escaping (CGImage?) -> Void) {
        pendingCapture = completion
    }
    
    var lastDrawTime: CFTimeInterval = 0
    var frameIntervals: [Double] = []
    let frameSampleCount = 60
    
    func draw(in view: MTKView) {
        guard let _ = yTexture, let _ = cbcrTexture else { return }
        
        guard let queue = queue,
              let pipeline = pipeline,
              let yTex = yTexture,
              let uvTex = cbcrTexture else {
            return
        }
        
        let now = CACurrentMediaTime()
        if lastDrawTime > 0 {
            let delta = (now - lastDrawTime) * 1000  // in milliseconds
            frameIntervals.append(delta)

            if frameIntervals.count == frameSampleCount {
                let average = frameIntervals.reduce(0, +) / Double(frameIntervals.count)
                print(String(format: "debug: frame time over %d frames: %.2f ms (%.2f FPS)", frameSampleCount, average, 1000.0 / average))
                frameIntervals.removeAll()
            }
        }
        lastDrawTime = now

        struct Uniforms {
            var viewSize: SIMD2<Float>
            var videoSize: SIMD2<Float>
        }

        var uniforms = Uniforms(
            viewSize: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            videoSize: SIMD2(Float(yTex.width), Float(yTex.height))
        )

        guard let cmd = queue.makeCommandBuffer() else { return }

        if let captureHandler = pendingCapture {
            if offscreenTexture == nil ||
                offscreenTexture!.width != Int(view.drawableSize.width) ||
                offscreenTexture!.height != Int(view.drawableSize.height) {
                setupOffscreenTexture(device: device, size: view.drawableSize)
            }
            
            let offscreenRPD = MTLRenderPassDescriptor()
            offscreenRPD.colorAttachments[0].texture = offscreenTexture
            offscreenRPD.colorAttachments[0].loadAction = .clear
            offscreenRPD.colorAttachments[0].storeAction = .store
            offscreenRPD.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

            if let offEnc = cmd.makeRenderCommandEncoder(descriptor: offscreenRPD) {
                offEnc.setRenderPipelineState(pipeline)
                offEnc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                offEnc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
                offEnc.setFragmentTexture(yTex, index: 0)
                offEnc.setFragmentTexture(uvTex, index: 1)
                offEnc.setFragmentTexture(lutTexture, index: 2)
                offEnc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                offEnc.endEncoding()
            }

            cmd.addCompletedHandler { [weak self] _ in
                guard let self = self, let texture = self.offscreenTexture else {
                    DispatchQueue.main.async { captureHandler(nil) }
                    return
                }

                let width = texture.width
                let height = texture.height
                let bytesPerRow = width * 4
                if captureRawData == nil || captureRawData!.count != bytesPerRow * height {
                    captureRawData = [UInt8](repeating: 0, count: bytesPerRow * height)
                }
                guard var rawData = captureRawData else {
                    DispatchQueue.main.async { captureHandler(nil) }
                    return
                }
                
                let region = MTLRegionMake2D(0, 0, width, height)
                texture.getBytes(&rawData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

                let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
                let bitmapInfo: CGBitmapInfo = [.byteOrder32Little,
                                                CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)]

                let context = CGContext(data: &rawData,
                                        width: width,
                                        height: height,
                                        bitsPerComponent: 8,
                                        bytesPerRow: bytesPerRow,
                                        space: colorSpace,
                                        bitmapInfo: bitmapInfo.rawValue)

                let cgImage = context?.makeImage()
                DispatchQueue.main.async { captureHandler(cgImage) }
            }

            self.pendingCapture = nil
        }

        guard let rpd = view.currentRenderPassDescriptor else { return }
        if let screenEnc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            screenEnc.setRenderPipelineState(pipeline)
            screenEnc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            screenEnc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
            screenEnc.setFragmentTexture(yTex, index: 0)
            screenEnc.setFragmentTexture(uvTex, index: 1)
            screenEnc.setFragmentTexture(lutTexture, index: 2)
            screenEnc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            screenEnc.endEncoding()
        }

        if let drawable = view.currentDrawable {
            cmd.present(drawable)
        }

        cmd.commit()
    }

    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
}
