// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import MetalKit

final class MetalView: MTKView {

    var camera: OrbitCamera?

    private var lastMouseLocation: CGPoint = .zero

    override func scrollWheel(with event: NSEvent) {
        camera?.zoom(delta: Float(event.scrollingDeltaY))
    }

    override func mouseDown(with event: NSEvent) {
        lastMouseLocation = convert(event.locationInWindow, from: nil)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        let dx = Float(location.x - lastMouseLocation.x)
        let dy = Float(location.y - lastMouseLocation.y)

        camera?.rotate(deltaX: dx, deltaY: dy)
        lastMouseLocation = location
    }

    override var acceptsFirstResponder: Bool { true }
}
