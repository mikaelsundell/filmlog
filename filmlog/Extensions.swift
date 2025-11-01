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
