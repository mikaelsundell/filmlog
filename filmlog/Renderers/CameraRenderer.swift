// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import AVFoundation
import ARKit
import Metal
import MetalKit
import CoreVideo

enum LUTType: String, CaseIterable {
    case kodakNeutral = "Kodak neutral"
    case kodakWarm    = "Kodak warm"
    case fujiNeutral  = "Fuji neutral"
    case fujiWarm     = "Fuji warm"
    case bwNeutral    = "BW neutral"
    case bwContrast   = "BW contrast"
    case lookExposure = "Print exposure"
    case exposure     = "Exposure"
    
    var filename: String {
        switch self {
        case .kodakNeutral: return "LutKodakNeutral"
        case .kodakWarm:    return "LutKodakWarm"
        case .fujiNeutral:  return "LutFujiNeutral"
        case .fujiWarm:     return "LutFujiWarm"
        case .bwNeutral:    return "LutBWNeutral"
        case .bwContrast:   return "LutBWContrast"
        case .lookExposure: return "LutLookExposure"
        case .exposure:     return "LutExposure"
        }
    }
}

final class CameraRenderer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, MTKViewDelegate {
    struct CameraUniforms {
        var viewSize:  SIMD2<Float>
        var videoSize: SIMD2<Float>
        var isCapture: Int32
    }

    struct ModelUniforms {
        var mvp: simd_float4x4
        var normalMatrix: simd_float3x3
    }
    
    public var viewportSize: CGSize = .zero
    public var currentLutType: LUTType = .kodakNeutral { didSet { loadCurrentLut() } }
    
    private(set) weak var mtkView: MTKView?
    private var device: MTLDevice!
    private var queue:  MTLCommandQueue!

    private var pipeline: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var yTexture: MTLTexture?
    private var cbcrTexture: MTLTexture?
    private var offscreenTexture: MTLTexture?
    private var lutTexture:  MTLTexture?
    private var depthTexture:  MTLTexture?
    private var textureCache: CVMetalTextureCache!

    private var captureRawData: [UInt8]? = nil
    private var pendingCapture: ((CGImage?) -> Void)?
    
    private var arRenderer: ARRenderer!
    private var outputRenderer: OutputRenderer!
    private var pbrRenderer: PBRRenderer!
    
