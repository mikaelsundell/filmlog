// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import MetalKit
import ModelIO

class PBRRenderer {
    struct CameraData {
        var projection: simd_float4x4
        var viewMatrix: simd_float4x4
        var worldPosition: SIMD3<Float>
    }
    
    struct ModelUniforms {
        var modelMatrix: simd_float4x4
        var mvp: simd_float4x4
        var normalMatrix: simd_float3x3
        var cameraWorldPos: SIMD3<Float>
        var _pad0: Float = 0 // 16-byte alignment for Metal
    }
    
    struct FragmentUniforms {
        var baseColorFactor: SIMD4<Float>
        var metallicFactor: Float
        var roughnessFactor: Float
        var hasBaseColorTexture: UInt32
        var hasMetallicTexture: UInt32
        var hasRoughnessTexture: UInt32
        var hasNormalTexture: UInt32
    }
    
    struct ShaderControlsUniforms {
        var keyIntensity: Float
        var ambientIntensity: Float
        var specularIntensity: Float
        var roughnessBias: Float
        var topLightIntensity: Float
    }
    
    struct ShadowDepthUniforms {
        var lightMVP: simd_float4x4
    }
    
    struct BlurUniforms {
        var direction: SIMD2<Float>
        var radius: Float
        var _pad: Float = 0
    }

    struct GroundUniforms {
        var mvp: simd_float4x4
        var modelMatrix: simd_float4x4
        var lightVP: simd_float4x4
        var baseColor: SIMD4<Float>
        var shadowStrength: Float
        var maxHeight: Float
        var cameraWorldPos: SIMD3<Float>
        var _pad0: SIMD3<Float> = .zero
    }

    public var model: PBRModel?
    public var cameraData: CameraData?
    public var shaderControls = PBRShaderControls()
    public var environmentTexture: MTLTexture?
    
    private var renderContext: RenderContext
    
    private var pbrPipeline: MTLRenderPipelineState!
    private var shadowDepthPipeline: MTLRenderPipelineState!
    private var contactShadowMaskPipeline: MTLRenderPipelineState!
    private var blurPipeline: MTLRenderPipelineState!
    private var groundPipeline: MTLRenderPipelineState!

    private let depthWriteState: MTLDepthStencilState
    private let noDepthState: MTLDepthStencilState
    
    private var samplerState: MTLSamplerState
    private var shadowSamplerState: MTLSamplerState

    private var shadowMaskTexture: MTLTexture!
    private var shadowMaskBlurTemp: MTLTexture!
    private var shadowMaskBlurred: MTLTexture!
    
    private var shadowDepthTexture: MTLTexture!
    private var shadowPassDesc: MTLRenderPassDescriptor!
    private var shadowMapSize: Int = 1024
    
    private var shadowPlaneZ: Float = 0.0
    private var shadowStrength: Float = 0.50
    private var groundSizeMultiplier: Float = 1.0
    
    private var groundVertexBuffer: MTLBuffer
    
    init(renderContext: RenderContext) {
        self.renderContext = renderContext

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        self.depthWriteState = renderContext.device.makeDepthStencilState(descriptor: depthDesc)!

        let noDepthDesc = MTLDepthStencilDescriptor()
        noDepthDesc.depthCompareFunction = .always
        noDepthDesc.isDepthWriteEnabled = false
        self.noDepthState = renderContext.device.makeDepthStencilState(descriptor: noDepthDesc)!

        let samp = MTLSamplerDescriptor()
        samp.minFilter = .linear
        samp.magFilter = .linear
        samp.mipFilter = .linear
        samp.sAddressMode = .repeat
        samp.tAddressMode = .repeat
        self.samplerState = renderContext.device.makeSamplerState(descriptor: samp)!

        let shadowSamp = MTLSamplerDescriptor()
        shadowSamp.minFilter = .linear
        shadowSamp.magFilter = .linear
        shadowSamp.mipFilter = .notMipmapped
        shadowSamp.sAddressMode = .clampToEdge
        shadowSamp.tAddressMode = .clampToEdge
        self.shadowSamplerState = renderContext.device.makeSamplerState(descriptor: shadowSamp)!

        let groundVerts: [SIMD3<Float>] = [
            [-1, -1, 0], [ 1, -1, 0], [-1,  1, 0],
            [ 1, -1, 0], [ 1,  1, 0], [-1,  1, 0],
        ]

        self.groundVertexBuffer = renderContext.device.makeBuffer(
            bytes: groundVerts,
            length: groundVerts.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        )!
        self.groundVertexBuffer.label = "GroundQuadVB"

        makeShadowMapResources()
    }
    
