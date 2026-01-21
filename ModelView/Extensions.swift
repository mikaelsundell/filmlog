// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import ARKit
import Foundation
import SwiftUI
import simd

extension float3x3 {
    init(_ m: float4x4) {
        self.init([
            SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
            SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
            SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        ])
    }
}

extension float4x4 {

    init(perspectiveFov fovY: Float, aspect: Float, nearZ: Float, farZ: Float) {
        let y = 1 / tan(fovY * 0.5)
        let x = y / aspect
        let z = farZ / (nearZ - farZ)

        self.init(
            SIMD4<Float>( x,  0,   0,   0),
            SIMD4<Float>( 0,  y,   0,   0),
            SIMD4<Float>( 0,  0,   z,  -1),
            SIMD4<Float>( 0,  0,  z * nearZ, 0)
        )
    }

    init(lookAt eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) {
        let f = normalize(target - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)

        self.init(
            SIMD4<Float>( s.x,  u.x, -f.x, 0),
            SIMD4<Float>( s.y,  u.y, -f.y, 0),
            SIMD4<Float>( s.z,  u.z, -f.z, 0),
            SIMD4<Float>(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)
        )
    }

    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(t.x, t.y, t.z, 1)
    }

    init(scale: Float) {
        self = matrix_identity_float4x4
        columns.0.x = scale
        columns.1.y = scale
        columns.2.z = scale
    }

    init(scale v: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.0.x = v.x
        columns.1.y = v.y
        columns.2.z = v.z
    }

    static func rotationX(_ angle: Float) -> float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return float4x4(
            SIMD4(1, 0,  0, 0),
            SIMD4(0, c,  s, 0),
            SIMD4(0, -s, c, 0),
            SIMD4(0, 0,  0, 1)
        )
    }

    static func rotationY(_ angle: Float) -> float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return float4x4(
            SIMD4( c, 0, -s, 0),
            SIMD4( 0, 1,  0, 0),
            SIMD4( s, 0,  c, 0),
            SIMD4( 0, 0,  0, 1)
        )
    }

    static func rotationZ(_ angle: Float) -> float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return float4x4(
            SIMD4( c,  s, 0, 0),
            SIMD4(-s,  c, 0, 0),
            SIMD4( 0,  0, 1, 0),
            SIMD4( 0,  0, 0, 1)
        )
    }
}

extension float4x4 {

    init(
        orthoLeft l: Float,
        right r: Float,
        bottom b: Float,
        top t: Float,
        nearZ n: Float,
        farZ f: Float
    ) {
        let rl = r - l
        let tb = t - b
        let fn = f - n

        self.init(
            SIMD4<Float>( 2.0 / rl, 0, 0, 0),
            SIMD4<Float>( 0, 2.0 / tb, 0, 0),
            SIMD4<Float>( 0, 0, -1.0 / fn, 0),
            SIMD4<Float>(
                -(r + l) / rl,
                -(t + b) / tb,
                -n / fn,
                1
            )
        )
    }
}

extension simd_float3x3 {
    init(fromModelMatrix m: simd_float4x4) {
        let upper = simd_float3x3(
            SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
            SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
            SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        )
        self = upper.inverse.transpose
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

extension simd_float4x4 {
    init(lookAt eye: SIMD3<Float>,
         _ center: SIMD3<Float>,
         _ up: SIMD3<Float>) {
        let f = normalize(center - eye)
        let r = normalize(cross(f, up))
        let u = cross(r, f)
        let t = SIMD3<Float>(
            -dot(r, eye),
            -dot(u, eye),
             dot(f, eye)
        )
        self.init(
            SIMD4<Float>( r.x,  u.x, -f.x, 0),
            SIMD4<Float>( r.y,  u.y, -f.y, 0),
            SIMD4<Float>( r.z,  u.z, -f.z, 0),
            SIMD4<Float>( t.x,  t.y,  t.z, 1)
        )
    }

    var position: SIMD3<Float> {
        SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }

    var forward: SIMD3<Float> {
        -SIMD3(columns.2.x, columns.2.y, columns.2.z)
    }
}
