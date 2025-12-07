// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import ARKit
import Foundation
import MetalKit

class ARRenderer {
    struct CameraData {
        var resolution: SIMD2<Float>
        var intrinsics: simd_float3x3
        var transform:  simd_float4x4   // camera in world
        var projection: simd_float4x4   // clip = P * V * M
    }
    
    struct IndicatorUniforms {
        var modelViewProjectionMatrix: simd_float4x4
        var time: Float
        var radius: Float
        var thickness: Float
        var color: SIMD3<Float>
        var padding: Float = 0 // padding to keep 16-byte alignment
    }
    
    struct ModelUniforms {
        var mvp: simd_float4x4
        var normalMatrix: simd_float3x3
    }
    
    public var planeTransform: simd_float4x4? {
        didSet {
            if let m = planeTransform {
                planeY = m.columns.3.y
            }
        }
    }
    public private(set) var planeY: Float = 0
    
    public var cameraData: CameraData?

    private(set) weak var mtkView: MTKView?
    private var device: MTLDevice!
    private var depthState: MTLDepthStencilState!
    private var meshAllocator: MTKMeshBufferAllocator!
    private var testCubePipeline: MTLRenderPipelineState?
    private var pipeline: MTLRenderPipelineState?
    private var testCubeModel: MTKMesh?
    private var model: MTKMesh?
    
    private var indicatorUniforms = IndicatorUniforms(
        modelViewProjectionMatrix: matrix_identity_float4x4,
        time: 0,
        radius: 0.80,
        thickness: 0.20,
        color: SIMD3<Float>(1, 1, 1),
        padding: 0
    )

    private var startTime = CACurrentMediaTime()

    init(device: MTLDevice, mtkView: MTKView) {
        self.device = device
        self.mtkView = mtkView
        self.meshAllocator = MTKMeshBufferAllocator(device: device)
        
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled  = true
        depthState = device.makeDepthStencilState(descriptor: depthDesc)

        makeTestCubeModel()
        makeIndicatorModel()
    }
    
    func draw(with encoder: MTLRenderCommandEncoder, in view: MTKView) {
        guard let cameraData = self.cameraData,
              let model = self.model,
              let testCubeModel = self.testCubeModel,
              let testCubePipeline = self.testCubePipeline,
              let pipeline = self.pipeline else { return }
        
        var uniforms = ModelUniforms(
            mvp: matrix_identity_float4x4,
            normalMatrix: matrix_identity_float3x3
        )
        
        drawMesh(
            testCubeModel,
            pipeline: testCubePipeline,
            modelMatrix: makeInitialMatrix(),
            uniforms: &uniforms,
            uniformIndex: 10,
            encoder: encoder
        )
        
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let modelMatrix = makeFloorHitMatrix(
            screenPoint: center,
            viewSize: view.bounds.size,
            planeY: planeY
        ) ?? makeInitialMatrix()
        
        drawMesh(
            testCubeModel,
            pipeline: testCubePipeline,
            modelMatrix: modelMatrix,
            uniforms: &uniforms,
            uniformIndex: 10,
            encoder: encoder
        )

        indicatorUniforms.time = Float(CACurrentMediaTime() - startTime)
        indicatorUniforms.radius = 0.80
        indicatorUniforms.thickness = 0.20
        indicatorUniforms.color = SIMD3<Float>(0.2, 0.7, 1.0)
        
        drawMesh(
            model,
            pipeline: pipeline,
            modelMatrix: modelMatrix,
            uniforms: &indicatorUniforms,
            uniformIndex: 10,
            encoder: encoder
        )
    }
    
    func drawMesh<T>(
        _ mesh: MTKMesh,
        pipeline: MTLRenderPipelineState,
        modelMatrix: simd_float4x4,
        uniforms: inout T,
        uniformIndex: Int,
        encoder: MTLRenderCommandEncoder
    ) {
        guard let cameraData = self.cameraData else { return }

        let projection = cameraData.projection
        let viewM      = simd_inverse(cameraData.transform)
        let mvp        = projection * viewM * modelMatrix

        if var u = uniforms as? ModelUniforms {
            let nm = simd_float3x3(
                SIMD3(modelMatrix.columns.0.x, modelMatrix.columns.0.y, modelMatrix.columns.0.z),
                SIMD3(modelMatrix.columns.1.x, modelMatrix.columns.1.y, modelMatrix.columns.1.z),
                SIMD3(modelMatrix.columns.2.x, modelMatrix.columns.2.y, modelMatrix.columns.2.z)
            )
            u.mvp = mvp
            u.normalMatrix = simd_transpose(simd_inverse(nm))
            uniforms = u as! T
        }
        else if var u = uniforms as? IndicatorUniforms {
            u.modelViewProjectionMatrix = mvp
            uniforms = u as! T
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)

        for (i, vtx) in mesh.vertexBuffers.enumerated() {
            encoder.setVertexBuffer(vtx.buffer, offset: vtx.offset, index: i)
        }

        encoder.setVertexBytes(&uniforms,
                           length: MemoryLayout<T>.stride,
                           index: uniformIndex)
        
        encoder.setFragmentBytes(&uniforms,
                             length: MemoryLayout<T>.stride,
                             index: uniformIndex)

        for sub in mesh.submeshes {
            encoder.drawIndexedPrimitives(
                type: sub.primitiveType,
                indexCount: sub.indexCount,
                indexType: sub.indexType,
                indexBuffer: sub.indexBuffer.buffer,
                indexBufferOffset: sub.indexBuffer.offset
            )
        }
    }
    