    func loadModel(from url: URL)
    {
        let materialLoader = PBRMaterialLoader(device: self.renderContext.device)
        let modelFactory = PBRModelLoader(
            device: self.renderContext.device,
            materialLoader: materialLoader
        )
        do {
            let loadedModel = try modelFactory.loadModel(from: url)
            self.model = loadedModel
            
            if self.pbrPipeline == nil {
            self.pbrPipeline =
                try makePBRPipeline(
                    vertexDescriptor: loadedModel.vertexDescriptor,
                    vertexFunction: "modelVS",
                    fragmentFunction: "modelFS"
                )
                
                self.blurPipeline =
                try makeBlurPipeline(fragmentFunction: "blurFS")
                
                self.shadowDepthPipeline =
                try makeShadowDepthPipeline(
                    vertexDescriptor: loadedModel.vertexDescriptor,
                    vertexFunction: "shadowDepthVS",
                    fragmentFunction: "shadowDepthFS"
                )
                
                self.contactShadowMaskPipeline =
                try makeContactShadowMaskPipeline(
                    vertexFunction: "groundVS",
                    fragmentFunction: "shadowMaskFS"
                )
                
                self.groundPipeline =
                try makeGroundPipeline(
                    vertexFunction: "groundVS",
                    fragmentFunction: "groundFS"
                )
            }
        }
        catch {
            print("failed to load model: \(error)")
        }
    }
    
    func draw(with cmd: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor, drawableSize: CGSize) {
        guard let cameraData,
              let model,
              let pbrPipeline else { return }

        print("draw...")
        
        renderShadowMap(with: cmd)
        
        if shadowMaskTexture == nil ||
            shadowMaskTexture.width  != Int(drawableSize.width) ||
            shadowMaskTexture.height != Int(drawableSize.height) {
            makeContactShadowTextures(size: drawableSize)
        }

        let aspect = Float(drawableSize.width / max(drawableSize.height, 1))
        let projection = simd_float4x4(
            perspectiveFov: .pi / 3,
            aspect: aspect,
            nearZ: 0.1,
            farZ: 100.0
        )

        let localViewMatrix = cameraData.viewMatrix
        let cameraWorldPos  = cameraData.worldPosition
        let globalModelScale = simd_float4x4(scale: 1.00)

        let (heightVP, modelCenter, footprint, maxHeight) =
            model.heightShadowVP(shadowPlaneZ: shadowPlaneZ)

        renderShadowMask(
            commandBuffer: cmd,
            projection: projection,
            viewMatrix: localViewMatrix,
            lightVP: heightVP,
            center: modelCenter,
            footprintRadius: footprint,
            maxHeight: maxHeight
        )

        let blurRadius: Float = 4.0
        if blurPipeline != nil {
            
            let r0: Float = blurRadius
            let r1: Float = blurRadius * 0.4

            renderBlur(
                commandBuffer: cmd,
                src: shadowMaskTexture,
                dst: shadowMaskBlurTemp,
                direction: SIMD2<Float>(1, 0),
                radius: r0
            )
            
            renderBlur(
                commandBuffer: cmd,
                src: shadowMaskBlurTemp,
                dst: shadowMaskBlurred,
                direction: SIMD2<Float>(0, 1),
                radius: r0
            )

            renderBlur(
                commandBuffer: cmd,
                src: shadowMaskBlurred,
                dst: shadowMaskBlurTemp,
                direction: SIMD2<Float>(1, 0),
                radius: r1
            )
            renderBlur(
                commandBuffer: cmd,
                src: shadowMaskBlurTemp,
                dst: shadowMaskBlurred,
                direction: SIMD2<Float>(0, 1),
                radius: r1
            )
        }

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        enc.setDepthStencilState(depthWriteState)
        enc.setCullMode(.none)
        
        drawGround(
            encoder: enc,
            projection: projection,
            viewMatrix: localViewMatrix,
            lightVP: heightVP,
            center: modelCenter,
            footprintRadius: footprint,
            maxHeight: maxHeight
        )

        enc.setRenderPipelineState(pbrPipeline)
        enc.setFragmentSamplerState(samplerState, index: 0)

        if let env = environmentTexture {
            enc.setFragmentTexture(env, index: 9)
        }

        renderMeshes(
            encoder: enc,
            model: model,
            projection: projection,
            viewMatrix: localViewMatrix,
            globalModelScale: globalModelScale,
            cameraWorldPos: cameraWorldPos
        )

        enc.endEncoding()
    }

