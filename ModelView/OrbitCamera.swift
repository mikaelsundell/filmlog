// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT

import simd

final class OrbitCamera {

    var target: SIMD3<Float>
    var distance: Float
    var yaw: Float
    var pitch: Float

    let minDistance: Float = 0.5
    let maxDistance: Float = 12.0

    init(eye: SIMD3<Float>, target: SIMD3<Float>) {
        self.target = target

        let offset = eye - target
        self.distance = length(offset)
        self.yaw = atan2(offset.y, offset.x)
        self.pitch = atan2(offset.z, length(SIMD2(offset.x, offset.y)))
    }

    var position: SIMD3<Float> {
        SIMD3(
            distance * cos(pitch) * cos(yaw),
            distance * cos(pitch) * sin(yaw),
            distance * sin(pitch)
        ) + target
    }

    var viewMatrix: simd_float4x4 {
        float4x4(
            lookAt: position,
            target: target,
            up: SIMD3(0, 0, 1)
        )
    }

    func rotate(deltaX: Float, deltaY: Float) {
        yaw   -= deltaX * 0.01
        pitch -= deltaY * 0.01

        let limit: Float = (.pi / 2) - 0.01
        pitch = min(max(pitch, -limit), limit)
    }

    func zoom(delta: Float) {
        distance *= (1.0 - delta * 0.1)
        distance = min(max(distance, minDistance), maxDistance)
    }
}
