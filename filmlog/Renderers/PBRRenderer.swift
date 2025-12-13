// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import MetalKit
import ModelIO

class PBRRenderer {
    struct PBRMaterial {
        var baseColor: SIMD4<Float>
        var metallic: Float
        var roughness: Float
        
        var baseColorTexture: MTLTexture?
        var normalTexture: MTLTexture?
        var metallicTexture: MTLTexture?
        var roughnessTexture: MTLTexture?
    }
    
    struct PBRMesh {
        var mtkMesh: MTKMesh
        var transform: float4x4
        var material: PBRMaterial
        
        var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
    }
    
    struct PBRModel {
        var meshes: [PBRMesh]
    }
    
    struct PBRUniforms {
        var modelMatrix: simd_float4x4
        var mvp: simd_float4x4
        var normalMatrix: simd_float3x3
        var cameraWorldPos: SIMD3<Float>
        var _pad0: Float = 0 // 16-byte alignment for Metal
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
    public var environmentTexture: MTLTexture?
    
    private(set) weak var mtkView: MTKView?
    private var device: MTLDevice!
    private var meshAllocator: MTKMeshBufferAllocator!
    private var pipeline: MTLRenderPipelineState?
    private var model: PBRModel?
    private var depthState: MTLDepthStencilState!
    
    private var textureLoader: MTKTextureLoader!
    private var textureCache: [URL: MTLTexture] = [:]
    private var samplerState: MTLSamplerState!
    
    init(device: MTLDevice, mtkView: MTKView) {
        self.device = device
        self.mtkView = mtkView
        self.meshAllocator = MTKMeshBufferAllocator(device: device)
        self.textureLoader = MTKTextureLoader(device: device)

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

    func draw(with encoder: MTLRenderCommandEncoder, in view: MTKView) {
        guard let model = self.model,
              let pipeline = self.pipeline else {
            return
        }

        let aspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1))

        let projection = float4x4(
            perspectiveFov: .pi / 3,
            aspect: aspect,
            nearZ: 0.1,
            farZ: 100.0
        )

        let eye    = SIMD3<Float>(0.0, -2.0, 1.0)
        let target = SIMD3<Float>(0.0,  0.0, 0.65)
        let up     = SIMD3<Float>(0.0,  0.0, 1.0)

        let viewMatrix = float4x4(lookAt: eye, target: target, up: up)
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
            let mvp = projection * viewMatrix * modelMatrix
            var uniforms = PBRUniforms(
                modelMatrix: modelMatrix,
                mvp: mvp,
                normalMatrix: simd_float3x3(fromModelMatrix: modelMatrix),
                cameraWorldPos: eye
            )
            
            for (i, vtx) in mesh.mtkMesh.vertexBuffers.enumerated() {
                encoder.setVertexBuffer(vtx.buffer, offset: vtx.offset, index: i)
            }

            encoder.setVertexBytes(
                &uniforms,
                length: MemoryLayout<PBRUniforms>.stride,
                index: 10
            )
            
            encoder.setFragmentBytes(
                &uniforms,
                length: MemoryLayout<PBRUniforms>.stride,
                index: 10
            )
            
            var fragUniforms = PBRFragmentUniforms(
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
                length: MemoryLayout<PBRFragmentUniforms>.stride,
                index: 0
            )
            
            encoder.setFragmentTexture(mesh.material.baseColorTexture, index: 0)
            encoder.setFragmentTexture(mesh.material.metallicTexture,  index: 1)
            encoder.setFragmentTexture(mesh.material.roughnessTexture, index: 2)
            encoder.setFragmentTexture(mesh.material.normalTexture,    index: 3)

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
    
    private func makePBRVertexDescriptor() -> MDLVertexDescriptor {
        let vd = MDLVertexDescriptor()

        vd.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )

        vd.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: 12,
            bufferIndex: 0
        )