    private func drawGround(
        encoder: MTLRenderCommandEncoder,
        projection: simd_float4x4,
        viewMatrix: simd_float4x4,
        lightVP: simd_float4x4,
        center: SIMD3<Float>,
        footprintRadius: Float,
        maxHeight: Float
    ) {
        let r = max(footprintRadius, 0.25) * groundSizeMultiplier
        let groundModel =
            simd_float4x4(translation: [center.x, center.y, shadowPlaneZ]) *
            simd_float4x4(scale: [r, r, 1])

        let mvp = projection * viewMatrix * groundModel

        var gu = GroundUniforms(
            mvp: mvp,
            modelMatrix: groundModel,
            lightVP: lightVP,
            baseColor: [1, 1, 1, 1],
            shadowStrength: shadowStrength,
            maxHeight: maxHeight,
            cameraWorldPos: cameraData!.worldPosition
        )

        encoder.setRenderPipelineState(groundPipeline)
        encoder.setVertexBuffer(groundVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&gu,
            length: MemoryLayout<GroundUniforms>.stride,
            index: 1)

        encoder.setFragmentTexture(shadowMaskBlurred, index: 0)
        encoder.setFragmentSamplerState(shadowSamplerState, index: 0)
        encoder.setFragmentBytes(&gu,
            length: MemoryLayout<GroundUniforms>.stride,
            index: 1)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
    
    private func renderBlur(
        commandBuffer: MTLCommandBuffer,
        src: MTLTexture,
        dst: MTLTexture,
        direction: SIMD2<Float>,
        radius: Float
    ) {
        guard let blurPipeline else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = dst
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
        enc.setRenderPipelineState(blurPipeline)
        enc.setFragmentTexture(src, index: 0)
        enc.setFragmentSamplerState(samplerState, index: 0)

        var bu = BlurUniforms(direction: direction, radius: radius)
        enc.setFragmentBytes(&bu,
            length: MemoryLayout<BlurUniforms>.stride,
            index: 0)

        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }
    
    private func renderShadowMap(with cmd: MTLCommandBuffer) {
        guard let model else { return }

        let (heightVP, _, _, _) = model.heightShadowVP(shadowPlaneZ: shadowPlaneZ)

        let enc = cmd.makeRenderCommandEncoder(descriptor: shadowPassDesc)!
        enc.setRenderPipelineState(shadowDepthPipeline)
        enc.setDepthStencilState(depthWriteState)
        enc.setCullMode(.none)

        for mesh in model.meshes {
            var su = ShadowDepthUniforms(lightMVP: heightVP * mesh.transform)

            if let vb0 = mesh.mesh.vertexBuffers.first {
                enc.setVertexBuffer(vb0.buffer, offset: vb0.offset, index: 0)
            }

            enc.setVertexBytes(&su,
                length: MemoryLayout<ShadowDepthUniforms>.stride,
                index: 1)

            for sub in mesh.mesh.submeshes {
                enc.drawIndexedPrimitives(
                    type: sub.primitiveType,
                    indexCount: sub.indexCount,
                    indexType: sub.indexType,
                    indexBuffer: sub.indexBuffer.buffer,
                    indexBufferOffset: sub.indexBuffer.offset
                )
            }
        }

        enc.endEncoding()
    }
    
    private func renderShadowMask(
        commandBuffer: MTLCommandBuffer,
        projection: simd_float4x4,
        viewMatrix: simd_float4x4,
        lightVP: simd_float4x4,
        center: SIMD3<Float>,
        footprintRadius: Float,
        maxHeight: Float
    ) {
        guard
            let cameraData,
            let contactShadowMaskPipeline,
            let shadowDepthTexture
        else { return }

        let r = max(footprintRadius, 0.25) * groundSizeMultiplier
        let groundModel =
            simd_float4x4(translation: SIMD3<Float>(center.x, center.y, shadowPlaneZ)) *
            simd_float4x4(scale: SIMD3<Float>(r, r, 1.0))

        let mvp = lightVP * groundModel
        let cameraWorldPos  = cameraData.worldPosition
        var gu = GroundUniforms(
            mvp: mvp,
            modelMatrix: groundModel,
            lightVP: lightVP,
            baseColor: SIMD4<Float>(1, 1, 1, 1),
            shadowStrength: shadowStrength,
            maxHeight: maxHeight,
            cameraWorldPos: cameraWorldPos
        )

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = shadowMaskTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
        enc.setRenderPipelineState(contactShadowMaskPipeline)
        enc.setCullMode(.none)
        enc.setDepthStencilState(noDepthState)

        enc.setVertexBuffer(groundVertexBuffer, offset: 0, index: 0)
        enc.setVertexBytes(&gu, length: MemoryLayout<GroundUniforms>.stride, index: 1)

        enc.setFragmentTexture(shadowDepthTexture, index: 0)
        enc.setFragmentSamplerState(shadowSamplerState, index: 0)
        enc.setFragmentBytes(&gu, length: MemoryLayout<GroundUniforms>.stride, index: 1)

        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }
    
    private func renderMeshes(
        encoder: MTLRenderCommandEncoder,
        model: PBRModel,
        projection: simd_float4x4,
        viewMatrix: simd_float4x4,
        globalModelScale: simd_float4x4,
        cameraWorldPos: SIMD3<Float>
    ) {
        for mesh in model.meshes {
            let modelMatrix = globalModelScale * mesh.transform
            let mvp = projection * viewMatrix * modelMatrix

            var uniforms = ModelUniforms(
                modelMatrix: modelMatrix,
                mvp: mvp,
                normalMatrix: simd_float3x3(fromModelMatrix: modelMatrix),
                cameraWorldPos: cameraWorldPos
            )

            for (i, vtx) in mesh.mesh.vertexBuffers.enumerated() {
                encoder.setVertexBuffer(vtx.buffer, offset: vtx.offset, index: i)
            }

            encoder.setVertexBytes(&uniforms, length: MemoryLayout<ModelUniforms>.stride, index: 10)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ModelUniforms>.stride, index: 10)

            var controls = ShaderControlsUniforms(
                keyIntensity: shaderControls.keyIntensity,
                ambientIntensity: shaderControls.ambientIntensity,
                specularIntensity: shaderControls.specularIntensity,
                roughnessBias: shaderControls.roughnessBias,
                topLightIntensity: shaderControls.topLightIntensity
            )
            encoder.setFragmentBytes(&controls, length: MemoryLayout<PBRShaderControls>.stride, index: 1)

            var frag = FragmentUniforms(
                baseColorFactor: mesh.material.baseColor,
                metallicFactor: mesh.material.metallic,
                roughnessFactor: mesh.material.roughness,
                hasBaseColorTexture: mesh.material.baseColorTexture != nil ? 1 : 0,
                hasMetallicTexture: mesh.material.metallicTexture != nil ? 1 : 0,
                hasRoughnessTexture: mesh.material.roughnessTexture != nil ? 1 : 0,
                hasNormalTexture: mesh.material.normalTexture != nil ? 1 : 0
            )
            encoder.setFragmentBytes(&frag, length: MemoryLayout<FragmentUniforms>.stride, index: 0)

            encoder.setFragmentTexture(mesh.material.baseColorTexture, index: 0)
            encoder.setFragmentTexture(mesh.material.metallicTexture, index: 1)
            encoder.setFragmentTexture(mesh.material.roughnessTexture, index: 2)
            encoder.setFragmentTexture(mesh.material.normalTexture, index: 3)

            for sub in mesh.mesh.submeshes {
                encoder.drawIndexedPrimitives(
                    type: sub.primitiveType,
                    indexCount: sub.indexCount,
                    indexType: sub.indexType,
                    indexBuffer: sub.indexBuffer.buffer,
                    indexBufferOffset: sub.indexBuffer.offset
                )
            }
        }
    }
    
