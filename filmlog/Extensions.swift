// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import ARKit
import AVFoundation
import Foundation
import SwiftUI
import UIKit

extension ARPlaneAnchor {
    var areaXZ: Float {
        if #available(iOS 16.0, *) {
            return planeExtent.width * planeExtent.height
        } else {
            return extent.x * extent.z
        }
    }
    var widthXZ: Float {
        if #available(iOS 16.0, *) {
            return planeExtent.width
        } else {
            return extent.x
        }
    }
    var depthXZ: Float {
        if #available(iOS 16.0, *) {
            return planeExtent.height
        } else {
            return extent.z
        }
    }
}

extension CGSize {
    func switchOrientation() -> CGSize {
        return CGSize(width: self.height, height: self.width)
    }

    var isLandscape: Bool {
        width >= height
    }

    var isPortrait: Bool {
        height > width
    }
    
    func toPortrait() -> CGSize {
        isLandscape ? switchOrientation() : self
    }

    func toLandscape() -> CGSize {
        isPortrait ? switchOrientation() : self
    }

    var aspectRatio: CGFloat {
        height == 0 ? 0 : width / height
    }
    
    var portraitRatio: CGFloat {
        let portraitSize = toPortrait()
        return portraitSize.height == 0 ? 0 : portraitSize.width / portraitSize.height
    }
    
    var landscapeRatio: CGFloat {
       let landscapeSize = toLandscape()
       return landscapeSize.height == 0 ? 0 : landscapeSize.width / landscapeSize.height
    }
    
    func exceeds(_ other: CGSize) -> Bool {
        width > other.width || height > other.height
    }

    func fits(in other: CGSize) -> Bool {
        width <= other.width && height <= other.height
    }
    
    func scaleToFit(in other: CGSize) -> CGFloat {
        let scaleW = other.width / width
        let scaleH = other.height / height
        return min(scaleW, scaleH)
    }
    
    func isApproximatelyEqual(to other: CGSize, tolerance: CGFloat = 0.5) -> Bool {
        abs(width - other.width) < tolerance && abs(height - other.height) < tolerance
    }

    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int(r * 255),
                      Int(g * 255),
                      Int(b * 255))
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

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

        self.init(SIMD4<Float>( x,  0,   0,   0),
                  SIMD4<Float>( 0,  y,   0,   0),
                  SIMD4<Float>( 0,  0,   z,  -1),
                  SIMD4<Float>( 0,  0,  z*nearZ, 0))
    }

    init(lookAt eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) {
        let f = normalize(target - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)

        self.init(SIMD4<Float>( s.x,  u.x, -f.x, 0),
                  SIMD4<Float>( s.y,  u.y, -f.y, 0),
                  SIMD4<Float>( s.z,  u.z, -f.z, 0),
                  SIMD4<Float>(-dot(s, eye), -dot(u, eye), dot(f, eye), 1))
    }
    
    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        self.columns.3 = SIMD4(t.x, t.y, t.z, 1)
    }
    
    init(scale: Float) {
        self = matrix_identity_float4x4
        self.columns.0.x = scale
        self.columns.1.y = scale
        self.columns.2.z = scale
    }
    
    static func rotationX(_ angle: Float) -> float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return float4x4(
            SIMD4(1, 0, 0, 0),
            SIMD4(0,  c,  s, 0),
            SIMD4(0, -s,  c, 0),
            SIMD4(0, 0, 0, 1)
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

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

extension simd_float4x4 {
    var position: SIMD3<Float> {
        SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }

    var forward: SIMD3<Float> {
        -SIMD3(columns.2.x, columns.2.y, columns.2.z)
    }
}

extension UIDeviceOrientation {
    var toLandscape: Angle {
        switch self {
        case .landscapeLeft: return .degrees(90)
        case .landscapeRight: return .degrees(-90)
        case .portraitUpsideDown: return .degrees(180)
        default: return .degrees(0)
        }
    }
    var isLandscape: Bool {
        self == .landscapeLeft || self == .landscapeRight
    }
}

extension UIImage {
    var asLandscape: UIImage? {
        guard let cg = self.cgImage else { return nil }
        return UIImage(cgImage: cg, scale: 1.0, orientation: .up)
    }
    var aspectRatio: CGFloat {
        size.width / size.height
    }
    func resize(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    static func solidColor(_ color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
}
