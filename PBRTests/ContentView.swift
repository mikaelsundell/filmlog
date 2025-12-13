// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import MetalKit

struct MetalViewRepresentable: NSViewRepresentable {
    @Binding var controls: MetalShaderControls
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MetalView {
        let view = MetalView(frame: .zero)

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported")
        }

        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)

        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = false

        // Create & retain renderer
        let renderer = MetalRenderer(mtkView: view)
        context.coordinator.renderer = renderer
        view.delegate = renderer

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    func updateNSView(_ nsView: MetalView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        
        print("""
         Shader Controls Updated (SwiftUI):
            keyIntensity      = \(controls.keyIntensity)
            ambientIntensity  = \(controls.ambientIntensity)
            specularIntensity = \(controls.specularIntensity)
            roughnessBias     = \(controls.roughnessBias)
        """)
        
        renderer.shaderControls = controls
    }
    
    final class Coordinator {
        var renderer: MetalRenderer?
    }
}

struct ContentView: View {
    @State private var controls = MetalShaderControls()
    var body: some View {
        ZStack(alignment: .bottomLeading) {

            MetalViewRepresentable(controls: $controls)
                .ignoresSafeArea()

            VStack(alignment: .leading) {
                Slider(value: $controls.keyIntensity, in: 0...3) {
                    Text("Key")
                }
                Slider(value: $controls.ambientIntensity, in: 0...0.5) {
                    Text("Ambient")
                }
                Slider(value: $controls.specularIntensity, in: 0...2) {
                    Text("Specular")
                }
                Slider(value: $controls.roughnessBias, in: -0.5...0.5) {
                    Text("Roughness Bias")
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .padding()
        }
    }
}
#Preview {
    ContentView()
}
