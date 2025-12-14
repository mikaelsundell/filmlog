// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import MetalKit
import ModelIO
import simd

final class MetalPBRRenderer {
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
        var _pad0: SIMD3<Float> = .zero
    }

    var shaderControls = MetalShaderControls()
    var environmentTexture: MTLTexture?
    var viewMatrix: simd_float4x4?
    var worldPosition: SIMD3<Float>?

    var shadowPlaneZ: Float = 0.0
    var shadowStrength: Float = 0.50
    var groundSizeMultiplier: Float = 2.0
    
    var lightDirection = normalize(SIMD3<Float>(0.0, 0.0001, -1.0))

    private(set) weak var mtkView: MTKView?

    private var device: MTLDevice
    private var meshAllocator: MTKMeshBufferAllocator

    private var model: PBRModel?

    private var pbrPipeline: MTLRenderPipelineState?
    private var shadowDepthPipeline: MTLRenderPipelineState?
    private var groundPipeline: MTLRenderPipelineState?

    private var modelDepthState: MTLDepthStencilState
    private var groundDepthState: MTLDepthStencilState
    private var shadowDepthState: MTLDepthStencilState

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

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        self.modelDepthState = device.makeDepthStencilState(descriptor: depthDesc)!

        let groundDepthDesc = MTLDepthStencilDescriptor()
        groundDepthDesc.depthCompareFunction = .less
        groundDepthDesc.isDepthWriteEnabled = true
        self.groundDepthState = device.makeDepthStencilState(descriptor: groundDepthDesc)!

        let shadowDepthDesc = MTLDepthStencilDescriptor()
        shadowDepthDesc.depthCompareFunction = .less
        shadowDepthDesc.isDepthWriteEnabled = true
        self.shadowDepthState = device.makeDepthStencilState(descriptor: shadowDepthDesc)!

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
        rebuildShadowMapResources()
    }

    func renderShadowMap(commandBuffer: MTLCommandBuffer) {
        guard
            let model,
            let shadowPassDesc,
            let shadowDepthPipeline
        else { return }

        let globalModelScale = simd_float4x4(scale: 1.00)

        let (lightVP, _, _) = computeLightVP(
            model: model,
            globalModelScale: globalModelScale
        )

        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowPassDesc)!
        encoder.label = "ShadowDepthEncoder"

        encoder.setRenderPipelineState(shadowDepthPipeline)
        encoder.setDepthStencilState(shadowDepthState)
        encoder.setCullMode(.back)

        for mesh in model.meshes {
            let modelMatrix = globalModelScale * mesh.transform
            var su = ShadowDepthUniforms(lightMVP: lightVP * modelMatrix)

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

    func drawMainPass(
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
        let globalModelScale = simd_float4x4(scale: 0.75)

        let (lightVP, modelCenter, footprint) =
            computeLightVP(model: model, globalModelScale: globalModelScale)

        drawGroundReceiver(
            with: encoder,
            projection: projection,
            viewMatrix: localViewMatrix,
            lightVP: lightVP,
            center: modelCenter,
            footprintRadius: footprint
        )

        encoder.setRenderPipelineState(pbrPipeline)
        encoder.setDepthStencilState(modelDepthState)
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

    private func rebuildShadowMapResources() {
        let size = shadowMapSize

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: size,
            height: size,
            mipmapped: false
        )
        depthDesc.usage = [.renderTarget, .shaderRead]
        depthDesc.storageMode = .private

        shadowDepthTexture = device.makeTexture(descriptor: depthDesc)
        shadowDepthTexture?.label = "ShadowDepthMap"

        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = shadowDepthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1.0
        shadowPassDesc = pass
    }

    private func renderShadowMap(
        commandBuffer: MTLCommandBuffer,
        model: PBRModel,
        globalModelScale: simd_float4x4,
        lightVP: simd_float4x4
    ) {
        guard let shadowPassDesc,
              let shadowDepthPipeline,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowPassDesc)
        else { return }

        encoder.label = "ShadowDepthPass"
        encoder.setRenderPipelineState(shadowDepthPipeline)
        encoder.setDepthStencilState(shadowDepthState)
        encoder.setCullMode(.back)

        for mesh in model.meshes {
            // IMPORTANT: use same model scale so silhouette matches main pass
            let modelMatrix = globalModelScale * mesh.transform
            var su = ShadowDepthUniforms(lightMVP: lightVP * modelMatrix)

            // position attribute must be attribute(0) => buffer(0) layout for our shadow VS
            // MTKMesh vertex buffers contain interleaved attributes. We reuse the same vertex buffer 0.
            
            if let vb0 = mesh.mtkMesh.vertexBuffers.first {
                encoder.setVertexBuffer(vb0.buffer, offset: vb0.offset, index: 0)
            }

            encoder.setVertexBytes(&su, length: MemoryLayout<ShadowDepthUniforms>.stride, index: 1)

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
    
    private func drawGroundReceiver(
        with encoder: MTLRenderCommandEncoder,
        projection: simd_float4x4,
        viewMatrix: simd_float4x4,
        lightVP: simd_float4x4,
        center: SIMD3<Float>,
        footprintRadius: Float
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
            baseColor: SIMD4<Float>(0.08, 0.08, 0.08, 1.0),
            shadowStrength: shadowStrength
        )

        encoder.setRenderPipelineState(groundPipeline)
        encoder.setDepthStencilState(groundDepthState)
        encoder.setCullMode(.none)

        encoder.setVertexBuffer(groundVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&gu, length: MemoryLayout<GroundUniforms>.stride, index: 1)

        encoder.setFragmentTexture(shadowDepthTexture, index: 0)
        encoder.setFragmentSamplerState(shadowSamplerState, index: 0)
        encoder.setFragmentBytes(&gu, length: MemoryLayout<GroundUniforms>.stride, index: 1)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    private func computeLightVP(model: PBRModel, globalModelScale: simd_float4x4)
        -> (simd_float4x4, SIMD3<Float>, Float)
    {
        let b = modelBoundsWorld(model, globalModelScale: globalModelScale)
        let minB = b?.min ?? SIMD3<Float>(-0.5, 0.0, -0.5)
        let maxB = b?.max ?? SIMD3<Float>( 0.5, 1.0,  0.5)

        let center = (minB + maxB) * 0.5
        let ext = (maxB - minB)
        let footprint = 0.5 * max(ext.x, ext.z)

        // build a directional light “camera”
        // position the light a fixed distance away along -lightDirection.
        
        let lightDir = normalize(lightDirection)
        let distance: Float = max(ext.y, max(ext.x, ext.z)) * 2.5 + 2.0
        let lightPos = center - lightDir * distance

        let lightView = simd_float4x4(
            lookAt: lightPos,
            target: center,
            up: SIMD3<Float>(0, 0, 1)
        )

        // ortho extents: include footprint + padding
        let pad: Float = max(footprint, 0.5) * 1.5
        let halfW = max(ext.x, ext.z) * 0.5 + pad
        let halfH = max(ext.x, ext.z) * 0.5 + pad

        // near/far along light view direction; keep generous
        let nearZ: Float = 0.1
        let farZ: Float = distance * 3.0 + ext.y * 2.0

        let lightProj = simd_float4x4(
            orthoLeft: -halfW, right: halfW,
            bottom: -halfH, top: halfH,
            nearZ: nearZ, farZ: farZ
        )

        return (lightProj * lightView, center, footprint)
    }

    private func modelBoundsWorld(_ model: PBRModel, globalModelScale: simd_float4x4)
        -> (min: SIMD3<Float>, max: SIMD3<Float>)?
    {
        var minOut = SIMD3<Float>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
        var maxOut = SIMD3<Float>(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
        var found = false

        for mesh in model.meshes {
            guard let bounds = mesh.bounds else { continue }

            let t = globalModelScale * mesh.transform
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
                let wc = (t * SIMD4<Float>(c, 1)).xyz
                minOut = simd.min(minOut, wc)
                maxOut = simd.max(maxOut, wc)
            }

            found = true
        }

        return found ? (minOut, maxOut) : nil
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
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: meshAllocator)
        asset.loadTextures()

        var pbrMeshes: [PBRMesh] = []
        var firstMDLMesh: MDLMesh?

        func worldTransform(for object: MDLObject, parent: simd_float4x4) -> simd_float4x4 {
            if let t = object.transform as? MDLTransform { return parent * t.matrix }
            return parent
        }

        func process(object: MDLObject, parentTransform: simd_float4x4) {
            let world = worldTransform(for: object, parent: parentTransform)

            if let mesh = object as? MDLMesh {
                if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
                    mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.0)
                }
                if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTangent) == nil {
                    mesh.addOrthTanBasis(
                        forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                        normalAttributeNamed: MDLVertexAttributeNormal,
                        tangentAttributeNamed: MDLVertexAttributeTangent
                    )
                }

                if firstMDLMesh == nil { firstMDLMesh = mesh }

                do {
                    mesh.vertexDescriptor = makePBRVertexDescriptor()
                    let mtkMesh = try MTKMesh(mesh: mesh, device: device)

                    var chosenMat: MDLMaterial?
                    if let subs = mesh.submeshes as? [MDLSubmesh] {
                        chosenMat = subs.compactMap { $0.material }.first
                    }

                    let pbrMaterial = makeMaterial(from: chosenMat)

                    let bb = mesh.boundingBox
                    let bounds = (
                        min: SIMD3<Float>(bb.minBounds),
                        max: SIMD3<Float>(bb.maxBounds)
                    )

                    pbrMeshes.append(PBRMesh(
                        mtkMesh: mtkMesh,
                        transform: world,
                        material: pbrMaterial,
                        bounds: bounds
                    ))

                } catch {
                    print("warning: MDL→MTK conversion failed for mesh \(mesh.name): \(error)")
                }
            }

            for child in object.children.objects {
                process(object: child, parentTransform: world)
            }
        }

        for i in 0..<asset.count {
            process(object: asset.object(at: i), parentTransform: matrix_identity_float4x4)
        }
        self.model = PBRModel(meshes: pbrMeshes)
        
        guard let mdl = firstMDLMesh else {
            print("warning: no MDLMesh found, pipeline not built.")
            return
        }

        do {
            self.pbrPipeline = try makePBRPipeline(mdlMesh: mdl, vertexFunction: "modelPBRVS", fragmentFunction: "modelPBRFS")
            self.shadowDepthPipeline =
                try makeShadowDepthPipeline(
                    mdlMesh: mdl,
                    vertexFunction: "shadowDepthVS",
                    fragmentFunction: "shadowDepthFS"
                )
            self.groundPipeline = try makeGroundPipeline(vertexFunction: "groundVS", fragmentFunction: "groundFS")
        } catch {
            print("warning: pipeline build failed: \(error)")
        }
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

            // Embedded (USDZ)
            if prop.type == .texture,
               let sampler = prop.textureSamplerValue,
               let mdlTex = sampler.texture {
                do {
                    return try textureLoader.newTexture(
                        texture: mdlTex,
                        options: [
                            .SRGB: sRGB,
                            .generateMipmaps: true
                        ]
                    )
                } catch {
                    print("warning: embedded texture load failed: \(error)")
                }
            }
            var url: URL?
            switch prop.type {
            case .URL:    url = prop.urlValue
            case .string: url = prop.stringValue.map { URL(fileURLWithPath: $0) }
            default:      break
            }
            guard let finalURL = url else { return nil }

            if let cached = textureCache[finalURL] { return cached }

            do {
                let tex = try textureLoader.newTexture(
                    URL: finalURL,
                    options: [
                        .SRGB: sRGB,
                        .generateMipmaps: true
                    ]
                )
                textureCache[finalURL] = tex
                return tex
            } catch {
                print("warning: URL texture load failed for \(finalURL): \(error)")
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
        desc.vertexDescriptor = metalVertexDescriptor   // ✅ REQUIRED
        desc.depthAttachmentPixelFormat = .depth32Float
        desc.rasterSampleCount = 1

        return try device.makeRenderPipelineState(descriptor: desc)
    }

    private func makeGroundPipeline(vertexFunction: String, fragmentFunction: String) throws -> MTLRenderPipelineState {
        let library = try device.makeDefaultLibrary(bundle: .main)

        guard let vfn = library.makeFunction(name: vertexFunction),
              let ffn = library.makeFunction(name: fragmentFunction)
        else {
            throw NSError(domain: "MetalPBRRenderer", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Missing ground shader functions \(vertexFunction)/\(fragmentFunction)"])
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.rasterSampleCount = mtkView?.sampleCount ?? 1
        desc.colorAttachments[0].pixelFormat = mtkView?.colorPixelFormat ?? .bgra8Unorm_srgb
        desc.depthAttachmentPixelFormat = mtkView?.depthStencilPixelFormat ?? .depth32Float
        
        let attachment = desc.colorAttachments[0]!
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try device.makeRenderPipelineState(descriptor: desc)
    }
}

