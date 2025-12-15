// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT

import Foundation
import Metal
import MetalKit
import ModelIO
import simd

final class MetalPBRLoader {
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
        var transform: simd_float4x4
        var material: PBRMaterial
        var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
    }

    struct PBRModel {
        var meshes: [PBRMesh]
    }

    private let device: MTLDevice
    private let meshAllocator: MTKMeshBufferAllocator
    private let textureLoader: MTKTextureLoader
    private var textureCache: [URL: MTLTexture] = [:]

    init(device: MTLDevice) {
        self.device = device
        self.meshAllocator = MTKMeshBufferAllocator(device: device)
        self.textureLoader = MTKTextureLoader(device: device)
    }

    func loadModel(from url: URL) throws -> (model: PBRModel, referenceMesh: MDLMesh) {
        let asset = MDLAsset(
            url: url,
            vertexDescriptor: nil,
            bufferAllocator: meshAllocator
        )
        asset.loadTextures()

        var pbrMeshes: [PBRMesh] = []
        var firstMDLMesh: MDLMesh?

        func worldTransform(for object: MDLObject, parent: simd_float4x4) -> simd_float4x4 {
            if let t = object.transform as? MDLTransform {
                return parent * t.matrix
            }
            return parent
        }

        func process(object: MDLObject, parentTransform: simd_float4x4) {
            let world = worldTransform(for: object, parent: parentTransform)

            if let mesh = object as? MDLMesh {

                if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
                    mesh.addNormals(
                        withAttributeNamed: MDLVertexAttributeNormal,
                        creaseThreshold: 0.0
                    )
                }

                if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTangent) == nil {
                    mesh.addOrthTanBasis(
                        forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                        normalAttributeNamed: MDLVertexAttributeNormal,
                        tangentAttributeNamed: MDLVertexAttributeTangent
                    )
                }

                if firstMDLMesh == nil {
                    firstMDLMesh = mesh
                }

                do {
                    mesh.vertexDescriptor = makePBRVertexDescriptor()
                    let mtkMesh = try MTKMesh(mesh: mesh, device: device)

                    let chosenMaterial: MDLMaterial? =
                        (mesh.submeshes as? [MDLSubmesh])?
                        .compactMap { $0.material }
                        .first

                    let material = makeMaterial(from: chosenMaterial)

                    let bb = mesh.boundingBox
                    let bounds = (
                        min: SIMD3<Float>(bb.minBounds),
                        max: SIMD3<Float>(bb.maxBounds)
                    )

                    pbrMeshes.append(
                        PBRMesh(
                            mtkMesh: mtkMesh,
                            transform: world,
                            material: material,
                            bounds: bounds
                        )
                    )
                } catch {
                    print("warning: MDL→MTK conversion failed for mesh \(mesh.name): \(error)")
                }
            }

            for child in object.children.objects {
                process(object: child, parentTransform: world)
            }
        }

        for i in 0..<asset.count {
            process(
                object: asset.object(at: i),
                parentTransform: matrix_identity_float4x4
            )
        }

        guard let referenceMesh = firstMDLMesh else {
            throw NSError(
                domain: "MetalPBRModelLoader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No MDLMesh found in asset"]
            )
        }

        return (PBRModel(meshes: pbrMeshes), referenceMesh)
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

    private func makeMaterial(from mdlMaterial: MDLMaterial?) -> PBRMaterial {
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

        func colorFrom(_ semantic: MDLMaterialSemantic, default value: SIMD4<Float>) -> SIMD4<Float> {
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
            case .color:
                if let cg = p.color {
                    let comps = cg.components ?? [0, 0, 0, 1]
                    return SIMD4<Float>(
                        Float(comps[0]),
                        Float(comps.count > 1 ? comps[1] : comps[0]),
                        Float(comps.count > 2 ? comps[2] : comps[0]),
                        Float(comps.count > 3 ? comps[3] : 1.0)
                    )
                }
                return value
            default:
                return value
            }
        }

        func loadTexture(_ semantic: MDLMaterialSemantic, sRGB: Bool) -> MTLTexture? {
            guard let prop = mat.property(with: semantic) else { return nil }

            if prop.type == .texture,
               let sampler = prop.textureSamplerValue,
               let mdlTex = sampler.texture {
                return try? textureLoader.newTexture(
                    texture: mdlTex,
                    options: [
                        .SRGB: sRGB,
                        .generateMipmaps: true
                    ]
                )
            }

            let url: URL?
            switch prop.type {
            case .URL:    url = prop.urlValue
            case .string: url = prop.stringValue.map { URL(fileURLWithPath: $0) }
            default:      url = nil
            }

            guard let finalURL = url else { return nil }

            if let cached = textureCache[finalURL] {
                return cached
            }

            if let tex = try? textureLoader.newTexture(
                URL: finalURL,
                options: [
                    .SRGB: sRGB,
                    .generateMipmaps: true
                ]
            ) {
                textureCache[finalURL] = tex
                return tex
            }

            return nil
        }

        return PBRMaterial(
            baseColor: colorFrom(.baseColor, default: SIMD4<Float>(0.8, 0.8, 0.8, 1.0)),
            metallic:  floatFrom(.metallic,  default: 0.0),
            roughness: floatFrom(.roughness, default: 0.5),
            baseColorTexture: loadTexture(.baseColor,          sRGB: true),
            normalTexture:    loadTexture(.tangentSpaceNormal, sRGB: false),
            metallicTexture:  loadTexture(.metallic,           sRGB: false),
            roughnessTexture: loadTexture(.roughness,          sRGB: false)
        )
    }
}
