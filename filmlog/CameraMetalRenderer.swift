// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import AVFoundation
import Metal
import MetalKit
import CoreVideo

enum LUTType: String, CaseIterable {
    case kodakNeutral = "Kodak neutral"
    case kodakWarm = "Kodak warm"
    case fujiNeutral = "Fuji neutral"
    case fujiWarm = "Fuji warm"
    case bwNeutral = "BW neutral"
    case bwContrast = "BW contrast"
    case lookExposure = "Print exposure"
    case exposure = "Exposure"
    
    var filename: String {
        switch self {
        case .kodakNeutral: return "LutKodakNeutral"
        case .kodakWarm: return "LutKodakWarm"
        case .fujiNeutral: return "LutFujiNeutral"
        case .fujiWarm: return "LutFujiWarm"
        case .bwNeutral: return "LutBWNeutral"
        case .bwContrast: return "LutBWContrast"
        case .lookExposure: return "LutLookExposure"
        case .exposure: return "LutExposure"
        }
    }
}

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
    
    struct Uniforms {
        var viewSize: SIMD2<Float>
        var videoSize: SIMD2<Float>
        var isCapture: Int32
    }
    
    var currentLutType: LUTType = .kodakNeutral {
        didSet {
            loadCurrentLut()
        }
    }
    
    private var pendingCapture: ((CGImage?) -> Void)?
    
    func resetLutType() {
        currentLutType = .kodakNeutral
    }
    
    func setLutType(_ type: LUTType) {
        currentLutType = type
    }

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
    
        loadCurrentLut()
        
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
    
    private func loadCurrentLut() {
        guard let url = Bundle.main.url(forResource: currentLutType.filename, withExtension: "cube") else {
            print("lut file \(currentLutType.filename).cube not found in bundle.")
            lutTexture = nil
            return
        }
        lutTexture = setupLut(url: url, device: device)
    }
    
    private func setupOffscreenTexture(device: MTLDevice, size: CGSize) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        offscreenTexture = device.makeTexture(descriptor: descriptor)
    }
    
    private func setupLut(url: URL, device: MTLDevice) -> MTLTexture? {
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

        for color in lutData {
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
    
    private func encodeRenderPass(encoder: MTLRenderCommandEncoder,
                                  uniforms: inout Uniforms,
                                  yTex: MTLTexture,
                                  cbcrTex: MTLTexture) {
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        encoder.setFragmentTexture(yTex, index: 0)
        encoder.setFragmentTexture(cbcrTex, index: 1)
        encoder.setFragmentTexture(lutTexture, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
    
    private func makeCGImage(from texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        
        if captureRawData == nil || captureRawData!.count != bytesPerRow * height {
            captureRawData = [UInt8](repeating: 0, count: bytesPerRow * height)
        }
        guard var rawData = captureRawData else { return nil }
        
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
        return context?.makeImage()
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
    
    func drawImage(pixelBuffer: CVPixelBuffer, completion: @escaping (CGImage?) -> Void) {
        guard let cache = textureCache,
              let queue = queue,
              let pipeline = pipeline else {
            completion(nil)
            return
        }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let aspect = Double(width) / Double(height)
        
        var yTexRef: CVMetalTexture?
        var cTexRef: CVMetalTexture?

        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil,
                                                  .r8Unorm, width, height, 0, &yTexRef)
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil,
                                                  .rg8Unorm, width/2, height/2, 1, &cTexRef)

        guard let yTex = yTexRef.flatMap(CVMetalTextureGetTexture),
              let cbcrTex = cTexRef.flatMap(CVMetalTextureGetTexture) else {
            completion(nil)
            return
        }

        if offscreenTexture == nil ||
            offscreenTexture!.width != width ||
            offscreenTexture!.height != height {
            setupOffscreenTexture(device: device, size: CGSize(width: width, height: height))
        }

        var uniforms = Uniforms(
            viewSize: SIMD2(Float(width), Float(height)),
            videoSize: SIMD2(Float(width), Float(height)),
            isCapture: 1
        )

        guard let cmd = queue.makeCommandBuffer() else {
            completion(nil)
            return
        }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = offscreenTexture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
            enc.setFragmentTexture(yTex, index: 0)
            enc.setFragmentTexture(cbcrTex, index: 1)
            enc.setFragmentTexture(lutTexture, index: 2)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }

        cmd.addCompletedHandler { [weak self] _ in
            guard let self = self, let texture = self.offscreenTexture else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let w = texture.width
            let h = texture.height
            let bytesPerRow = w * 4

            if captureRawData == nil || captureRawData!.count != bytesPerRow * h {
                captureRawData = [UInt8](repeating: 0, count: bytesPerRow * h)
            }

            captureRawData!.withUnsafeMutableBytes { ptr in
                let region = MTLRegionMake2D(0, 0, w, h)
                texture.getBytes(ptr.baseAddress!, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
            }

            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

            if let ctx = captureRawData?.withUnsafeMutableBytes({ ptr -> CGContext? in
                return CGContext(data: ptr.baseAddress,
                                 width: w,
                                 height: h,
                                 bitsPerComponent: 8,
                                 bytesPerRow: bytesPerRow,
                                 space: colorSpace,
                                 bitmapInfo: bitmapInfo)
            }), let cgImage = ctx.makeImage() {
                DispatchQueue.main.async { completion(cgImage) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }

        cmd.commit()
    }

    func draw(in view: MTKView) {
        guard let yTex = yTexture,
              let cbcrTex = cbcrTexture,
              let queue = queue,
              let _ = pipeline else { return }

        var uniforms = Uniforms(
            viewSize: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            videoSize: SIMD2(Float(yTex.width), Float(yTex.height)),
            isCapture: 0
        )

        guard let cmd = queue.makeCommandBuffer() else { return }

        if let rpd = view.currentRenderPassDescriptor,
           let screenEnc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            encodeRenderPass(encoder: screenEnc, uniforms: &uniforms, yTex: yTex, cbcrTex: cbcrTex)
        }

        if let drawable = view.currentDrawable {
            cmd.present(drawable)
        }

        cmd.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
}
