// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import simd

struct MetalShaderControls {
    var keyIntensity: Float      = 2.8
    var ambientIntensity: Float  = 0.4
    var specularIntensity: Float = 1.8
    var roughnessBias: Float     = 0.4
    var topLightIntensity: Float = 0.5
}
