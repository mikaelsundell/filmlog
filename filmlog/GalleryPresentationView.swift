// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI

struct GalleryPresentationView: View {
    let images: [ImageData]
    @State private var currentIndex: Int
    var onClose: () -> Void
    
    @State private var showControls = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    init(images: [ImageData], startIndex: Int, onClose: @escaping () -> Void) {
        self.images = images
        _currentIndex = State(initialValue: startIndex)
        self.onClose = onClose
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let uiImage = images[safe: currentIndex]?.original ?? images[safe: currentIndex]?.thumbnail {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .animation(.easeInOut(duration: 0.2), value: scale)
                    .animation(.easeInOut(duration: 0.2), value: offset)
                    .gesture(dragGesture)
                    .gesture(magnificationGesture)
                    .gesture(doubleTapGesture)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showControls.toggle()
                        }
                    }
                    .transition(.opacity)
            } else {
                Color.gray
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            if showControls {
                VStack(spacing: 0) {
                    HStack {
                        HStack {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    resetView()
                                    onClose()
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 24, weight: .regular))
                                    .frame(width: 46, height: 46)
                            }
                            .padding(.leading, -6)
                            .buttonStyle(.borderless)
                        }
                        .frame(width: 80, alignment: .leading)
                        
                        Text(currentTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    previous()
                                }
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 24, weight: .regular))
                            }
                            .buttonStyle(.borderless)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    next()
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 24, weight: .regular))
                            }
                            .buttonStyle(.borderless)
                        }
                        .frame(width: 80, alignment: .trailing)
                        .padding(.trailing, 16)
                    }
                    .background(Color.black.opacity(0.85))
                    .shadow(radius: 2)
                    
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    guard abs(value.translation.width) > 60 else { return }
                    if value.translation.width > 0 {
                        withAnimation(.easeInOut(duration: 0.25)) { previous() }
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) { next() }
                    }
                }
        )
    }
    
    private var currentTitle: String {
        let img = images[safe: currentIndex]
        return img?.name ?? "Untitled"
    }
    
    private func next() {
        resetView()
        currentIndex = (currentIndex + 1) % images.count
    }
    
    private func previous() {
        resetView()
        currentIndex = (currentIndex - 1 + images.count) % images.count
    }
    
    private func resetView() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                let newScale = scale * delta
                scale = min(max(newScale, 1.0), 4.0)
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale < 1.05 {
                    resetView()
                }
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard scale > 1 else { return }
                lastOffset = offset
            }
    }
    
    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if abs(scale - 1.0) < 0.1 {
                        scale = 2.5
                    } else {
                        resetView()
                    }
                }
            }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
