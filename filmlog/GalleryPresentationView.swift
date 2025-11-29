// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import UIKit

class FitAwareScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage
    @Binding var isControlsVisible: Bool

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = FitAwareScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.tag = 101
        scrollView.addSubview(imageView)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap))
        tap.numberOfTapsRequired = 1
        scrollView.addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        tap.require(toFail: doubleTap)
        scrollView.onLayout = { [weak scrollView] in
            guard let scrollView else { return }
            fitImage(scrollView: scrollView, context: context)
        }
        return scrollView
    }

    func fitImage(scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator

        if coordinator.hasInitialLayout {
            return
        }

        guard let imageView = coordinator.imageView else { return }
        guard let image = imageView.image else { return }

        let scrollSize = scrollView.bounds.size
        guard scrollSize.width > 0, scrollSize.height > 0 else { return }

        let scaleX = scrollSize.width / image.size.width
        let scaleY = scrollSize.height / image.size.height
        let fitScale = min(scaleX, scaleY)

        let newWidth = image.size.width * fitScale
        let newHeight = image.size.height * fitScale

        imageView.frame = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
        scrollView.contentSize = imageView.frame.size

        scrollView.minimumZoomScale = 1.0
        scrollView.zoomScale = 1.0

        coordinator.hasInitialLayout = true
        coordinator.centerImage()
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isControlsVisible: $isControlsVisible)
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var isControlsVisible: Bool
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?

        var hasInitialLayout: Bool = false

        init(isControlsVisible: Binding<Bool>) {
            _isControlsVisible = isControlsVisible
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage()
        }

        func centerImage() {
            guard let scrollView, let imageView else { return }

            let offsetX = max((scrollView.bounds.width - imageView.frame.width) * 0.5, 0)
            let offsetY = max((scrollView.bounds.height - imageView.frame.height) * 0.5, 0)

            scrollView.contentInset = UIEdgeInsets(
                top: offsetY,
                left: offsetX,
                bottom: offsetY,
                right: offsetX
            )
        }
        
        @objc func handleTap() {
            isControlsVisible.toggle()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }

            if abs(scrollView.zoomScale - 1.0) > 0.01 {
                scrollView.setZoomScale(1.0, animated: true)
                centerImage()
                return
            }

            let location = recognizer.location(in: imageView)
            zoom(to: location)
        }

        private func zoom(to point: CGPoint) {
            guard let scrollView else { return }

            let zoomScale: CGFloat = 2.5
            let size = scrollView.bounds.size

            let width = size.width / zoomScale
            let height = size.height / zoomScale

            let rect = CGRect(
                x: point.x - width / 2,
                y: point.y - height / 2,
                width: width,
                height: height
            )

            scrollView.zoom(to: rect, animated: true)
        }
    }
}

struct PagedImageViewer: UIViewControllerRepresentable {
    let images: [UIImage]
    @Binding var index: Int
    @Binding var isControlsVisible: Bool

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator

        let initialVC = context.coordinator.viewController(for: index)
        controller.setViewControllers([initialVC], direction: .forward, animated: false)

        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        let vc = context.coordinator.viewController(for: index)
        controller.setViewControllers([vc], direction: .forward, animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagedImageViewer
        private var cache: [Int: UIViewController] = [:]

        init(_ parent: PagedImageViewer) {
            self.parent = parent
        }

        func viewController(for index: Int) -> UIViewController {
            if let vc = cache[index] { return vc }

            let vc = UIHostingController(
                rootView:
                    ZoomableScrollView(
                        image: parent.images[index],
                        isControlsVisible: parent.$isControlsVisible
                    )
                    .ignoresSafeArea()
            )
            cache[index] = vc
            return vc
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard parent.images.count > 1 else { return nil }
            guard let index = index(of: viewController) else { return nil }
            let prev = (index - 1 + parent.images.count) % parent.images.count
            return self.viewController(for: prev)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard parent.images.count > 1 else { return nil }
            guard let index = index(of: viewController) else { return nil }
            let next = (index + 1) % parent.images.count
            return self.viewController(for: next)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            if completed,
               let visible = pageViewController.viewControllers?.first,
               let newIndex = index(of: visible) {
                parent.index = newIndex
            }
        }

        private func index(of vc: UIViewController) -> Int? {
            cache.first(where: { $0.value === vc })?.key
        }
    }
}

struct VisualEffectView: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct GalleryPresentationView: View {
    let images: [ImageData]
    @State private var currentIndex: Int
    var onClose: () -> Void

    @State private var isControlsVisible: Bool = true

    init(images: [ImageData], startIndex: Int, onClose: @escaping () -> Void) {
        self.images = images
        _currentIndex = State(initialValue: startIndex)
        self.onClose = onClose
    }

    private var uiImages: [UIImage] {
        images.compactMap { $0.original ?? $0.thumbnail }
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let screen = geometry.size
                let width = geometry.size.width
                let height = geometry.size.height
                let frameSize = CGSize(width: 200, height: 200)
                
                ZStack {
                    if !uiImages.isEmpty {
                        PagedImageViewer(
                            images: uiImages,
                            index: $currentIndex,
                            isControlsVisible: $isControlsVisible
                        )
                        .scaleEffect(0.75)
                        .rotationEffect(.degrees(90))
                        .frame(
                            width: screen.height,
                            height: screen.width
                        )
                        .position(
                            x: screen.width / 2,
                            y: screen.height / 2
                        )
                        .clipped()
                        .ignoresSafeArea()
                    }

                    if isControlsVisible {
                        controls
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    MaskView(
                        frameSize: displaySize,
                        aspectSize: aspectFrame,
                        radius: 8,
                        geometry: geometry
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 8)
                    )
                    
                }
                .overlay()
                {
                    if gridMode != .off
                        
                        GridView(
                            gridMode: gridMode,
                            size: aspectFrame,
                            geometry: geometry
                        )
                        .position(x: width / 2, y: height / 2)
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            
        }.statusBarHidden()
    }
    
    private func geometrySafeTopPadding() -> CGFloat {
        let topInset = UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0
        return topInset - 8
    }

    private var controls: some View {
        VStack {
            HStack {
                Spacer()

                Button(action: { onClose() }) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .frame(width: 38, height: 38)
                            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)

                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
                .frame(width: 42)

                Spacer()
            }
            .padding(.top, 42)
            .padding(.horizontal)

            Spacer()
        }
    }
}
