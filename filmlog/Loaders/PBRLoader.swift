// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import Metal
import MetalKit
import ModelIO

public struct PBRMaterial {
    public var baseColor: SIMD4<Float>
    public var metallic: Float
    public var roughness: Float

    public var baseColorTexture: MTLTexture?
    public var normalTexture: MTLTexture?
    public var metallicTexture: MTLTexture?
    public var roughnessTexture: MTLTexture?

    public init(
        baseColor: SIMD4<Float> = SIMD4(0.8, 0.8, 0.8, 1.0),
        metallic: Float = 0.0,
        roughness: Float = 0.5,
        baseColorTexture: MTLTexture? = nil,
        normalTexture: MTLTexture? = nil,
        metallicTexture: MTLTexture? = nil,
        roughnessTexture: MTLTexture? = nil
    ) {
        self.baseColor = baseColor
        self.metallic = metallic
        self.roughness = roughness
        self.baseColorTexture = baseColorTexture
        self.normalTexture = normalTexture
        self.metallicTexture = metallicTexture
        self.roughnessTexture = roughnessTexture
    }
}

public struct PBRMesh {
    public let mesh: MTKMesh
    public var transform: simd_float4x4
    public var material: PBRMaterial
    public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?

    public init(
        mesh: MTKMesh,
        transform: simd_float4x4 = matrix_identity_float4x4,
        material: PBRMaterial = PBRMaterial(),
        bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? = nil
    ) {
        self.mesh = mesh
        self.transform = transform
        self.material = material
        self.bounds = bounds
    }
}

public struct PBRModel {
    public let meshes: [PBRMesh]
    public let vertexDescriptor: MDLVertexDescriptor

    public init(
        meshes: [PBRMesh],
        vertexDescriptor: MDLVertexDescriptor
    ) {
        self.meshes = meshes
        self.vertexDescriptor = vertexDescriptor
    }
}

public enum PBRPrimitive {
    case box(size: SIMD3<Float>)
    case plane(size: SIMD2<Float>)
    case triangle
}

public final class PBRMaterialLoader {
    private let textureLoader: MTKTextureLoader
    private var textureCache: [URL: MTLTexture] = [:]

    public init(device: MTLDevice) {
        self.textureLoader = MTKTextureLoader(device: device)
    }

