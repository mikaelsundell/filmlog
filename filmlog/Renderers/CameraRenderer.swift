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
    
    struct RenderContext {
        let device: MTLDevice
        let commandQueue: MTLCommandQueue
        let colorPixelFormat: MTLPixelFormat
        let depthPixelFormat: MTLPixelFormat
    }
    
    struct CameraUniforms {
        var viewSize:  SIMD2<Float>
        var videoSize: SIMD2<Float>
        var offscreen: Int32
    }

    struct ModelUniforms {
        var mvp: simd_float4x4
        var normalMatrix: simd_float3x3
    }
    
    public var viewportSize: CGSize = .zero
    public var currentLutType: LUTType = .kodakNeutral { didSet { loadCurrentLut() } }
    
    public func resume() {
        paused = false
    }
    public func pause() {
        paused = true
    }

    private(set) weak var mtkView: MTKView?
    private var context: RenderContext?

    private var pipeline: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!
    private var yTexture: MTLTexture?
    private var cbcrTexture: MTLTexture?
    private var offscreenTexture: MTLTexture?
    private var offscreenDepthTexture: MTLTexture?
    private var lutTexture:  MTLTexture?
    private var textureCache: CVMetalTextureCache!

    private var captureRawData: [UInt8]? = nil
    private var pendingCapture: ((CGImage?) -> Void)?
    
    private var arRenderer: ARRenderer!
    private var pbrRenderer: PBRRenderer!
    private var paused = false
    
    // todo: test code
    private var testFileLoaded = false

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard let context else { return }
        viewportSize = size
        offscreenDepthTexture = makeDepthTexture(device: context.device, size: size)
    }
    
    func attach(to view: MTKView) {
        self.mtkView = view
        guard let device = view.device else { return }

        let commandQueue = device.makeCommandQueue()!
        
        view.depthStencilPixelFormat = .depth32Float
        view.delegate = self
        
        self.context = RenderContext(
            device: device,
            commandQueue: commandQueue,
            colorPixelFormat: view.colorPixelFormat,
            depthPixelFormat: .depth32Float
        )
        
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)

        try? makePipeline(pixelFormat: view.colorPixelFormat)

        let verts: [Float] = [
            -1, -1,  0, 1,
             1, -1,  1, 1,
            -1,  1,  0, 0,
             1,  1,  1, 0
        ]
        vertexBuffer = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Float>.size)
        
        arRenderer = ARRenderer(device: device, mtkView: view)
        pbrRenderer = PBRRenderer(device: device, mtkView: view)
        
        /*if !testFileLoaded {
            testFileLoaded = true
            if let firstFile = testLoadFirstFile() {
                print("loading first AR file:", firstFile.lastPathComponent)
                pbrRenderer.loadModel(from: firstFile)
            } else {
                print("no AR files found in shared storage")
            }
        }*/

        loadCurrentLut()
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let texture = yTexture,
              let descriptor = view.currentRenderPassDescriptor else { return }
        
        if (paused) { return }

        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let cmd = render(
            to: descriptor,
            viewSize: view.drawableSize,
            videoSize: CGSize(width: texture.width, height: texture.height)
        ) else {
            return
        }

        cmd.present(drawable)
        cmd.commit()
    }
    
    func drawOffscreen(pixelBuffer: CVPixelBuffer, completion: @escaping (CGImage?) -> Void) {
        guard let context else {
            completion(nil)
            return
        }
        guard let cache = textureCache else {
            completion(nil)
            return
        }
        
        let width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        
        if offscreenDepthTexture == nil ||
            offscreenDepthTexture!.width != width ||
            offscreenDepthTexture!.height != height {
            offscreenDepthTexture = makeDepthTexture(device: context.device, size: CGSize(width: width, height: height))
        }

        var yTexRef: CVMetalTexture?
        var cTexRef: CVMetalTexture?

        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, .r8Unorm,  width,  height, 0, &yTexRef)
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, .rg8Unorm, width/2, height/2, 1, &cTexRef)

        guard let yTex = yTexRef.flatMap(CVMetalTextureGetTexture),
              let cbcrTex = cTexRef.flatMap(CVMetalTextureGetTexture) else {
            completion(nil)
            return
        }

        yTexture = yTex
        cbcrTexture = cbcrTex

        if offscreenTexture == nil ||
            offscreenTexture!.width != width ||
            offscreenTexture!.height != height {
            offscreenTexture = makeOffscreenTexture(device: context.device, size: CGSize(width: width, height: height))
        }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = offscreenTexture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        rpd.depthAttachment.texture = offscreenDepthTexture
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1.0

        guard let cmd = render(
            to: rpd,
            viewSize: CGSize(width: width, height: height),
            videoSize: CGSize(width: width, height: height),
            offscreen: true
        ) else {
            completion(nil)
            return
        }

        cmd.addCompletedHandler { _ in
            let w = self.offscreenTexture!.width
            let h = self.offscreenTexture!.height
            let row = w * 4

            if self.captureRawData == nil || self.captureRawData!.count != row * h {
                self.captureRawData = .init(repeating: 0, count: row * h)
            }

            self.captureRawData!.withUnsafeMutableBytes { ptr in
                self.offscreenTexture!.getBytes(
                    ptr.baseAddress!,
                    bytesPerRow: row,
                    from: MTLRegionMake2D(0, 0, w, h),
                    mipmapLevel: 0
                )
            }

            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let info = CGImageAlphaInfo.premultipliedFirst.rawValue |
                       CGBitmapInfo.byteOrder32Little.rawValue

            if let ctx = self.captureRawData?.withUnsafeMutableBytes({ ptr -> CGContext? in
                CGContext(
                    data: ptr.baseAddress,
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: row,
                    space: cs,
                    bitmapInfo: info
                )
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
    
    func updateAREnvironmentTexture(_ texture: MTLTexture) {
        guard let renderer = pbrRenderer else { return }
        renderer.environmentTexture = texture
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
    
    private func render(to descriptor: MTLRenderPassDescriptor, viewSize: CGSize, videoSize: CGSize, offscreen: Bool = false) -> MTLCommandBuffer? {
        guard let context,
              let pipeline,
              let yTexture,
              let cbcrTexture else { return nil }

        guard let cmd = context.commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: descriptor) else { return nil }

        var cameraUniforms = CameraUniforms(
            viewSize: SIMD2(Float(viewSize.width), Float(viewSize.height)),
            videoSize: SIMD2(Float(yTexture.width), Float(yTexture.height)),
            offscreen: offscreen ? 1 : 0
        )
        
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        enc.setVertexBytes(&cameraUniforms, length: MemoryLayout<CameraUniforms>.size, index: 1)
        enc.setFragmentTexture(yTexture, index: 0)
        enc.setFragmentTexture(cbcrTexture, index: 1)
        enc.setFragmentTexture(lutTexture, index: 2)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        pbrRenderer?.draw(with: enc, drawableSize: viewSize)

        if !offscreen {
            arRenderer?.draw(with: enc, drawableSize: viewSize)
        }

        enc.endEncoding()
        return cmd
    }
    
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
        guard let context else { return }
        guard let url = Bundle.main.url(forResource: currentLutType.filename, withExtension: "cube") else {
            print("lut file \(currentLutType.filename).cube not found in bundle.")
            lutTexture = nil
            return
        }
        lutTexture = makeLut(url: url, device: context.device)
    }

    private func makeLut(url: URL, device: MTLDevice) -> MTLTexture? {
        guard let context else { return nil }
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
        guard let tex = context.device.makeTexture(descriptor: desc) else { return nil }

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
        guard let context else { return }
        let lib = try context.device.makeDefaultLibrary(bundle: .main)
        let vfn = lib.makeFunction(name: "cameraVS")!
        let ffn = lib.makeFunction(name: "nv12ToLinear709FS")!

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = pixelFormat
        desc.depthAttachmentPixelFormat = .depth32Float

        pipeline = try context.device.makeRenderPipelineState(descriptor: desc)
    }
    
    private func makeDepthTexture(
        device: MTLDevice,
        size: CGSize
    ) -> MTLTexture? {
        guard let context else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        desc.usage = [.renderTarget]
        return context.device.makeTexture(descriptor: desc)
    }
    
    private func makeOffscreenTexture(device: MTLDevice, size: CGSize) -> MTLTexture? {
        guard let context else { return nil }
        let fmt = mtkView?.colorPixelFormat ?? .bgra8Unorm_srgb
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: fmt,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        return context.device.makeTexture(descriptor: descriptor)
    }
}