    private func makeTestCubeModel() {
        let allocator = MTKMeshBufferAllocator(device: device)
        
        let box = MDLMesh(
            boxWithExtent: [0.2, 0.2, 0.2],
            segments: [1, 1, 1],
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )

        box.addNormals(withAttributeNamed: MDLVertexAttributeNormal,
                       creaseThreshold: 0)

        let vdesc = box.vertexDescriptor

        if let pos = vdesc.attributes[0] as? MDLVertexAttribute {
            pos.name = MDLVertexAttributePosition
            pos.format = .float3
            pos.bufferIndex = 0
            pos.offset = 0
        }

        if let nor = vdesc.attributes[1] as? MDLVertexAttribute {
            nor.name = MDLVertexAttributeNormal
            nor.format = .float3
            nor.bufferIndex = 0
        }

        let vertexCount = box.vertexCount
        let faceCount = 6
        let vertsPerFace = vertexCount / faceCount
        var colors = [SIMD4<Float>](repeating: .zero, count: vertexCount)

        for face in 0..<faceCount {
            let randomColor = SIMD4<Float>(
                Float.random(in: 0.1...1),
                Float.random(in: 0.1...1),
                Float.random(in: 0.1...1),
                1.0
            )

            let start = face * vertsPerFace
            let end   = start + vertsPerFace

            for i in start..<end {
                colors[i] = randomColor
            }
        }

        let colorAttr = MDLVertexAttribute(
            name: MDLVertexAttributeColor,
            format: .float4,
            offset: 0,
            bufferIndex: 1
        )
        vdesc.attributes.add(colorAttr)

        let colorLayout = MDLVertexBufferLayout(
            stride: MemoryLayout<SIMD4<Float>>.size
        )
        vdesc.layouts.add(colorLayout)

        let colorData = Data(
            bytes: colors,
            count: colors.count * MemoryLayout<SIMD4<Float>>.size
        )

        let colorBuffer = allocator.newBuffer(with: colorData, type: .vertex)

        box.vertexBuffers.append(colorBuffer)

        do {
            testCubeModel = try MTKMesh(mesh: box, device: device)
        } catch {
            print("failed to build test cube model:", error)
            testCubeModel = nil
            return
        }

        do {
            testCubePipeline = try makePipeline(
                mdlMesh: box,
                vertexFunction: "modelVS",
                fragmentFunction: "modelFS"
            )
        } catch {
            print("failed to build test pipeline:", error.localizedDescription)
        }
    }
    
    private func makeIndicatorModel() {
        let allocator = MTKMeshBufferAllocator(device: device)
        let plane = MDLMesh.newPlane(
            withDimensions: [10.0, 10.0],
            segments: [1, 1],
            geometryType: .triangles,
            allocator: allocator
        )

        plane.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0)
        
        print(plane.vertexDescriptor)

        do {
            model = try MTKMesh(mesh: plane, device: device)
        } catch {
            print("failed to build indicator model: \(error)")
            model = nil
            return
        }

        do {
            pipeline = try makePipeline(
                mdlMesh: plane,
                vertexFunction: "indicatorVS",
                fragmentFunction: "indicatorFS"
            )
        } catch {
            print("failed to build floor indicator pipeline:", error.localizedDescription)
        }
    }

    private func makeInitialMatrix() -> float4x4 {
        return float4x4(translation: SIMD3<Float>(0, 0, 0)) * // origin is where we stand initially
               float4x4(scale: 0.2)
    }

    private func makeFloorHitMatrix(
        screenPoint: CGPoint,
        viewSize: CGSize,
        planeY: Float
    ) -> float4x4? {
        guard let cameraData = self.cameraData else { return nil }
        
        let ndcX =  (2.0 * Float(screenPoint.x) / Float(viewSize.width))  - 1.0
        let ndcY = -(2.0 * Float(screenPoint.y) / Float(viewSize.height)) + 1.0
        let clip = SIMD4<Float>(ndcX, ndcY, 1.0, 1.0)

        // unproject
        let projInv = simd_inverse(cameraData.projection)
        var viewSpace = projInv * clip
        viewSpace /= viewSpace.w

        let dirCamera = normalize(SIMD3<Float>(viewSpace.x, viewSpace.y, viewSpace.z))

        // convert ray to world
        let camTransform = cameraData.transform
        let originWorld = SIMD3<Float>(
            camTransform.columns.3.x,
            camTransform.columns.3.y,
            camTransform.columns.3.z
        )

        let dirWorld4 = camTransform * SIMD4<Float>(dirCamera, 0.0)
        var dirWorld  = normalize(SIMD3<Float>(dirWorld4.x, dirWorld4.y, dirWorld4.z))

        // cap to horizon
        if dirWorld.y >= 0 {
            // project to horizontal direction (XZ only)
            dirWorld = normalize(SIMD3<Float>(dirWorld.x, -0.001, dirWorld.z))
        }

        // plane intersection
        let denom = dirWorld.y
        if abs(denom) < 1e-5 { return nil }

        let t = (planeY - originWorld.y) / denom
        if t <= 0 { return nil }

        let hit = originWorld + dirWorld * t

        // build transform
        let translation = float4x4(translation: hit)
        let scale       = float4x4(scale: 0.2)

        return translation * scale
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
            throw NSError(domain: "ARRenderer",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey:
                             "Function \(vertexFunction) or \(fragmentFunction) not found in Metal library"])
        }

        let metalVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mdlMesh.vertexDescriptor)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.vertexDescriptor = metalVertexDescriptor
        desc.colorAttachments[0].pixelFormat = mtkView?.colorPixelFormat ?? .bgra8Unorm
        desc.depthAttachmentPixelFormat = .depth32Float

        return try device.makeRenderPipelineState(descriptor: desc)
    }
}
