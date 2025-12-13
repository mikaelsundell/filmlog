// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import MetalKit
import ModelIO

class MetalPBRRenderer {
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
        var worldPosition: SIMD3<Float>
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
    struct PBRShaderControls {
        var keyIntensity: Float
        var ambientIntensity: Float
        var specularIntensity: Float
        var roughnessBias: Float
    }
    
    var shaderControls = MetalShaderControls()
    var environmentTexture: MTLTexture?
    var viewMatrix: float4x4?
    var worldPosition: SIMD3<Float>?
    
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

        let localViewMatrix = viewMatrix ?? matrix_identity_float4x4
        let localWorldPosition = worldPosition ?? SIMD3<Float>(0, 0, 0)
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
            let mvp = projection * localViewMatrix * modelMatrix
            var uniforms = PBRUniforms(
                modelMatrix: modelMatrix,
                mvp: mvp,
                normalMatrix: simd_float3x3(fromModelMatrix: modelMatrix),
                worldPosition: localWorldPosition
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
            
            var pbrShaderControls = PBRShaderControls(
                keyIntensity: shaderControls.keyIntensity,
                ambientIntensity: shaderControls.ambientIntensity,
                specularIntensity: shaderControls.specularIntensity,
                roughnessBias: shaderControls.roughnessBias
            )
            
            encoder.setFragmentBytes(
                &pbrShaderControls,
                length: MemoryLayout<PBRShaderControls>.stride,
                index: 1
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

        for i in 0..<asset.count {
            let obj = asset.object(at: i)
            printModelTree(obj, indent: "   ")
        }

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
                    print("debug: mesh has no MDLSubmesh array")
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

                    if let mat = chosenMat {
                        print("material for mesh \"\(mesh.name)\": \(mat.name)")
                        printMaterial(mat, indent: "      ")
                    } else {
                        print("warning: No material available for mesh \"\(mesh.name)\" using default PBR")
                    }

                    let pbrMaterial = makeMaterial(from: chosenMat)
                    let bb = mesh.boundingBox
                    let bounds = (
                        min: SIMD3<Float>(bb.minBounds),
                        max: SIMD3<Float>(bb.maxBounds)
                    )

                    print("""
                        mesh summary:
                            name: \(mesh.name)
                            vertexCount: \(mesh.vertexCount)
                            submeshes: \(mesh.submeshes?.count ?? 0)
                            worldTransform:
                                \(world.columns.0)
                                \(world.columns.1)
                                \(world.columns.2)
                                \(world.columns.3)
                        """)

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
                    print("warning: MDL to MTK conversion failed for mesh \(mesh.name): \(error)")
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
                    fragmentFunction: "modelPBRFS"
                )
                print("warning: PBR pipeline created with vertex descriptor from first MDLMesh")
            }
            catch {
                print("warning: failed to build PBR pipeline: \(error)")
            }
        } else {
            print("warning: no MDLMesh found, pipeline not built.")
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
                print("warning: colorFrom(\(semanticName(semantic))) color but no cgColor, default \(value)")
                return value

            default:
                print("warning: colorFrom: unsupported type \(p.type.rawValue) for \(semanticName(semantic)), default \(value)")
                return value
            }
        }
        
        func loadTexture(_ semantic: MDLMaterialSemantic, sRGB: Bool) -> MTLTexture? {
            guard let prop = mat.property(with: semantic) else {
                print("no material property for semantic \(semanticName(semantic))")
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
                        
                        let pf = tex.pixelFormat
                        let mipCount = tex.mipmapLevelCount
                        let usage = tex.usage
                        let storage = tex.storageMode
                        let texType = tex.textureType

                        print("""
                               created Metal texture from MDLTexture
                                   semantic: \(semanticName(semantic))
                                   requested sRGB: \(sRGB)
                                   size: \(tex.width)x\(tex.height)
                                   pixelFormat: \(pf) (raw=\(pf.rawValue))
                                   mipLevels: \(mipCount)
                                   textureType: \(texType)
                                   usage: \(usage)
                                   storageMode: \(storage)
                        """)
                        
                        return tex
                        
                    } catch {
                        print("warning: failed to create Metal texture from MDLTexture: \(error)")
                    }
                } else {
                    print("warning: texture semantic had no sampler/texture")
                }
            }

            var url: URL?
            switch prop.type {
            case .URL:
                url = prop.urlValue
                let name = url?.lastPathComponent ?? "nil"
                print("   🔍 [URL] \(semanticName(semantic)) → \(name)")

            case .string:
                if let s = prop.stringValue {
                    url = URL(fileURLWithPath: s)
                } else {
                    print("warning: \(semanticName(semantic)) had no stringValue")
                }

            default:
                break
            }

            guard let finalURL = url else {
                print("warning: no usable URL for semantic \(semanticName(semantic))")
                return nil
            }

            if let cached = textureCache[finalURL] {
                print("using cached texture for \(semanticName(semantic)): \(finalURL.lastPathComponent)")
                return cached
            }

            print("loading texture from URL for \(semanticName(semantic)): \(finalURL.lastPathComponent), sRGB=\(sRGB)")
            do {
                let tex = try textureLoader.newTexture(
                    URL: finalURL,
                    options: [
                        MTKTextureLoader.Option.SRGB : sRGB,
                        MTKTextureLoader.Option.generateMipmaps : true
                    ]
                )
                textureCache[finalURL] = tex
                print("loaded URL texture \(finalURL.lastPathComponent) [\(tex.width)x\(tex.height)] for \(semanticName(semantic))")
                return tex
            } catch {
                print("warning: failed to load URL texture for \(semanticName(semantic)) from \(finalURL): \(error)")
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

        print("""
            🎨 PBRMaterial summary:
                baseColor: \(baseColor)
                metallic: \(metallic)
                roughness: \(roughness)
                baseColorTexture: \(baseColorTex != nil ? "YES" : "NO")
                metallicTexture:  \(metallicTex  != nil ? "YES" : "NO")
                roughnessTexture: \(roughnessTex != nil ? "YES" : "NO")
                normalTexture:    \(normalTex    != nil ? "YES" : "NO")
            """)

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
        desc.rasterSampleCount = mtkView?.sampleCount ?? 1
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
        
        if found {
            print("📐 Model world bounds: min=\(minOut), max=\(maxOut)")
        } else {
            print("📐 Model has no bounds information")
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
    
    private func printMaterial(_ mat: MDLMaterial, indent: String = "") {
        print(indent + "Material: \(mat.name)")
        let allSemantics: [MDLMaterialSemantic] = [
            .baseColor, .specular, .specularExponent, .roughness,
            .metallic, .emission, .opacity,
            .objectSpaceNormal, .tangentSpaceNormal,
            .ambientOcclusion, .displacement
        ]
        
        for semantic in allSemantics {
            let props = mat.properties(with: semantic)
            for p in props {
                print(indent + "  • \(semanticName(semantic)) \(p.name) type=\(p.type.rawValue)")
                
                switch p.type {
                case .string:
                    print(indent + "      string = \(p.stringValue ?? "<nil>")")
                case .float:
                    print(indent + "      float = \(p.floatValue)")
                case .color:
                    if let cg = p.color {
                        print(indent + "      color = \(cg)")
                    }
                case .URL:
                    if let url = p.urlValue {
                        print(indent + "      texture url = \(url.lastPathComponent)")
                    }
                default:
                    print(indent + "      (unhandled type)")
                }
            }
        }
    }

    private func printModelTree(_ object: MDLObject, indent: String = "") {
        let typeName = String(describing: type(of: object))
        let name = object.name.isEmpty ? "<no name>" : object.name
        
        print("\(indent)• \(typeName) \"\(name)\"")

        if let mesh = object as? MDLMesh {
            print("\(indent)   ↳ MDLMesh:")
            print("\(indent)      vertexCount = \(mesh.vertexCount)")
            print("\(indent)      submeshes  = \(mesh.submeshes?.count ?? 0)")

            if let submeshes = mesh.submeshes {
                for (i, sub) in submeshes.enumerated() {
                    guard let sm = sub as? MDLSubmesh else { continue }
                    print("\(indent)      [Submesh \(i)] indexCount = \(sm.indexCount)")
                    
                    if let mat = sm.material {
                        print("\(indent)         material = \(mat.name)")
                        for idx in 0..<mat.count {
                            if let prop = mat[idx] {
                                print("\(indent)            • \(prop.name) : \(prop.type)")
                            }
                        }
                    } else {
                        print("\(indent)         material = NONE")
                    }
                }
            }
        }

        if let xform = object.transform {
            let m = xform.matrix
            print("\(indent)   ↳ Transform:")
            print("\(indent)      [\(m.columns.0)]")
            print("\(indent)      [\(m.columns.1)]")
            print("\(indent)      [\(m.columns.2)]")
            print("\(indent)      [\(m.columns.3)]")
        }

        for child in object.children.objects {
            printModelTree(child, indent: indent + "   ")
        }
    }
}