    public func makeMaterial(from mdlMaterial: MDLMaterial?) -> PBRMaterial {
        guard let mat = mdlMaterial else {
            return PBRMaterial(
                baseColor: SIMD4<Float>(0.8, 0.8, 0.8, 1.0),
                metallic: 0.0,
                roughness: 0.5
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
                    let r = Float(comps[0])
                    let g = Float(comps.count > 1 ? comps[1] : comps[0])
                    let b = Float(comps.count > 2 ? comps[2] : comps[0])
                    let a = Float(comps.count > 3 ? comps[3] : 1.0)
                    return SIMD4<Float>(r, g, b, a)
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
                do {
                    return try textureLoader.newTexture(
                        texture: mdlTex,
                        options: [
                            MTKTextureLoader.Option.SRGB: sRGB,
                            MTKTextureLoader.Option.generateMipmaps: true
                        ]
                    )
                } catch {
                    print("failed to create Metal texture from MDLTexture (\(semanticName(semantic))): \(error)")
                    return nil
                }
            }
            var url: URL?
            switch prop.type {
            case .URL:
                url = prop.urlValue

            case .string:
                if let s = prop.stringValue {
                    url = URL(fileURLWithPath: s)
                } else {
                    print("\(semanticName(semantic)) had no stringValue")
                }

            default:
                break
            }

            guard let finalURL = url else { return nil }

            if let cached = textureCache[finalURL] {
                return cached
            }

            do {
                let tex = try textureLoader.newTexture(
                    URL: finalURL,
                    options: [
                        MTKTextureLoader.Option.SRGB: sRGB,
                        MTKTextureLoader.Option.generateMipmaps: true
                    ]
                )
                textureCache[finalURL] = tex
                return tex
            } catch {
                print("failed to load URL texture for \(semanticName(semantic)) from \(finalURL): \(error)")
                return nil
            }
        }

        let baseColor    = colorFrom(.baseColor, default: SIMD4<Float>(0.8, 0.8, 0.8, 1.0))
        let metallic     = floatFrom(.metallic, default: 0.0)
        let roughness    = floatFrom(.roughness, default: 0.5)

        let baseColorTex = loadTexture(.baseColor, sRGB: true)
        let metallicTex  = loadTexture(.metallic, sRGB: false)
        let roughnessTex = loadTexture(.roughness, sRGB: false)
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

public final class PBRModelLoader {
    private let device: MTLDevice
    private let allocator: MTKMeshBufferAllocator
    private let materialLoader: PBRMaterialLoader

    public init(device: MTLDevice, materialLoader: PBRMaterialLoader) {
        self.device = device
        self.allocator = MTKMeshBufferAllocator(device: device)
        self.materialLoader = materialLoader
    }

    public func makePrimitive(
        _ primitive: PBRPrimitive,
        transform: simd_float4x4 = matrix_identity_float4x4,
        material: PBRMaterial = PBRMaterial()
    ) throws -> PBRModel {

        let mdlMesh: MDLMesh

        switch primitive {
        case .box(let size):
            mdlMesh = MDLMesh(
                boxWithExtent: size,
                segments: [1, 1, 1],
                inwardNormals: false,
                geometryType: .triangles,
                allocator: allocator
            )

        case .plane(let size):
            mdlMesh = MDLMesh.newPlane(
                withDimensions: size,
                segments: [1, 1],
                geometryType: .triangles,
                allocator: allocator
            )

        case .triangle:
            mdlMesh = makeTriangle()
        }

        prepareMesh(mdlMesh)
        let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)

        let bb = mdlMesh.boundingBox
        let bounds = (
            min: SIMD3<Float>(bb.minBounds),
            max: SIMD3<Float>(bb.maxBounds)
        )

        let pbrMesh = PBRMesh(
            mesh: mtkMesh,
            transform: transform,
            material: material,
            bounds: bounds
        )

        return PBRModel(
            meshes: [pbrMesh],
            vertexDescriptor: makePBRVertexDescriptor()
        )
    }

    public func loadModel(from url: URL) throws -> PBRModel {
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: allocator)
        asset.loadTextures()

        var meshes: [PBRMesh] = []

        func worldTransform(for object: MDLObject, parent: simd_float4x4) -> simd_float4x4 {
            if let t = object.transform as? MDLTransform {
                return parent * t.matrix
            }
            return parent
        }

        func process(object: MDLObject, parentTransform: simd_float4x4) {
            let world = worldTransform(for: object, parent: parentTransform)
            if let mdlMesh = object as? MDLMesh {
                prepareMesh(mdlMesh)
                do {
                    let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)
                    var chosenMat: MDLMaterial? = nil
                    if let subs = mdlMesh.submeshes as? [MDLSubmesh] {
                        for sm in subs {
                            if let m = sm.material {
                                chosenMat = m
                                break
                            }
                        }
                    }

                    let pbrMaterial = materialLoader.makeMaterial(from: chosenMat)
                    
                    let bb = mdlMesh.boundingBox
                    let bounds = (
                        min: SIMD3<Float>(bb.minBounds),
                        max: SIMD3<Float>(bb.maxBounds)
                    )

                    meshes.append(
                        PBRMesh(
                            mesh: mtkMesh,
                            transform: world,
                            material: pbrMaterial,
                            bounds: bounds
                        )
                    )
                } catch {
                    print("MDL to MTK conversion failed for mesh \(mdlMesh.name): \(error)")
                }
            }

            for child in object.children.objects {
                process(object: child, parentTransform: world)
            }
        }

        for i in 0..<asset.count {
            process(object: asset.object(at: i), parentTransform: matrix_identity_float4x4)
        }

        return PBRModel(
            meshes: meshes,
            vertexDescriptor: makePBRVertexDescriptor()
        )
    }
}

private extension PBRModelLoader {

    func prepareMesh(_ mesh: MDLMesh) {
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

        mesh.vertexDescriptor = makePBRVertexDescriptor()
    }

    func makeTriangle() -> MDLMesh {
        let vertices: [Float] = [
             0.0,  0.1, 0.0,
            -0.1, -0.1, 0.0,
             0.1, -0.1, 0.0
        ]

        let vertexData = Data(
            bytes: vertices,
            count: vertices.count * MemoryLayout<Float>.size
        )
        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)

        let indices: [UInt16] = [0, 1, 2]
        let indexData = Data(
            bytes: indices,
            count: indices.count * MemoryLayout<UInt16>.size
        )
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: 12)

        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: indices.count,
            indexType: .uInt16,
            geometryType: .triangles,
            material: nil
        )

        return MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: 3,
            descriptor: descriptor,
            submeshes: [submesh]
        )
    }

    func makePBRVertexDescriptor() -> MDLVertexDescriptor {
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
}
