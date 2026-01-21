// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Metal

struct RenderContext {
    var device: MTLDevice
    var commandQueue: MTLCommandQueue
    var colorPixelFormat: MTLPixelFormat
    var depthPixelFormat: MTLPixelFormat
    var sampleCount: Int
}
