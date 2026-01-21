// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

enum LUTType: String, CaseIterable {
    case kodakNeutral = "Kodak neutral"
    case kodakWarm    = "Kodak warm"
    case fujiNeutral  = "Fuji neutral"
    case fujiWarm     = "Fuji warm"
    case bwNeutral    = "BW neutral"
    case bwContrast   = "BW contrast"
    case lookExposure = "Print exposure"
    case exposure     = "Exposure"
    
    var filename: String {
        switch self {
        case .kodakNeutral: return "LutKodakNeutral"
        case .kodakWarm:    return "LutKodakWarm"
        case .fujiNeutral:  return "LutFujiNeutral"
        case .fujiWarm:     return "LutFujiWarm"
        case .bwNeutral:    return "LutBWNeutral"
        case .bwContrast:   return "LutBWContrast"
        case .lookExposure: return "LutLookExposure"
        case .exposure:     return "LutExposure"
        }
    }
}
