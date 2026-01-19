// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import MetalKit
import ModelIO

class PBRRenderer {
    struct CameraData {
        var projection: simd_float4x4
        var view: simd_float4x4
        var worldPosition: SIMD3<Float>
    }
    
    struct Uniforms {
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
    public var environmentTexture: MTLTexture?
    public var model: PBRModel?
    public var cameraData: CameraData?
    
    private(set) weak var mtkView: MTKView?
    private var device: MTLDevice!
    private var pipeline: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState!
    private var samplerState: MTLSamplerState!
    
    init(device: MTLDevice, mtkView: MTKView) {
        self.device = device
        self.mtkView = mtkView

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor: depthDesc)
        
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .linear
        samplerDesc.sAddressMode = .repeat
        samplerDesc.tAddressMode = .repeat
        self.samplerState = device.makeSamplerState(descriptor: samplerDesc)
    }

    func draw(with encoder: MTLRenderCommandEncoder, drawableSize: CGSize) {
        guard let model = self.model,
            let camera = cameraData,
              let pipeline = self.pipeline else {
            return
        }
        let projection = camera.projection
        let viewMatrix = camera.view
        let cameraPos  = camera.worldPosition
        
        let globalModelScale = float4x4(scale: 0.75)

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        if let env = environmentTexture {
            encoder.setFragmentTexture(env, index: 9)
        }
        
        for mesh in model.meshes {
            let modelMatrix = globalModelScale * mesh.transform
            var uniforms = Uniforms(
                modelMatrix: modelMatrix,
                mvp: projection * viewMatrix * modelMatrix,
                normalMatrix: simd_float3x3(fromModelMatrix: modelMatrix),
                cameraWorldPos: cameraPos
            )
            
            for (i, vtx) in mesh.mesh.vertexBuffers.enumerated() {
                encoder.setVertexBuffer(vtx.buffer, offset: vtx.offset, index: i)
            }

            encoder.setVertexBytes(
                &uniforms,
                length: MemoryLayout<Uniforms>.stride,
                index: 10
            )
            
            encoder.setFragmentBytes(
                &uniforms,
                length: MemoryLayout<Uniforms>.stride,
                index: 10
            )
            
            var fragUniforms = FragmentUniforms(
                baseColorFactor: mesh.material.baseColor,
                metallicFactor: mesh.material.metallic,
                roughnessFactor: mesh.material.roughness,
                hasBaseColorTexture: mesh.material.baseColorTexture != nil ? 1 : 0,
                hasMetallicTexture: mesh.material.metallicTexture != nil ? 1 : 0,
                hasRoughnessTexture: mesh.material.roughnessTexture != nil ? 1 : 0,
                hasNormalTexture: mesh.material.normalTexture != nil ? 1 : 0
            )
            
            encoder.setFragmentBytes(
                &fragUniforms,
                length: MemoryLayout<FragmentUniforms>.stride,
                index: 0
            )
            
            encoder.setFragmentTexture(mesh.material.baseColorTexture, index: 0)
            encoder.setFragmentTexture(mesh.material.metallicTexture,  index: 1)
            encoder.setFragmentTexture(mesh.material.roughnessTexture, index: 2)
            encoder.setFragmentTexture(mesh.material.normalTexture,    index: 3)

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

    private func makePipeline(
        mdlMesh: MDLMesh,
        vertexFunction: String,
        fragmentFunction: String
    ) throws -> MTLRenderPipelineState {
        let library = try device.makeDefaultLibrary(bundle: .main)
        let vfn = library.makeFunction(name: vertexFunction)
        let ffn = library.makeFunction(name: fragmentFunction)

        guard let vfn, let ffn else {
            throw NSError(
                domain: "CameraMetalRenderer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Function \(vertexFunction) or \(fragmentFunction) not found in Metal library"]
            )
        }

        let metalVertexDescriptor =
            MTKMetalVertexDescriptorFromModelIO(mdlMesh.vertexDescriptor)

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.vertexDescriptor = metalVertexDescriptor
        desc.colorAttachments[0].pixelFormat = mtkView?.colorPixelFormat ?? .bgra8Unorm_srgb
        desc.depthAttachmentPixelFormat = .depth32Float

        let pipeline = try device.makeRenderPipelineState(descriptor: desc)
        return pipeline
    }
}