    private func makeContactShadowTextures(size: CGSize) {
        let w = Int(size.width  * 0.5)
        let h = Int(size.height * 0.5)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Float,
            width: w,
            height: h,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private

        shadowMaskTexture    = renderContext.device.makeTexture(descriptor: desc)
        shadowMaskBlurTemp   = renderContext.device.makeTexture(descriptor: desc)
        shadowMaskBlurred    = renderContext.device.makeTexture(descriptor: desc)
    }
    
    private func makeShadowMapResources() {
        let size = shadowMapSize
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: size,
            height: size,
            mipmapped: false
        )

        depthDesc.sampleCount = 1
        depthDesc.textureType = .type2D
        depthDesc.storageMode = .private
        depthDesc.usage = [.renderTarget, .shaderRead]

        shadowDepthTexture = renderContext.device.makeTexture(descriptor: depthDesc)
        
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowDepthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1.0
        shadowPassDesc = pass
    }
    
    private func makeBlurPipeline(
        fragmentFunction: String
    ) throws -> MTLRenderPipelineState {

        let library = try renderContext.device.makeDefaultLibrary(bundle: .main)

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = library.makeFunction(name: "fullscreenVS")
        desc.fragmentFunction = library.makeFunction(name: fragmentFunction)

        // Single-channel blur target
        desc.colorAttachments[0].pixelFormat = .r16Float
        desc.colorAttachments[0].isBlendingEnabled = false

        desc.depthAttachmentPixelFormat = .invalid
        desc.rasterSampleCount = 1

        return try renderContext.device.makeRenderPipelineState(descriptor: desc)
    }
    
    private func makeShadowDepthPipeline(
            vertexDescriptor: MDLVertexDescriptor,
            vertexFunction: String,
            fragmentFunction: String
        ) throws -> MTLRenderPipelineState {

            let library = try renderContext.device.makeDefaultLibrary(bundle: .main)

            guard let vfn = library.makeFunction(name: vertexFunction),
                  let ffn = library.makeFunction(name: fragmentFunction)
            else {
                throw NSError(
                    domain: "MetalPBRRenderer",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Missing shadow depth shader functions \(vertexFunction)/\(fragmentFunction)"]
                )
            }

            let metalVertexDescriptor =
                MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.vertexDescriptor = metalVertexDescriptor

            // Depth-only pass
            desc.colorAttachments[0].pixelFormat = .invalid
            desc.depthAttachmentPixelFormat = .depth32Float

            // Shadow map is single-sampled
            desc.rasterSampleCount = 1

            return try renderContext.device.makeRenderPipelineState(descriptor: desc)
        }

    private func makeContactShadowMaskPipeline(
        vertexFunction: String,
        fragmentFunction: String
    ) throws -> MTLRenderPipelineState {

        let library = try renderContext.device.makeDefaultLibrary(bundle: .main)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: vertexFunction)
        desc.fragmentFunction = library.makeFunction(name: fragmentFunction)
        desc.colorAttachments[0].pixelFormat = .r16Float
        desc.colorAttachments[0].isBlendingEnabled = false
        desc.depthAttachmentPixelFormat = .invalid
        desc.rasterSampleCount = 1
        return try renderContext.device.makeRenderPipelineState(descriptor: desc)
    }
    
    private func makeSkyEnvironmentTexture() {
        let sky = MDLSkyCubeTexture(
            name: "ProceduralSky",
            channelEncoding: .float16,
            textureDimensions: [512, 512],
            turbidity: 0.8,
            sunElevation: 0.8,
            upperAtmosphereScattering: 0.5,
            groundAlbedo: 0.3
        )
        let loader = MTKTextureLoader(device: renderContext.device)
        do {
            let tex = try loader.newTexture(
                texture: sky,
                options: [
                    .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                    .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
                    .generateMipmaps: true
                ]
            )
            tex.label = "EnvironmentSkyCubemap"
            self.environmentTexture = tex

        } catch {
            print("Failed to create sky cubemap:", error)
        }
    }

    private func makePBRPipeline(vertexDescriptor: MDLVertexDescriptor, vertexFunction: String, fragmentFunction: String) throws -> MTLRenderPipelineState {
        let library = try renderContext.device.makeDefaultLibrary(bundle: .main)

        guard let vfn = library.makeFunction(name: vertexFunction),
              let ffn = library.makeFunction(name: fragmentFunction)
        else {
            throw NSError(domain: "MetalPBRRenderer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing shader functions \(vertexFunction)/\(fragmentFunction)"])
        }

        let metalVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.vertexDescriptor = metalVertexDescriptor
        desc.rasterSampleCount = renderContext.sampleCount
        desc.colorAttachments[0].pixelFormat = renderContext.colorPixelFormat
        desc.depthAttachmentPixelFormat = renderContext.depthPixelFormat

        return try renderContext.device.makeRenderPipelineState(descriptor: desc)
    }

    private func makeGroundPipeline(
        vertexFunction: String,
        fragmentFunction: String
    ) throws -> MTLRenderPipelineState {

        let library = try renderContext.device.makeDefaultLibrary(bundle: .main)

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: vertexFunction)
        desc.fragmentFunction = library.makeFunction(name: fragmentFunction)
        desc.rasterSampleCount = renderContext.sampleCount
        
        desc.colorAttachments[0].pixelFormat = renderContext.colorPixelFormat
        desc.depthAttachmentPixelFormat = renderContext.depthPixelFormat

        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        desc.rasterSampleCount = renderContext.sampleCount
        
        return try renderContext.device.makeRenderPipelineState(descriptor: desc)
    }
}
