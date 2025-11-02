// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import SwiftUI
import UIKit
import AVFoundation

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

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
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
