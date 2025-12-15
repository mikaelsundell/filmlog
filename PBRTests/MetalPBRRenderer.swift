// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import MetalKit
import ModelIO
import simd

final class MetalPBRRenderer {
    struct PBRUniforms {
        var modelMatrix: simd_float4x4
        var mvp: simd_float4x4
        var normalMatrix: simd_float3x3
        var worldPosition: SIMD3<Float>
        var _pad0: Float = 0
    }

    struct PBRFragmentUniforms {
        var baseColorFactor: SIMD4<Float>
        var metallicFactor: Float
        var roughnessFactor: Float
        var hasBaseColorTexture: UInt32
        var hasMetallicTexture: UInt32
        var hasRoughnessTexture: UInt32
        var hasNormalTexture: UInt32
    }

    struct PBRShaderControls {
        var keyIntensity: Float
        var ambientIntensity: Float
        var specularIntensity: Float
        var roughnessBias: Float
    }

    struct ShadowDepthUniforms {
        var lightMVP: simd_float4x4
    }

    struct GroundUniforms {
        var mvp: simd_float4x4
        var modelMatrix: simd_float4x4
        var lightVP: simd_float4x4
        var baseColor: SIMD4<Float>
        var shadowStrength: Float
        var maxHeight: Float
        var _pad0: SIMD3<Float> = .zero
    }

    var shaderControls = MetalShaderControls()
    var environmentTexture: MTLTexture?
    var viewMatrix: simd_float4x4?
    var worldPosition: SIMD3<Float>?

    var shadowPlaneZ: Float = 0.0
    var shadowStrength: Float = 0.50
    var groundSizeMultiplier: Float = 1.0
    
    var lightDirection = normalize(SIMD3<Float>(0.0, 0.0001, -1.0))

    private(set) weak var mtkView: MTKView?

    private var device: MTLDevice
    private var meshAllocator: MTKMeshBufferAllocator
    private var model: MetalPBRLoader.PBRModel?
    private let loader: MetalPBRLoader

    private var pbrPipeline: MTLRenderPipelineState?
    private var shadowDepthPipeline: MTLRenderPipelineState?
    private var groundPipeline: MTLRenderPipelineState?

    private let depthWriteState: MTLDepthStencilState
    private let noDepthState: MTLDepthStencilState
    
    private var textureLoader: MTKTextureLoader
    private var textureCache: [URL: MTLTexture] = [:]
    private var samplerState: MTLSamplerState
    private var shadowSamplerState: MTLSamplerState

    private var shadowDepthTexture: MTLTexture?
    private var shadowPassDesc: MTLRenderPassDescriptor?
    private var shadowMapSize: Int = 1024

    private var groundVertexBuffer: MTLBuffer?

    init(device: MTLDevice, mtkView: MTKView) {
        self.device = device
        self.mtkView = mtkView
        self.meshAllocator = MTKMeshBufferAllocator(device: device)
        self.textureLoader = MTKTextureLoader(device: device)
        self.loader = MetalPBRLoader(device: device)
        
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        self.depthWriteState = device.makeDepthStencilState(descriptor: depthDesc)!
        
        let noDepthDesc = MTLDepthStencilDescriptor()
        noDepthDesc.depthCompareFunction = .always
        noDepthDesc.isDepthWriteEnabled = false
        self.noDepthState = device.makeDepthStencilState(descriptor: noDepthDesc)!
        
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .linear
        samplerDesc.sAddressMode = .repeat
        samplerDesc.tAddressMode = .repeat
        self.samplerState = device.makeSamplerState(descriptor: samplerDesc)!

        let shadowSamp = MTLSamplerDescriptor()
        shadowSamp.minFilter = .linear
        shadowSamp.magFilter = .linear
        shadowSamp.mipFilter = .notMipmapped
        shadowSamp.sAddressMode = .clampToEdge
        shadowSamp.tAddressMode = .clampToEdge
        self.shadowSamplerState = device.makeSamplerState(descriptor: shadowSamp)!

        let groundVerts: [SIMD3<Float>] = [
            SIMD3(-1, -1, 0),
            SIMD3( 1, -1, 0),
            SIMD3(-1,  1, 0),

            SIMD3( 1, -1, 0),
            SIMD3( 1,  1, 0),
            SIMD3(-1,  1, 0),
        ]
        self.groundVertexBuffer = device.makeBuffer(
            bytes: groundVerts,
            length: groundVerts.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        )
        self.groundVertexBuffer?.label = "GroundQuadVB"
        makeShadowMapResources()
    }
    
