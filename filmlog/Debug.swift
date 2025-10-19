// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import UIKit
import UniformTypeIdentifiers
import ImageIO


func captureScreenshot() {
    guard let window = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first?.windows
        .first(where: \.isKeyWindow) else {
            print("unable to find key window for screenshot")
            return
        }
    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
    let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    print("saved image to photos")
}

func captureToBundle(_ cgImage: CGImage, name: String = "debug.png") {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL,
                                                     UTType.png.identifier as CFString,
                                                     1,
                                                     nil) else {
        print("failed to create image in bundle")
        return
    }

    CGImageDestinationAddImage(dest, cgImage, nil)
    if CGImageDestinationFinalize(dest) {
        print("saved image to \(url)")
    } else {
        print("failed to save image")
    }
}

func captureToPhotos(_ image: UIImage, name: String = "debug") {
    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    print("saved debug image to photos: \(name)")
}

func dumpImage(_ image: UIImage, name: String = "image") {
    print("image info: \(name)")
    print("size: \(image.size.width)x\(image.size.height)")
    print("scale: \(image.scale)")
    print("orientation: \(image.imageOrientation.rawValue) (\(image.imageOrientation))")
    
    if let cg = image.cgImage {
        print("width: \(cg.width), height: \(cg.height)")
        print("bitsPerComponent: \(cg.bitsPerComponent)")
        print("bitsPerPixel: \(cg.bitsPerPixel)")
        print("bytesPerRow: \(cg.bytesPerRow)")
        print("bitmapInfo: \(cg.bitmapInfo)")
        
        if let cs = cg.colorSpace {
            print("colorSpace: \(cs)")
            print("name: \(cs.name as String? ?? "Unknown")")
            print("model: \(cs.model.rawValue)") // 1 = RGB
        } else {
            print("colorSpace: nil")
        }
    } else {
        print("no CGImage backing this UIImage")
    }
}
