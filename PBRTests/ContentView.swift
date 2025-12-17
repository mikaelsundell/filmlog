// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import MetalKit

extension Notification.Name {
    static let loadMetalModel = Notification.Name("LoadMetalModel")
}

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
        view.clearColor = MTLClearColor(
            red: 0.1,
            green: 0.1,
            blue: 0.1,
            alpha: 1.0
        )

        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = false

        let renderer = MetalRenderer(mtkView: view)
        context.coordinator.renderer = renderer
        view.delegate = renderer

        NotificationCenter.default.addObserver(
            forName: .loadMetalModel,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let modelName = notification.object as? String,
                let renderer = context.coordinator.renderer
            else { return }

            renderer.loadModel(named: modelName)
        }

        return view
    }

    func updateNSView(_ nsView: MetalView, context: Context) {
        context.coordinator.renderer?.shaderControls = controls
    }
    
    final class Coordinator {
        var renderer: MetalRenderer?
    }
}

struct ContentView: View {
    @State private var controls = MetalShaderControls()

    var body: some View {
        VStack(spacing: 0) {
            MetalViewRepresentable(controls: $controls)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 12) {

                HStack(spacing: 8) {
                    modelButton("Elf",   model: "elf")
                    modelButton("Fox",   model: "fox")
                    modelButton("Shark", model: "shark")
                    modelButton("Sonic", model: "sonic")
                }

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

                Slider(value: $controls.topLightIntensity, in: 0.0...1.0) {
                    Text("Top Light")
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    private func modelButton(_ title: String, model: String) -> some View {
        Button(title) {
            NotificationCenter.default.post(
                name: .loadMetalModel,
                object: model
            )
        }
        .buttonStyle(.borderedProminent)
    }
}

#Preview {
    ContentView()
}
