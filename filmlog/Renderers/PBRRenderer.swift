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
        var baseColorTexture: URL?
        var normalTexture: URL?
        var metallicTexture: URL?
        var roughnessTexture: URL?
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
    
    struct ModelUniforms {
        var mvp: simd_float4x4
        var normalMatrix: simd_float3x3
    }
    
    private(set) weak var mtkView: MTKView?
    private var device: MTLDevice!
    private var meshAllocator: MTKMeshBufferAllocator!
    private var pipeline: MTLRenderPipelineState?
    private var model: PBRModel?
    private var depthState: MTLDepthStencilState!
    
    init(device: MTLDevice, mtkView: MTKView) {
        self.device = device
        self.mtkView = mtkView
        self.meshAllocator = MTKMeshBufferAllocator(device: device)

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        self.depthState = device.makeDepthStencilState(descriptor: depthDesc)
    }
    
    func draw(with encoder: MTLRenderCommandEncoder, in view: MTKView) {
        guard let model = self.model,
              let firstMesh = model.meshes.first,
              let pipeline = self.pipeline else { return }

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
        let modelMatrix = float4x4(scale: 0.75)

        let mvp = projection * viewMatrix * modelMatrix
        var uniforms = ModelUniforms(
            mvp: mvp,
            normalMatrix: simd_float3x3(fromModelMatrix: modelMatrix)
        )
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)

        for (i, vtx) in firstMesh.mtkMesh.vertexBuffers.enumerated() {
            encoder.setVertexBuffer(vtx.buffer, offset: vtx.offset, index: i)
        }

        encoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<ModelUniforms>.stride,
            index: 10
        )

        for sub in firstMesh.mtkMesh.submeshes {
            encoder.drawIndexedPrimitives(
                type: sub.primitiveType,
                indexCount: sub.indexCount,
                indexType: sub.indexType,
                indexBuffer: sub.indexBuffer.buffer,
                indexBufferOffset: sub.indexBuffer.offset
            )
        }
    }

    func loadModel(from url: URL) {
        guard let allocator = meshAllocator else {
            return
        }

        let asset = MDLAsset(url: url,
                             vertexDescriptor: nil,
                             bufferAllocator: allocator)

        for i in 0..<asset.count {
            let obj = asset.object(at: i)
            printModelTree(obj, indent: "   ")
        }

        var pbrMeshes: [PBRMesh] = []
        var firstMDLMesh: MDLMesh? = nil

        func worldTransform(for object: MDLObject, parent: float4x4) -> float4x4 {
            if let t = object.transform as? MDLTransform {
                return parent * t.matrix
            } else {
                return parent
            }
        }

        func process(object: MDLObject, parentTransform: float4x4) {
            let world = worldTransform(for: object, parent: parentTransform)
            if let mesh = object as? MDLMesh {
                mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal,
                                creaseThreshold: 0)

                if firstMDLMesh == nil { firstMDLMesh = mesh }
                do {
                    let mtkMesh = try MTKMesh(mesh: mesh, device: device)

                    let mdlSub = (mesh.submeshes?.first as? MDLSubmesh)
                    let material = makeMaterial(from: mdlSub?.material)

                    let bb = mesh.boundingBox
                    let localMin = SIMD3<Float>(bb.minBounds)
                    let localMax = SIMD3<Float>(bb.maxBounds)

                    let bounds = (min: localMin, max: localMax)

                    let pbr = PBRMesh(
                        mtkMesh: mtkMesh,
                        transform: world,
                        material: material,
                        bounds: bounds
                    )
                    pbrMeshes.append(pbr)
                }
                catch {
                    print("mdl to mdk conversion failed:", error)
                }
            }

            for child in object.children.objects {
                process(object: child, parentTransform: world)
            }
        }

        for i in 0..<asset.count {
            let obj = asset.object(at: i)
            process(object: obj, parentTransform: matrix_identity_float4x4)
        }

        if let mdl = firstMDLMesh {
            do {
                self.pipeline = try makePipeline(
                    mdlMesh: mdl,
                    vertexFunction: "modelPBRVS",
                    fragmentFunction: "modelPBRFS"
                )
            }
            catch {
                print("failed to build PBR pipeline:", error)
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
            guard let p = mat.property(with: semantic) else { return value }
            
            switch p.type {
            case .float:  return p.floatValue
            case .float2: return p.float2Value.x
            case .float3: return p.float3Value.x
            case .float4: return p.float4Value.x
            default:      return value
            }
        }
        
        func colorFrom(_ semantic: MDLMaterialSemantic,
                       default value: SIMD4<Float>) -> SIMD4<Float> {
            guard let p = mat.property(with: semantic) else { return value }

            switch p.type {
            case .float3:
                let c = p.float3Value
                return SIMD4<Float>(c.x, c.y, c.z, 1.0)

            case .float4:
                let c = p.float4Value
                return SIMD4<Float>(c.x, c.y, c.z, c.w)

            case .float:
                let g = p.floatValue
                return SIMD4<Float>(g, g, g, 1.0)

            default:
                return value
            }
        }
        
        func textureURL(_ semantic: MDLMaterialSemantic) -> URL? {
            guard let p = mat.property(with: semantic) else { return nil }
            switch p.type {
            case .URL:    return p.urlValue
            case .string: return p.stringValue.flatMap { URL(fileURLWithPath: $0) }
            default:      return nil
            }
        }

        let baseColor = colorFrom(.baseColor, default: SIMD4<Float>(0.8, 0.8, 0.8, 1.0))
        let metallic  = floatFrom(.metallic, default: 0.0)
        let roughness = floatFrom(.roughness, default: 0.5)

        return PBRMaterial(
            baseColor: baseColor,
            metallic: metallic,
            roughness: roughness,
            baseColorTexture: textureURL(.baseColor),
            normalTexture: textureURL(.tangentSpaceNormal),
            metallicTexture: textureURL(.metallic),
            roughnessTexture: textureURL(.roughness)
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
        desc.colorAttachments[0].pixelFormat = mtkView?.colorPixelFormat ?? .bgra8Unorm
        desc.depthAttachmentPixelFormat = .depth32Float

        return try device.makeRenderPipelineState(descriptor: desc)
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