    func renderShadowMap(commandBuffer: MTLCommandBuffer) {
        guard
            let model,
            let shadowPassDesc,
            let shadowDepthPipeline
        else { return }

        let (heightVP, _, _, _) = computeHeightVP(
            model: model
        )

        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowPassDesc)!
        encoder.setRenderPipelineState(shadowDepthPipeline)
        encoder.setDepthStencilState(depthWriteState)
        encoder.setCullMode(.none)

        for mesh in model.meshes {
            let modelMatrix = mesh.transform
            var su = ShadowDepthUniforms(lightMVP: heightVP * modelMatrix)

            if let vb0 = mesh.mtkMesh.vertexBuffers.first {
                encoder.setVertexBuffer(vb0.buffer, offset: vb0.offset, index: 0)
            }
            encoder.setVertexBytes(
                &su,
                length: MemoryLayout<ShadowDepthUniforms>.stride,
                index: 1
            )

            for sub in mesh.mtkMesh.submeshes {
                encoder.drawIndexedPrimitives(
                    type: sub.primitiveType,
                    indexCount: sub.indexCount,
                    indexType: sub.indexType,
                    indexBuffer: sub.indexBuffer.buffer,
                    indexBufferOffset: sub.indexBuffer.offset
                )
            }
        }

        encoder.endEncoding()
    }

    func draw(
        with encoder: MTLRenderCommandEncoder,
        in view: MTKView
    ) {
        guard let model, let pbrPipeline else { return }

        let aspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
        let projection = simd_float4x4(
            perspectiveFov: .pi / 3,
            aspect: aspect,
            nearZ: 0.1,
            farZ: 100.0
        )

        let localViewMatrix = viewMatrix ?? matrix_identity_float4x4
        let cameraWorldPos = worldPosition ?? SIMD3<Float>(0, 0, 0)
        let globalModelScale = simd_float4x4(scale: 1.00)

        let (heightVP, modelCenter, footprint, maxHeight) =
            computeHeightVP(model: model)

        drawGroundReceiver(
            with: encoder,
            projection: projection,
            viewMatrix: localViewMatrix,
            lightVP: heightVP,
            center: modelCenter,
            footprintRadius: footprint,
            maxHeight: maxHeight
        )

        encoder.setRenderPipelineState(pbrPipeline)
        encoder.setDepthStencilState(depthWriteState)
        encoder.setCullMode(.none)
        encoder.setFragmentSamplerState(samplerState, index: 0)

        if let env = environmentTexture {
            encoder.setFragmentTexture(env, index: 9)
        }

        for mesh in model.meshes {
            let modelMatrix = globalModelScale * mesh.transform
            let mvp = projection * localViewMatrix * modelMatrix

            var uniforms = PBRUniforms(
                modelMatrix: modelMatrix,
                mvp: mvp,
                normalMatrix: simd_float3x3(fromModelMatrix: modelMatrix),
                worldPosition: cameraWorldPos
            )

            for (i, vtx) in mesh.mtkMesh.vertexBuffers.enumerated() {
                encoder.setVertexBuffer(vtx.buffer, offset: vtx.offset, index: i)
            }

            encoder.setVertexBytes(&uniforms, length: MemoryLayout<PBRUniforms>.stride, index: 10)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PBRUniforms>.stride, index: 10)

            var controls = PBRShaderControls(
                keyIntensity: shaderControls.keyIntensity,
                ambientIntensity: shaderControls.ambientIntensity,
                specularIntensity: shaderControls.specularIntensity,
                roughnessBias: shaderControls.roughnessBias
            )
            encoder.setFragmentBytes(&controls, length: MemoryLayout<PBRShaderControls>.stride, index: 1)

            var frag = PBRFragmentUniforms(
                baseColorFactor: mesh.material.baseColor,
                metallicFactor: mesh.material.metallic,
                roughnessFactor: mesh.material.roughness,
                hasBaseColorTexture: mesh.material.baseColorTexture != nil ? 1 : 0,
                hasMetallicTexture: mesh.material.metallicTexture != nil ? 1 : 0,
                hasRoughnessTexture: mesh.material.roughnessTexture != nil ? 1 : 0,
                hasNormalTexture: mesh.material.normalTexture != nil ? 1 : 0
            )
            encoder.setFragmentBytes(&frag, length: MemoryLayout<PBRFragmentUniforms>.stride, index: 0)

            encoder.setFragmentTexture(mesh.material.baseColorTexture, index: 0)
            encoder.setFragmentTexture(mesh.material.metallicTexture, index: 1)
            encoder.setFragmentTexture(mesh.material.roughnessTexture, index: 2)
            encoder.setFragmentTexture(mesh.material.normalTexture, index: 3)

            for sub in mesh.mtkMesh.submeshes {
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

    func loadModel(from url: URL) {
        do {
            let result = try loader.loadModel(from: url)
            self.model = result.model

            self.pbrPipeline =
                try makePBRPipeline(
                    mdlMesh: result.referenceMesh,
                    vertexFunction: "modelPBRVS",
                    fragmentFunction: "modelPBRFS"
                )
            
            self.groundPipeline =
                try makeGroundPipeline(
                    vertexFunction: "groundVS",
                    fragmentFunction: "groundFS"
                )
            
            self.shadowDepthPipeline =
                try makeShadowDepthPipeline(
                    mdlMesh: result.referenceMesh,
                    vertexFunction: "shadowDepthVS",
                    fragmentFunction: "shadowDepthFS"
                )
        } catch {
            print("Model load failed:", error)
        }
    }
    
    private func drawGroundReceiver(
        with encoder: MTLRenderCommandEncoder,
        projection: simd_float4x4,
        viewMatrix: simd_float4x4,
        lightVP: simd_float4x4,
        center: SIMD3<Float>,
        footprintRadius: Float,
        maxHeight: Float
    ) {
        guard let groundPipeline,
              let groundVertexBuffer,
              let shadowDepthTexture
        else { return }

        let r = max(footprintRadius, 0.25) * groundSizeMultiplier

        let groundModel =
            simd_float4x4(translation: SIMD3<Float>(center.x, center.y, shadowPlaneZ)) *
            simd_float4x4(scale: SIMD3<Float>(r, r, 1.0))

        let mvp = projection * viewMatrix * groundModel
        var gu = GroundUniforms(
            mvp: mvp,
            modelMatrix: groundModel,
            lightVP: lightVP,
            baseColor: SIMD4<Float>(1, 1, 1, 1),
            shadowStrength: 1.0,
            maxHeight: maxHeight
        )

        encoder.setRenderPipelineState(groundPipeline)
        encoder.setDepthStencilState(depthWriteState)
        encoder.setCullMode(.none)

        encoder.setVertexBuffer(groundVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&gu, length: MemoryLayout<GroundUniforms>.stride, index: 1)

        encoder.setFragmentTexture(shadowDepthTexture, index: 0)
        encoder.setFragmentSamplerState(shadowSamplerState, index: 0)
        encoder.setFragmentBytes(&gu, length: MemoryLayout<GroundUniforms>.stride, index: 1)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
    
    private func computeHeightVP(
        model: MetalPBRLoader.PBRModel,
    ) -> (simd_float4x4, SIMD3<Float>, Float, Float) {
        let b = modelBoundsWorld(model)
        let minB = b?.min ?? SIMD3<Float>(-0.5, 0.0, -0.5)
        let maxB = b?.max ?? SIMD3<Float>( 0.5, 1.0,  0.5)

        let center = (minB + maxB) * 0.5
        let ext = (maxB - minB)
        let footprint = 0.5 * max(ext.x, ext.z)

        let maxHeight = max(ext.y, 0.1) * 2.0 + 0.1
        let view = simd_float4x4(
            lookAt:
                SIMD3<Float>(center.x, center.y, shadowPlaneZ),
                SIMD3<Float>(center.x, center.y, shadowPlaneZ + 1.0),
                SIMD3<Float>(0, 1, 0)
        )
        let pad = max(footprint, 0.25) * 1.5
        let proj = simd_float4x4(
            orthoLeft: -pad, right: pad,
            bottom: -pad, top: pad,
            nearZ: 0.0,
            farZ: maxHeight
        )
        return (proj * view, center, footprint, maxHeight)
    }
    
    private func modelBoundsWorld(_ model: MetalPBRLoader.PBRModel)
        -> (min: SIMD3<Float>, max: SIMD3<Float>)?
    {
        var minOut = SIMD3<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
        var maxOut = SIMD3<Float>(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
        var found = false

        for mesh in model.meshes {
            guard let bounds = mesh.bounds else { continue }

            let modelMatrix = mesh.transform
            let localMin = bounds.min
            let localMax = bounds.max

            let corners: [SIMD3<Float>] = [
                SIMD3(localMin.x, localMin.y, localMin.z),
                SIMD3(localMax.x, localMin.y, localMin.z),
                SIMD3(localMin.x, localMax.y, localMin.z),
                SIMD3(localMax.x, localMax.y, localMin.z),
                SIMD3(localMin.x, localMin.y, localMax.z),
                SIMD3(localMax.x, localMin.y, localMax.z),
                SIMD3(localMin.x, localMax.y, localMax.z),
                SIMD3(localMax.x, localMax.y, localMax.z),
            ]

            for c in corners {
                let wc = (modelMatrix * SIMD4<Float>(c, 1)).xyz
                minOut = simd.min(minOut, wc)
                maxOut = simd.max(maxOut, wc)
            }
            found = true
        }

        return found ? (minOut, maxOut) : nil
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

        shadowDepthTexture = device.makeTexture(descriptor: depthDesc)
        shadowDepthTexture?.label = "ShadowDepthMap"

        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowDepthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1.0
        shadowPassDesc = pass
    }

    private func makeShadowDepthPipeline(
        mdlMesh: MDLMesh,
        vertexFunction: String,
        fragmentFunction: String
    ) throws -> MTLRenderPipelineState {

        let library = try device.makeDefaultLibrary(bundle: .main)

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
            MTKMetalVertexDescriptorFromModelIO(mdlMesh.vertexDescriptor)

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.vertexDescriptor = metalVertexDescriptor
        desc.depthAttachmentPixelFormat = .depth32Float
        desc.rasterSampleCount = mtkView?.sampleCount ?? 1
        
        return try device.makeRenderPipelineState(descriptor: desc)
    }
    
    private func makePBRPipeline(mdlMesh: MDLMesh, vertexFunction: String, fragmentFunction: String) throws -> MTLRenderPipelineState {
        let library = try device.makeDefaultLibrary(bundle: .main)

        guard let vfn = library.makeFunction(name: vertexFunction),
              let ffn = library.makeFunction(name: fragmentFunction)
        else {
            throw NSError(domain: "MetalPBRRenderer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing shader functions \(vertexFunction)/\(fragmentFunction)"])
        }

        let metalVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mdlMesh.vertexDescriptor)

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.vertexDescriptor = metalVertexDescriptor
        desc.rasterSampleCount = mtkView?.sampleCount ?? 1
        desc.colorAttachments[0].pixelFormat = mtkView?.colorPixelFormat ?? .bgra8Unorm_srgb
        desc.depthAttachmentPixelFormat = mtkView?.depthStencilPixelFormat ?? .depth32Float

        return try device.makeRenderPipelineState(descriptor: desc)
    }

    private func makeGroundPipeline(
        vertexFunction: String,
        fragmentFunction: String
    ) throws -> MTLRenderPipelineState {

        let library = try device.makeDefaultLibrary(bundle: .main)

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: vertexFunction)
        desc.fragmentFunction = library.makeFunction(name: fragmentFunction)
       
        desc.colorAttachments[0].pixelFormat =
            mtkView?.colorPixelFormat ?? .bgra8Unorm_srgb
        desc.depthAttachmentPixelFormat =
            mtkView?.depthStencilPixelFormat ?? .depth32Float

        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        desc.rasterSampleCount = mtkView?.sampleCount ?? 1
        
        return try device.makeRenderPipelineState(descriptor: desc)
    }
}