        vd.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeTangent,
            format: .float4,
            offset: 24,
            bufferIndex: 0
        )

        vd.attributes[3] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate,
            format: .float2,
            offset: 40,
            bufferIndex: 0
        )

        vd.layouts[0] = MDLVertexBufferLayout(stride: 48)
        return vd
    }

    func loadModel(from url: URL) {
        guard let allocator = meshAllocator else {
            return
        }
        
        let asset = MDLAsset(
            url: url,
            vertexDescriptor: nil,
            bufferAllocator: allocator
        )
        asset.loadTextures()

        var pbrMeshes: [PBRMesh] = []
        var firstMDLMesh: MDLMesh? = nil

        func worldTransform(for object: MDLObject, parent: float4x4) -> float4x4 {
            if let t = object.transform as? MDLTransform {
                return parent * t.matrix
            }
            return parent
        }

        func process(object: MDLObject, parentTransform: float4x4) {
            let world = worldTransform(for: object, parent: parentTransform)
            if let mesh = object as? MDLMesh {
                if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
                    mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal,
                                    creaseThreshold: 0.0)
                }

                if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTangent) == nil {
                    mesh.addOrthTanBasis(
                        forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                        normalAttributeNamed: MDLVertexAttributeNormal,
                        tangentAttributeNamed: MDLVertexAttributeTangent
                    )
                }

                var originalMaterials: [MDLMaterial?] = []

                if let subs = mesh.submeshes as? [MDLSubmesh] {
                    for (_, sm) in subs.enumerated() {
                        originalMaterials.append(sm.material)
                    }
                } else {
                    print("mesh has no MDLSubmesh array")
                }

                if firstMDLMesh == nil {
                    firstMDLMesh = mesh
                }

                do {
                    mesh.vertexDescriptor = makePBRVertexDescriptor()

                    let mtkMesh = try MTKMesh(mesh: mesh, device: device)
                    var chosenMat: MDLMaterial? = nil
                    if let subs = mesh.submeshes as? [MDLSubmesh] {
                        for sm in subs {
                            if let m = sm.material {
                                chosenMat = m
                                break
                            }
                        }
                    }

                    if chosenMat == nil {
                        chosenMat = originalMaterials.first ?? nil
                    }

                    if chosenMat == nil {
                        print("no material available for mesh \"\(mesh.name)\" using default PBR")
                    }

                    let pbrMaterial = makeMaterial(from: chosenMat)
                    let bb = mesh.boundingBox
                    let bounds = (
                        min: SIMD3<Float>(bb.minBounds),
                        max: SIMD3<Float>(bb.maxBounds)
                    )
                    pbrMeshes.append(
                        PBRMesh(
                            mtkMesh: mtkMesh,
                            transform: world,
                            material: pbrMaterial,
                            bounds: bounds
                        )
                    )
                }
                catch {
                    print("MDL to MTK conversion failed for mesh \(mesh.name): \(error)")
                }
            }
            for child in object.children.objects {
                process(object: child, parentTransform: world)
            }
        }

        for i in 0..<asset.count {
            process(object: asset.object(at: i), parentTransform: matrix_identity_float4x4)
        }
        if let mdl = firstMDLMesh {
            do {
                self.pipeline = try makePipeline(
                    mdlMesh: mdl,
                    vertexFunction: "modelPBRVS",
                    fragmentFunction: "modelPBRFS",
                )
            }
            catch {
                print("failed to build PBR pipeline: \(error)")
            }
        } else {
            print("no MDLMesh found, pipeline not built.")
        }

        self.model = PBRModel(meshes: pbrMeshes)
    }

    func makeMaterial(from mdlMaterial: MDLMaterial?) -> PBRMaterial {
        guard let mat = mdlMaterial else {
            return PBRMaterial(
                baseColor: SIMD4<Float>(0.8, 0.8, 0.8, 1.0),
                metallic: 0.0,
                roughness: 0.5,
                baseColorTexture: nil,
                normalTexture: nil,
                metallicTexture: nil,
                roughnessTexture: nil
            )
        }
        func floatFrom(_ semantic: MDLMaterialSemantic, default value: Float) -> Float {
            guard let p = mat.property(with: semantic) else {
                return value
            }

            let result: Float
            switch p.type {
            case .float:  result = p.floatValue
            case .float2: result = p.float2Value.x
            case .float3: result = p.float3Value.x
            case .float4: result = p.float4Value.x
            default:
                result = value
            }
            return result
        }

        func colorFrom(_ semantic: MDLMaterialSemantic,
                       default value: SIMD4<Float>) -> SIMD4<Float> {
            guard let p = mat.property(with: semantic) else {
                return value
            }

            switch p.type {
            case .float3:
                let c = p.float3Value
                let v = SIMD4<Float>(c.x, c.y, c.z, 1.0)
                return v

            case .float4:
                let c = p.float4Value
                let v = SIMD4<Float>(c.x, c.y, c.z, c.w)
                return v

            case .float:
                let g = p.floatValue
                let v = SIMD4<Float>(g, g, g, 1.0)
                return v

            case .color:
                if let cg = p.color {
                    let comps = cg.components ?? [0, 0, 0, 1]
                    let r = Float(comps[0])
                    let g = Float(comps.count > 1 ? comps[1] : comps[0])
                    let b = Float(comps.count > 2 ? comps[2] : comps[0])
                    let a = Float(comps.count > 3 ? comps[3] : 1.0)
                    let v = SIMD4<Float>(r, g, b, a)
                    return v
                }
                return value

            default:
                return value
            }
        }

        func loadTexture(_ semantic: MDLMaterialSemantic, sRGB: Bool) -> MTLTexture? {
            guard let prop = mat.property(with: semantic) else {
                return nil
            }
            if prop.type == .texture {
                if let sampler = prop.textureSamplerValue,
                   let mdlTex = sampler.texture {
                    do {
                        let tex = try textureLoader.newTexture(
                            texture: mdlTex,
                            options: [
                                MTKTextureLoader.Option.SRGB : sRGB,
                                MTKTextureLoader.Option.generateMipmaps : true
                            ]
                        )
                        return tex
                        
                    } catch {
                        print("failed to create Metal texture from MDLTexture: \(error)")
                    }
                } else {
                    print("texture semantic had no sampler/texture")
                }
            }
            var url: URL?
            switch prop.type {
            case .URL:
                url = prop.urlValue
                let name = url?.lastPathComponent ?? "nil"

            case .string:
                if let s = prop.stringValue {
                    url = URL(fileURLWithPath: s)
                } else {
                    print("\(semanticName(semantic)) had no stringValue")
                }

            default:
                break
            }

            guard let finalURL = url else {
                return nil
            }

            if let cached = textureCache[finalURL] {
                return cached
            }
            
            do {
                let tex = try textureLoader.newTexture(
                    URL: finalURL,
                    options: [
                        MTKTextureLoader.Option.SRGB : sRGB,
                        MTKTextureLoader.Option.generateMipmaps : true
                    ]
                )
                textureCache[finalURL] = tex
                return tex
            } catch {
                print("failed to load URL texture for \(semanticName(semantic)) from \(finalURL): \(error)")
                return nil
            }
        }
        let baseColor = colorFrom(.baseColor, default: SIMD4<Float>(0.8, 0.8, 0.8, 1.0))
        let metallic  = floatFrom(.metallic,  default: 0.0)
        let roughness = floatFrom(.roughness, default: 0.5)
        let baseColorTex = loadTexture(.baseColor,          sRGB: true)
        
        let metallicTex  = loadTexture(.metallic,           sRGB: false)
        let roughnessTex = loadTexture(.roughness,          sRGB: false)
        let normalTex    = loadTexture(.tangentSpaceNormal, sRGB: false)

        return PBRMaterial(
            baseColor: baseColor,
            metallic: metallic,
            roughness: roughness,
            baseColorTexture: baseColorTex,
            normalTexture: normalTex,
            metallicTexture: metallicTex,
            roughnessTexture: roughnessTex
        )
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
    
    private func boundignBox(min: SIMD3<Float>, max: SIMD3<Float>) -> MTKMesh? {
        let ext = max - min
        let alloc = meshAllocator
        let mdl = MDLMesh(
            boxWithExtent: ext,
            segments: [1, 1, 1],
            inwardNormals: false,
            geometryType: .triangles,
            allocator: alloc
        )
        mdl.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0)
        return try? MTKMesh(mesh: mdl, device: device)
    }
    
    private func modelBounds(_ model: PBRModel) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        var minOut = SIMD3<Float>(
            .greatestFiniteMagnitude,
            .greatestFiniteMagnitude,
            .greatestFiniteMagnitude
        )
        var maxOut = SIMD3<Float>(
            -.greatestFiniteMagnitude,
            -.greatestFiniteMagnitude,
            -.greatestFiniteMagnitude
        )
        var found = false

        for mesh in model.meshes {
            if let bounds = mesh.bounds {
                let t = mesh.transform
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
                    SIMD3(localMax.x, localMax.y, localMax.z)
                ]

                for c in corners {
                    let wc = (t * SIMD4<Float>(c, 1)).xyz
                    minOut = min(minOut, wc)
                    maxOut = max(maxOut, wc)
                }

                found = true
            }
        }
        return found ? (minOut, maxOut) : nil
    }
    
    private func semanticName(_ s: MDLMaterialSemantic) -> String {
        switch s {
        case .baseColor: return "baseColor"
        case .subsurface: return "subsurface"
        case .metallic: return "metallic"
        case .specular: return "specular"
        case .specularExponent: return "specularExponent"
        case .specularTint: return "specularTint"
        case .roughness: return "roughness"
        case .anisotropic: return "anisotropic"
        case .anisotropicRotation: return "anisotropicRotation"
        case .sheen: return "sheen"
        case .sheenTint: return "sheenTint"
        case .clearcoat: return "clearcoat"
        case .clearcoatGloss: return "clearcoatGloss"
        case .emission: return "emission"
        case .bump: return "bump"
        case .opacity: return "opacity"
        case .interfaceIndexOfRefraction: return "iorInterface"
        case .materialIndexOfRefraction: return "iorMaterial"
        case .objectSpaceNormal: return "objectSpaceNormal"
        case .tangentSpaceNormal: return "tangentSpaceNormal"
        case .displacement: return "displacement"
        case .displacementScale: return "displacementScale"
        case .ambientOcclusion: return "ambientOcclusion"
        case .ambientOcclusionScale: return "ambientOcclusionScale"
        case .none: return "none"
        case .userDefined: return "userDefined"
        @unknown default: return "unknown"
        }
    }
}