    // todo: test code
    private var testFileLoaded = false

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
        setupDepthTexture(size: size)
    }
    
    func attach(to view: MTKView) {
        self.mtkView = view
        guard let device = view.device else { return }
        self.device = device
        self.queue  = device.makeCommandQueue()
        
        arRenderer = ARRenderer(device: device, mtkView: view)
        outputRenderer = OutputRenderer(device: device, mtkView: view)
        pbrRenderer = PBRRenderer(device: device, mtkView: view)
        if !testFileLoaded {
            testFileLoaded = true
            if let firstFile = testLoadFirstFile() {
                print("loading first AR file:", firstFile.lastPathComponent)
                pbrRenderer.loadModel(from: firstFile)
            } else {
                print("no AR files found in shared storage")
            }
        }
        
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)

        try? makePipeline(pixelFormat: view.colorPixelFormat)

        let verts: [Float] = [
            -1, -1,  0, 1,
             1, -1,  1, 1,
            -1,  1,  0, 0,
             1,  1,  1, 0
        ]
        vertexBuffer = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Float>.size)
        
        view.depthStencilPixelFormat = .depth32Float
        view.delegate = self

        loadCurrentLut()
    }

    func draw(in view: MTKView) {
        guard let yTexture = yTexture,
              let cbcrTexture = cbcrTexture,
              let queue = queue,
              let pipeline = pipeline,
              let rpd = view.currentRenderPassDescriptor else { return }

        if depthTexture == nil ||
            depthTexture!.width  != Int(view.drawableSize.width) ||
            depthTexture!.height != Int(view.drawableSize.height) {
            setupDepthTexture(size: view.drawableSize)
        }
        rpd.depthAttachment.texture = depthTexture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let cmd = queue.makeCommandBuffer(),
              let encoder = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        var cameraUniforms = CameraUniforms(
            viewSize: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            videoSize: SIMD2(Float(yTexture.width), Float(yTexture.height)),
            isCapture: 0
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&cameraUniforms, length: MemoryLayout<CameraUniforms>.size, index: 1)
        encoder.setFragmentTexture(yTexture, index: 0)
        encoder.setFragmentTexture(cbcrTexture, index: 1)
        encoder.setFragmentTexture(lutTexture, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        // renderers
        if let pbrRenderer = pbrRenderer {
            pbrRenderer.draw(with: encoder, in: view)
        }
        
        if let arRenderer = arRenderer {
            arRenderer.draw(with: encoder, in: view)
        }
        
        encoder.endEncoding()
        if let drawable = view.currentDrawable { cmd.present(drawable) }
        cmd.commit()
    }
    
    func drawImage(pixelBuffer: CVPixelBuffer, completion: @escaping (CGImage?) -> Void) {
        guard let cache = textureCache,
              let queue = queue,
              let _ = pipeline else { completion(nil); return }

        let width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        var yTexRef: CVMetalTexture?
        var cTexRef: CVMetalTexture?

        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, .r8Unorm,  width,  height, 0, &yTexRef)
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, .rg8Unorm, width/2, height/2, 1, &cTexRef)

        guard let yTex = yTexRef.flatMap(CVMetalTextureGetTexture),
              let cbcrTex = cTexRef.flatMap(CVMetalTextureGetTexture) else { completion(nil); return }

        if offscreenTexture == nil ||
            offscreenTexture!.width  != width ||
            offscreenTexture!.height != height {
            setupOffscreenTexture(device: device, size: CGSize(width: width, height: height))
        }

        var uniforms = CameraUniforms(viewSize: SIMD2(Float(width), Float(height)),
                                  videoSize: SIMD2(Float(width), Float(height)),
                                  isCapture: 1)

        guard let cmd = queue.makeCommandBuffer() else { completion(nil); return }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture    = offscreenTexture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&uniforms, length: MemoryLayout<CameraUniforms>.size, index: 1)
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
            let w = texture.width, h = texture.height, row = w * 4
            if captureRawData == nil || captureRawData!.count != row * h {
                captureRawData = .init(repeating: 0, count: row * h)
            }
            captureRawData!.withUnsafeMutableBytes { ptr in
                texture.getBytes(ptr.baseAddress!, bytesPerRow: row,
                                 from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            }
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            if let ctx = captureRawData?.withUnsafeMutableBytes({ ptr -> CGContext? in
                CGContext(data: ptr.baseAddress, width: w, height: h,
                          bitsPerComponent: 8, bytesPerRow: row,
                          space: cs, bitmapInfo: info)
            }), let cg = ctx.makeImage() {
                DispatchQueue.main.async { completion(cg) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
        cmd.commit()
    }
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer),
              let cache = textureCache else { return }

        let w = CVPixelBufferGetWidthOfPlane(pb, 0)
        let h = CVPixelBufferGetHeightOfPlane(pb, 0)
        var yRef: CVMetalTexture?
        var cRef: CVMetalTexture?

        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .r8Unorm,  w,   h,   0, &yRef)
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .rg8Unorm, w/2, h/2, 1, &cRef)

        if let yRef, let cRef {
            yTexture    = CVMetalTextureGetTexture(yRef)
            cbcrTexture = CVMetalTextureGetTexture(cRef)
        }
    }
    
    func captureAROutput(pixelBuffer: CVPixelBuffer) {
        guard let cache = textureCache else { return }
        let w = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let h = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)

        var yRef: CVMetalTexture?
        var cRef: CVMetalTexture?

        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, .r8Unorm,  w,   h,   0, &yRef)
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, .rg8Unorm, w/2, h/2, 1, &cRef)

        if let yRef, let cRef {
            yTexture    = CVMetalTextureGetTexture(yRef)
            cbcrTexture = CVMetalTextureGetTexture(cRef)
        }
    }
    
    func updateARPlaneTransform(_ transform: simd_float4x4) {
        guard let renderer = arRenderer else { return }
        renderer.planeTransform = transform
    }
    
    func updateARCamera(_ camera: ARCamera) {
        guard let view = mtkView,
              let renderer = arRenderer,
              let orientation = view.window?.windowScene?.interfaceOrientation else { return }

        let resolution = SIMD2<Float>(
            Float(camera.imageResolution.width),
            Float(camera.imageResolution.height)
        )

        let projection = camera.projectionMatrix(
            for: orientation,
            viewportSize: view.drawableSize,
            zNear: 0.01,
            zFar: 100.0
        )
        let viewM = camera.viewMatrix(for: orientation)
        
        renderer.cameraData = ARRenderer.CameraData(
            resolution: resolution,
            intrinsics: camera.intrinsics,
            transform: simd_inverse(viewM),
            projection: projection
        )
    }
    
    func clearARCamera() {
        guard let renderer = arRenderer else { return }
        renderer.cameraData = nil
    }
    
    func setLutType(_ type: LUTType) { currentLutType = type }
    
    private func resetLutType() { currentLutType = .kodakNeutral }
    
    private func testLoadFirstFile() -> URL? {
        let dir = SharedStorage.directory(for: .ar)
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        let allowedExtensions = SharedStorageKind.ar.supportedExtensions
        return items.first { allowedExtensions.contains($0.pathExtension.lowercased()) }
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
            if trimmed.uppercased().hasPrefix("LUT_3D_SIZE"),
               let size = Int(trimmed.components(separatedBy: .whitespaces).last ?? "") {
                lutSize = size; continue
            }
            let comps = trimmed.split(whereSeparator: \.isWhitespace).compactMap { Float($0) }
            if comps.count == 3 { lutData.append(.init(comps[0], comps[1], comps[2])) }
        }

        let expected = lutSize * lutSize * lutSize
        guard lutSize > 0, lutData.count == expected else {
            print("invalid LUT data")
            return nil
        }

        let desc = MTLTextureDescriptor()
        desc.pixelFormat = .rgba32Float
        desc.textureType = .type3D
        desc.width = lutSize; desc.height = lutSize; desc.depth = lutSize
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        var rgba: [Float] = []
        rgba.reserveCapacity(expected * 4)
        for c in lutData { rgba += [c.x, c.y, c.z, 1.0] }

        tex.replace(region: MTLRegionMake3D(0, 0, 0, lutSize, lutSize, lutSize),
                    mipmapLevel: 0, slice: 0,
                    withBytes: rgba,
                    bytesPerRow: lutSize * 4 * MemoryLayout<Float>.size,
                    bytesPerImage: lutSize * lutSize * 4 * MemoryLayout<Float>.size)
        return tex
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
    
    private func setupDepthTexture(size: CGSize) {
        guard let device else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                            width: Int(size.width),
                                                            height: Int(size.height),
                                                            mipmapped: false)
        desc.usage = [.renderTarget]
        depthTexture = device.makeTexture(descriptor: desc)
    }
}
