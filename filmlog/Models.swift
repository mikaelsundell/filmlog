// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct LocationUtils {
    struct Location: Codable {
        var latitude: Double
        var longitude: Double
        var altitude: Double?
        
        func elevation(for date: Date = Date(), timeZone: TimeZone = .current) -> Double {
            func deg2rad(_ deg: Double) -> Double { deg * .pi / 180 }
            func rad2deg(_ rad: Double) -> Double { rad * 180 / .pi }

            let calendar = Calendar.current
            let n = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
            let latRad = deg2rad(latitude)

            // declination δ = 23.44° * sin(360° * (284 + n)/365)
            let decl = deg2rad(23.44) * sin(deg2rad((360.0 * (284 + n)) / 365.0))

            // time components
            let components = calendar.dateComponents([.hour, .minute], from: date)
            let hours = Double(components.hour ?? 0)
            let minutes = Double(components.minute ?? 0)
            let clockTimeMinutes = hours * 60 + minutes

            // equation of Time (EoT) in minutes
            let B = deg2rad((360.0 / 365.0) * (n - 81))
            let EoT = 9.87 * sin(2 * B) - 7.53 * cos(B) - 1.5 * sin(B)

            // local Standard Time Meridian (LSTM)
            let timeZoneOffset = Double(timeZone.secondsFromGMT()) / 3600.0
            let LSTM = 15.0 * timeZoneOffset

            // time Correction (TC) in minutes
            let TC = 4.0 * (longitude - LSTM) + EoT

            // Llcal Solar Time (in minutes)
            let LST = clockTimeMinutes + TC

            // hour angle H = 15° * (LST/60 - 12)
            let H = deg2rad(15.0 * ((LST / 60.0) - 12.0))

            // solar elevation
            let elevationRad = asin(sin(latRad) * sin(decl) + cos(latRad) * cos(decl) * cos(H))
            return rad2deg(elevationRad)
        }
        
        func colorTemperature(for date: Date = Date(), timeZone: TimeZone = .current) -> Int {
            let elevationAngle = elevation(for: date, timeZone: timeZone)
            let clampedElevation = max(elevationAngle, 0.0)
            let cctDouble = 2000.0 + (4500.0 * (1.0 - exp(-0.045 * clampedElevation)))
            return Int(round(cctDouble))
        }
    }
}

struct CameraUtils {
    struct Aperture: Equatable {
        let name: String
        let fstop: Double
        let isNone: Bool
        
        init(name: String, fstop: Double, isNone: Bool = false) {
            self.name = name
            self.fstop = fstop
            self.isNone = isNone
        }
        
        static let none = Aperture(name: "-", fstop: 0.0, isNone: true)
    }

    static let apertures: [Aperture] = [
        Aperture(name: "f/1.4", fstop: 1.4),
        Aperture(name: "f/2", fstop: 2.0),
        Aperture(name: "f/2.8", fstop: 2.8),
        Aperture(name: "f/4", fstop: 4.0),
        Aperture(name: "f/5.6", fstop: 5.6),
        Aperture(name: "f/8", fstop: 8.0),
        Aperture(name: "f/11", fstop: 11.0),
        Aperture(name: "f/16", fstop: 16.0),
        Aperture(name: "f/22", fstop: 22.0)
    ]

    static func aperture(for label: String) -> Aperture {
        apertures.first(where: { $0.name == label }) ?? .none
    }
    
    struct AspectRatio: Equatable {
        let name: String
        let numerator: Int
        let denominator: Int
        let isNone: Bool

        init(name: String, numerator: Int, denominator: Int, isNone: Bool = false) {
             self.name = name
             self.numerator = numerator
             self.denominator = denominator
             self.isNone = isNone
         }
        
        var ratio: Double {
            denominator == 0 ? 0.0 : Double(numerator) / Double(denominator)
        }

        static let none = AspectRatio(name: "-", numerator: 0, denominator: 0, isNone: true)
    }
    
    static let aspectRatios: [AspectRatio] = [
        .none,
        AspectRatio(name: "1:1", numerator: 1, denominator: 1),
        AspectRatio(name: "5:4", numerator: 5, denominator: 4),
        AspectRatio(name: "4:3", numerator: 4, denominator: 3),
        AspectRatio(name: "3:2", numerator: 3, denominator: 2),
        AspectRatio(name: "16:10", numerator: 16, denominator: 10),
        AspectRatio(name: "16:9", numerator: 16, denominator: 9),
        AspectRatio(name: "1.43", numerator: 143, denominator: 100),
        AspectRatio(name: "1.66", numerator: 166, denominator: 100),
        AspectRatio(name: "1.85", numerator: 185, denominator: 100),
        AspectRatio(name: "1.90", numerator: 190, denominator: 100),
        AspectRatio(name: "2.00", numerator: 200, denominator: 100),
        AspectRatio(name: "2.20", numerator: 220, denominator: 100),
        AspectRatio(name: "2.35", numerator: 235, denominator: 100),
        AspectRatio(name: "2.39", numerator: 239, denominator: 100),
        AspectRatio(name: "2.55", numerator: 255, denominator: 100)
    ]

    static func aspectRatio(for label: String) -> AspectRatio {
        aspectRatios.first(where: { $0.name == label }) ?? .none
    }
    
    struct Camera: Equatable {
        let name: String
        let category: String
        let isNone: Bool

        init(name: String, category: String, isNone: Bool = false) {
            self.name = name
            self.category = category
            self.isNone = isNone
        }

        static let none = Camera(name: "-", category: "", isNone: true)
    }

    static let cameras: [Camera] = [
        .none,
        Camera(name: "Canon AE-1", category: "Photo"),
        Camera(name: "Canon A-1", category: "Photo"),
        Camera(name: "Canon F-1", category: "Photo"),
        Camera(name: "Nikon FM2", category: "Photo"),
        Camera(name: "Nikon FE2", category: "Photo"),
        Camera(name: "Nikon F3", category: "Photo"),
        Camera(name: "Olympus OM-1", category: "35mm Still"),
        Camera(name: "Olympus OM-2", category: "35mm Still"),
        Camera(name: "Pentax K1000", category: "35mm Still"),
        Camera(name: "Minolta X-700", category: "35mm Still"),
        Camera(name: "Leica M3", category: "35mm Still"),
        Camera(name: "Leica M6", category: "35mm Still"),
        Camera(name: "Contax T2", category: "35mm Still"),
        Camera(name: "Hasselblad 500C/M", category: "Medium Format"),
        Camera(name: "Mamiya RB67", category: "Medium Format"),
        Camera(name: "Yashica Mat-124G", category: "Medium Format"),
        Camera(name: "ARRIFLEX 435", category: "Motion Picture (Film)"),
        Camera(name: "ARRIFLEX 235", category: "Motion Picture (Film)"),
        Camera(name: "ARRIFLEX 16SR3", category: "Motion Picture (Film)"),
        Camera(name: "Panavision Panaflex Millennium XL2", category: "Motion Picture (Film)"),
        Camera(name: "Aaton XTR Prod", category: "Motion Picture (Film)"),
        Camera(name: "Bolex H16", category: "Motion Picture (Film)"),
        Camera(name: "ARRI Alexa Mini", category: "Digital Cinema"),
        Camera(name: "ARRI Alexa LF", category: "Digital Cinema"),
        Camera(name: "ARRI Alexa 35", category: "Digital Cinema"),
        Camera(name: "RED Komodo 6K", category: "Digital Cinema"),
        Camera(name: "RED Raptor 8K VV", category: "Digital Cinema"),
        Camera(name: "RED Helium 8K S35", category: "Digital Cinema"),
        Camera(name: "Sony Venice 2", category: "Digital Cinema"),
        Camera(name: "Sony FX9", category: "Digital Cinema"),
        Camera(name: "Sony FX6", category: "Digital Cinema"),
        Camera(name: "Blackmagic URSA Mini Pro 12K", category: "Digital Cinema"),
        Camera(name: "Blackmagic Pocket Cinema Camera 6K", category: "Digital Cinema"),
        Camera(name: "Canon C300 Mark III", category: "Digital Cinema"),
        Camera(name: "Canon C500 Mark II", category: "Digital Cinema"),
        Camera(name: "Other", category: "Other")
    ]

    static func camera(for label: String) -> Camera {
        cameras.first(where: { $0.name == label }) ?? .none
    }
    
    static var groupedCameras: [String: [Camera]] {
        Dictionary(grouping: cameras, by: { $0.category })
    }
    
    struct Filter: Equatable {
        let name: String
        let exposureCompensation: Double
        let colorTemperatureShift: Double
        let isNone: Bool
        
        init(name: String, exposureCompensation: Double, colorTemperatureShift: Double, isNone: Bool = false) {
            self.name = name
            self.exposureCompensation = exposureCompensation
            self.colorTemperatureShift = colorTemperatureShift
            self.isNone = isNone
        }
        
        static let none = Filter(name: "-", exposureCompensation: 0.0, colorTemperatureShift: 0.0, isNone: true)
    }
    
    static let colorFilters: [Filter] = [
        .none,
        Filter(name: "85",  exposureCompensation: -0.6, colorTemperatureShift: -2100),
        Filter(name: "85B", exposureCompensation: -0.6, colorTemperatureShift: -2300),
        Filter(name: "85C", exposureCompensation: -0.3, colorTemperatureShift: -1700),
        Filter(name: "80A", exposureCompensation: -1.0, colorTemperatureShift: +2300),
        Filter(name: "80B", exposureCompensation: -1.0, colorTemperatureShift: +1900),
        Filter(name: "80C", exposureCompensation: -0.6, colorTemperatureShift: +1200),
        Filter(name: "81A", exposureCompensation: -0.3, colorTemperatureShift: -300),
        Filter(name: "81B", exposureCompensation: -0.3, colorTemperatureShift: -450),
        Filter(name: "81C", exposureCompensation: -0.3, colorTemperatureShift: -600),
        Filter(name: "82A", exposureCompensation: -0.3, colorTemperatureShift: +200),
        Filter(name: "82B", exposureCompensation: -0.3, colorTemperatureShift: +400),
        Filter(name: "82C", exposureCompensation: -0.3, colorTemperatureShift: +600)
    ]

    static func colorFilter(for label: String) -> Filter {
        colorFilters.first(where: { $0.name == label }) ?? .none
    }
    
    static let ndFilters: [Filter] = [
        .none,
        Filter(name: "0.3", exposureCompensation: -1.0, colorTemperatureShift: 0.0),
        Filter(name: "0.6", exposureCompensation: -2.0, colorTemperatureShift: 0.0),
        Filter(name: "0.9", exposureCompensation: -3.0, colorTemperatureShift: 0.0),
        Filter(name: "1.2", exposureCompensation: -4.0, colorTemperatureShift: 0.0),
        Filter(name: "2.1", exposureCompensation: -6.0, colorTemperatureShift: 0.0)
    ]

    static func ndFilter(for label: String) -> Filter {
        ndFilters.first(where: { $0.name == label }) ?? .none
    }

    struct FocalLength: Equatable {
        let name: String
        let length: Double
        let isNone: Bool
        
        init(name: String, length: Double, isNone: Bool = false) {
            self.name = name
            self.length = length
            self.isNone = isNone
        }
        
        static let none = FocalLength(name: "-", length:  Double.random(in: 50...60), isNone: true)
    }
    
    static let focalLengths: [FocalLength] = [
        FocalLength(name: "12mm", length: 12),
        FocalLength(name: "14mm", length: 14),
        FocalLength(name: "16mm", length: 16),
        FocalLength(name: "18mm", length: 18),
        FocalLength(name: "19mm", length: 19),
        FocalLength(name: "20mm", length: 20),
        FocalLength(name: "21mm", length: 21),
        FocalLength(name: "24mm", length: 24),
        FocalLength(name: "25mm", length: 25),
        FocalLength(name: "27mm", length: 27),
        FocalLength(name: "28mm", length: 28),
        FocalLength(name: "32mm", length: 32),
        FocalLength(name: "35mm", length: 35),
        FocalLength(name: "40mm", length: 40),
        FocalLength(name: "50mm", length: 50),
        FocalLength(name: "60mm", length: 60),
        FocalLength(name: "65mm", length: 65),
        FocalLength(name: "70mm", length: 70),
        FocalLength(name: "75mm", length: 75),
        FocalLength(name: "80mm", length: 80),
        FocalLength(name: "85mm", length: 85),
        FocalLength(name: "105mm", length: 105),
        FocalLength(name: "135mm", length: 135),
        FocalLength(name: "150mm", length: 150),
        FocalLength(name: "200mm", length: 200),
        FocalLength(name: "300mm", length: 300)
    ]

    static func focalLength(for label: String) -> FocalLength {
        focalLengths.first(where: { $0.name == label }) ?? .none
    }
    
    struct FilmSize {
        let name: String
        let category: String
        let width: Double
        let height: Double
        let isNone: Bool
        
        init(name: String, category: String, width: Double, height: Double, isNone: Bool = false) {
            self.name = name
            self.category = category
            self.width = width
            self.height = height
            self.isNone = isNone
        }
        
        func angleOfView(focalLength: Double) -> (horizontal: Double, vertical: Double, diagonal: Double) {
            let horizontal = 2 * atan(width / (2 * focalLength)) * (180.0 / .pi)
            let vertical = 2 * atan(height / (2 * focalLength)) * (180.0 / .pi)
            let diagonal = 2 * atan(self.diagonal / (2 * focalLength)) * (180.0 / .pi)
            return (horizontal, vertical, diagonal)
        }
        
        var aspectRatio: Double {
            width / height
        }
        
        var diagonal: Double {
            sqrt(width * width + height * height)
        }
        
        var circleOfConfusion: Double {
            diagonal / Self.defaultCocFactor
        }
        
        func focusDepthOfField(
            focalLength: Double,
            aperture: Double,
            focusDistance: Double
        ) -> (near: Double, far: Double, hyperfocal: Double, hyperfocalNear: Double, dof: Double) {
            
            let f = focalLength
            let N = aperture
            let D = focusDistance

            let H = (f * f) / (N * circleOfConfusion) + f
            let near = (H * D) / (H + (D - f))

            let far: Double
            if H > (D - f) {
                far = (H * D) / (H - (D - f))
            } else {
                far = Double.infinity
            }
            let dof = far.isInfinite ? Double.infinity : max(0, far - near)
            
            let hyperfocalNear = H / 2

            return (near, far, H, hyperfocalNear, dof)
        }
        
        static let defaultInfinity: Double = 1000000
        static let defaultCocFactor: Double = 1442
        
        static let none = FilmSize(name: "-", category: "-", width: 0.0, height: 0.0, isNone: true)
    }
    
    static let filmSizes: [FilmSize] = [
        FilmSize(name: "135 (35mm)", category: "Photo 35mm", width: 36.0, height: 24.0),
        FilmSize(name: "120 (6x6)", category: "Photo Medium Format", width: 60.0, height: 60.0),
        FilmSize(name: "120 (6x7)", category: "Photo Medium Format", width: 70.0, height: 60.0),
        FilmSize(name: "120 (6x9)", category: "Photo Medium Format", width: 90.0, height: 60.0),
        FilmSize(name: "4x5 (Large Format)", category: "Photo Large Format", width: 127.0, height: 101.6),
        FilmSize(name: "35mm Academy (4-perf)", category: "Motion Picture Film", width: 21.95, height: 16.00),
        FilmSize(name: "35mm Full Aperture (Silent)", category: "Motion Picture Film", width: 24.89, height: 18.66),
        FilmSize(name: "Super 35 (4-perf)", category: "Motion Picture Film", width: 24.89, height: 18.66),
        FilmSize(name: "Super 35 (3-perf)", category: "Motion Picture Film", width: 24.89, height: 13.87),
        FilmSize(name: "Techniscope (2-perf)", category: "Motion Picture Film", width: 22.00, height: 9.47),
        FilmSize(name: "65mm / 70mm (5-perf)", category: "Motion Picture Film", width: 48.56, height: 22.10),
        FilmSize(name: "IMAX 70mm (15-perf)", category: "Motion Picture Film", width: 70.41, height: 52.63),
        FilmSize(name: "ARRI Alexa Mini / Classic (Open Gate)", category: "Motion Picture Digital", width: 28.17, height: 18.13),
        FilmSize(name: "ARRI Alexa Mini / Classic (16:9)", category: "Motion Picture Digital", width: 23.76, height: 13.37),
        FilmSize(name: "ARRI Alexa Mini / Classic (4:3)", category: "Motion Picture Digital", width: 23.76, height: 17.82),
        FilmSize(name: "ARRI Alexa LF (Open Gate)", category: "Motion Picture Digital", width: 36.70, height: 25.54),
        FilmSize(name: "ARRI Alexa LF (16:9)", category: "Motion Picture Digital", width: 31.68, height: 17.82),
        FilmSize(name: "ARRI Alexa 65 (Open Gate)", category: "Motion Picture Digital", width: 54.12, height: 25.58),
        FilmSize(name: "RED Komodo 6K (S35)", category: "Motion Picture Digital", width: 27.03, height: 14.26),
        FilmSize(name: "RED Raptor 8K VV (Full Frame)", category: "Motion Picture Digital", width: 40.96, height: 21.60),
        FilmSize(name: "RED V-Raptor XL 8K VV", category: "Motion Picture Digital", width: 40.96, height: 21.60),
        FilmSize(name: "RED Monstro 8K VV", category: "Motion Picture Digital", width: 40.96, height: 21.60),
        FilmSize(name: "RED Helium 8K S35", category: "Motion Picture Digital", width: 29.90, height: 15.77),
        FilmSize(name: "RED Gemini 5K S35", category: "Motion Picture Digital", width: 30.72, height: 18.00),
        FilmSize(name: "Sony Venice 2 8.6K (Full Frame)", category: "Motion Picture Digital", width: 36.2, height: 24.1),
        FilmSize(name: "Sony Venice (6K S35)", category: "Motion Picture Digital", width: 24.3, height: 12.9),
        FilmSize(name: "Sony FX9 (Full Frame)", category: "Motion Picture Digital", width: 35.7, height: 18.8),
        FilmSize(name: "Sony FX6 (Full Frame)", category: "Motion Picture Digital", width: 35.6, height: 18.8),
        FilmSize(name: "Sony FS7 (S35)", category: "Motion Picture Digital", width: 24.0, height: 13.5),
        FilmSize(name: "BMPCC 4K (MFT)", category: "Motion Picture Digital", width: 18.96, height: 10.00),
        FilmSize(name: "BMPCC 6K (S35)", category: "Motion Picture Digital", width: 23.10, height: 12.99),
        FilmSize(name: "BMPCC 6K Pro (S35)", category: "Motion Picture Digital", width: 23.10, height: 12.99),
        FilmSize(name: "URSA Mini 4.6K (S35)", category: "Motion Picture Digital", width: 25.34, height: 14.25),
        FilmSize(name: "URSA Mini Pro 12K (S35)", category: "Motion Picture Digital", width: 27.03, height: 14.25),
        FilmSize(name: "Cinema Camera 6K (Full Frame)", category: "Motion Picture Digital", width: 36.00, height: 24.00)
    ]

    static func filmSize(for label: String) -> FilmSize {
        filmSizes.first(where: { $0.name == label }) ?? .none
    }
    
    static var groupedFilmSizes: [String: [FilmSize]] {
        Dictionary(grouping: filmSizes, by: { $0.category })
    }
    
    struct FilmStock: Equatable {
        let name: String
        let category: String
        let speed: Double
        let colorTemperature: Double
        let isNone: Bool
        
        init(name: String, category: String, speed: Double, colorTemperature: Double, isNone: Bool = false) {
            self.name = name
            self.category = category
            self.speed = speed
            self.colorTemperature = colorTemperature
            self.isNone = isNone
        }
        
        static let none = FilmStock(name: "-", category: "-", speed: 0, colorTemperature: 0, isNone: true)
    }
    
    static let filmStocks: [FilmStock] = [
        FilmStock(name: "50", category: "Generic ISO", speed: 50, colorTemperature: 5600),
        FilmStock(name: "100", category: "Generic ISO", speed: 100, colorTemperature: 5600),
        FilmStock(name: "200", category: "Generic ISO", speed: 200, colorTemperature: 5600),
        FilmStock(name: "400", category: "Generic ISO", speed: 400, colorTemperature: 5600),
        FilmStock(name: "800", category: "Generic ISO", speed: 800, colorTemperature: 5600),
        FilmStock(name: "1600", category: "Generic ISO", speed: 1600, colorTemperature: 5600),
        FilmStock(name: "3200", category: "Generic ISO", speed: 3200, colorTemperature: 5600),
        FilmStock(name: "50D 5203", category: "Kodak", speed: 50, colorTemperature: 5600),
        FilmStock(name: "250D 5207", category: "Kodak", speed: 250, colorTemperature: 5600),
        FilmStock(name: "200T 5213", category: "Kodak", speed: 200, colorTemperature: 3200),
        FilmStock(name: "500T 5219", category: "Kodak", speed: 500, colorTemperature: 3200),
        FilmStock(name: "Ektachrome", category: "Kodak", speed: 100, colorTemperature: 5600),
        FilmStock(name: "Double X 5222", category: "Kodak", speed: 250, colorTemperature: 5600),

    ]
    
    static var groupedFilmStocks: [String: [FilmStock]] {
        Dictionary(grouping: filmStocks, by: { $0.category })
    }

    static func filmStock(for label: String) -> FilmStock {
        filmStocks.first(where: { $0.name == label }) ?? .none
    }

    struct Lens: Equatable {
        let name: String
        let category: String
        let isNone: Bool
        
        init(name: String, category: String, isNone: Bool = false) {
            self.name = name
            self.category = category
            self.isNone = isNone
        }
        
        static let none = Lens(name: "-", category: "-", isNone: true)
    }
    
    static let lenses: [Lens] = [
        .none,
        Lens(name: "Arri Signature Prime", category: "Cinema"),
        Lens(name: "Cooke S4/i", category: "Cinema"),
        Lens(name: "Cooke Panchro/i Classic", category: "Cinema"),
        Lens(name: "Zeiss Supreme Prime", category: "Cinema"),
        Lens(name: "Zeiss CP.3", category: "Cinema"),
        Lens(name: "Canon CN-E Prime", category: "Cinema"),
        Lens(name: "Sigma Cine Prime", category: "Cinema"),
        Lens(name: "Leica Summicron-C", category: "Cinema"),
        Lens(name: "Leica Summilux-C", category: "Cinema"),
        Lens(name: "Fujinon MK", category: "Cinema"),
        Lens(name: "Tokina Vista Prime", category: "Cinema"),
        Lens(name: "Canon EF", category: "Photo"),
        Lens(name: "Canon RF", category: "Photo"),
        Lens(name: "Nikon F", category: "Photo"),
        Lens(name: "Nikon Z", category: "Photo"),
        Lens(name: "Sony E", category: "Photo"),
        Lens(name: "Leica M", category: "Photo"),
        Lens(name: "Leica SL", category: "Photo"),
        Lens(name: "Sigma Art", category: "Photo"),
        Lens(name: "Tamron SP", category: "Photo"),
        Lens(name: "Fujifilm XF", category: "Photo"),
        Lens(name: "Panasonic Lumix", category: "Photo"),
        Lens(name: "Canon FD", category: "Vintage"),
        Lens(name: "Canon FL", category: "Vintage"),
        Lens(name: "Nikon AI-S", category: "Vintage"),
        Lens(name: "Minolta Rokkor", category: "Vintage"),
        Lens(name: "Zeiss Contax", category: "Vintage"),
        Lens(name: "Leica R", category: "Vintage"),
        Lens(name: "Pentax Takumar", category: "Vintage"),
        Lens(name: "Olympus OM", category: "Vintage"),
        Lens(name: "Helios 44", category: "Vintage"),
        Lens(name: "Mamiya Sekor", category: "Vintage"),
        Lens(name: "Vivitar Series 1", category: "Vintage"),
        Lens(name: "Laowa", category: "Other"),
        Lens(name: "TTArtisan", category: "Other"),
        Lens(name: "7Artisans", category: "Other"),
        Lens(name: "Voigtländer", category: "Other"),
        Lens(name: "Samyang / Rokinon", category: "Other"),
        Lens(name: "Other", category: "Other")
    ]
    
    static func lens(for label: String) -> Lens {
        lenses.first(where: { $0.name == label }) ?? .none
    }
    
    static var groupedLenses: [String: [Lens]] {
        Dictionary(grouping: lenses, by: { $0.category })
    }
    
    struct Shutter: Equatable {
        let name: String
        let numerator: Int
        let denominator: Int
        let isNone: Bool
        
        init(name: String, numerator: Int, denominator: Int, isNone: Bool = false) {
            self.name = name
            self.numerator = numerator
            self.denominator = denominator
            self.isNone = isNone
        }
        
        var shutter: Double {
            return Double(numerator) / Double(denominator)
        }
        
        static let none = Shutter(name: "-", numerator: 0, denominator: 0, isNone: true)
    }

    static let shutters: [Shutter] = [
        Shutter(name: "24 fps", numerator: 1, denominator: 48),
        Shutter(name: "25 fps", numerator: 1, denominator: 50),
        Shutter(name: "30 fps", numerator: 1, denominator: 60),
        Shutter(name: "50 fps", numerator: 1, denominator: 100),
        Shutter(name: "60 fps", numerator: 1, denominator: 120),
        Shutter(name: "1/2", numerator: 1, denominator: 2),
        Shutter(name: "1/4", numerator: 1, denominator: 4),
        Shutter(name: "1/8", numerator: 1, denominator: 8),
        Shutter(name: "1/15", numerator: 1, denominator: 15),
        Shutter(name: "1/30", numerator: 1, denominator: 30),
        Shutter(name: "1/50", numerator: 1, denominator: 50),
        Shutter(name: "1/60", numerator: 1, denominator: 60),
        Shutter(name: "1/100", numerator: 1, denominator: 100),
        Shutter(name: "1/125", numerator: 1, denominator: 125),
        Shutter(name: "1/250", numerator: 1, denominator: 250),
        Shutter(name: "1/500", numerator: 1, denominator: 500),
        Shutter(name: "1/1000", numerator: 1, denominator: 1000),
        Shutter(name: "1/2000", numerator: 1, denominator: 2000),
        Shutter(name: "1/4000", numerator: 1, denominator: 4000),
        Shutter(name: "1", numerator: 1, denominator: 1),
        Shutter(name: "2", numerator: 2, denominator: 1),
        Shutter(name: "4", numerator: 4, denominator: 1)
    ]

    static func shutter(for label: String) -> Shutter {
        shutters.first(where: { $0.name == label }) ?? .none
    }
}

struct OrientationUtils {
    struct Level: Equatable {
        var roll: Double
        var tilt: Double
    }
    
    static func normalizeLevel(from level: Level) -> Level {
        let normalizedRoll = (level.roll / 2).rounded() * 2
        let normalizedTilt = level.tilt.clamped(to: -90...90)
        return Level(roll: normalizedRoll, tilt: normalizedTilt)
    }
}

struct ImageUtils {
    enum FileType: String, CaseIterable {
        case original
        case thumbnail
        
        var maxDimension: CGFloat {
            switch self {
            case .original:
                return 2048
            case .thumbnail:
                return 1024
            }
        }

        var compressionQuality: CGFloat {
            switch self {
            case .original:
                return 0.8
            case .thumbnail:
                return 0.6
            }
        }
    }

    struct FileStorage {
        static let shared = FileStorage()
        private init() {}

        private let folderURL: URL = {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let folder = docs.appendingPathComponent("data")
            if !FileManager.default.fileExists(atPath: folder.path) {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
            }
            return folder
        }()

        private func fileURL(for id: UUID, type: FileType) -> URL {
            return folderURL.appendingPathComponent("\(id.uuidString)_\(type.rawValue).jpg")
        }
        
        func imageSize(id: UUID, type: FileType) -> Int {
            let url = fileURL(for: id, type: type)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attrs[.size] as? NSNumber {
                return fileSize.intValue
            }
            return 0
        }
        
        func fileExists(id: UUID, type: FileType) -> Bool {
            let url = fileURL(for: id, type: type)
            return FileManager.default.fileExists(atPath: url.path)
        }

        func saveImage(_ image: UIImage, id: UUID, type: FileType) -> Bool {
            let resizedImage = image.resizedPreservingOrientation(toMaxDimension: type.maxDimension)
            guard let data = resizedImage.jpegData(compressionQuality: type.compressionQuality) else {
                print("failed to compress jpeg data")
                return false
            }
            return saveImageFile(data, id: id, type: type)
        }
        
        func saveImage(_ image: UIImage, id: UUID, types: [FileType] = FileType.allCases) -> Bool {
            var allSucceeded = true
            for type in types {
                if !saveImage(image, id: id, type: type) {
                    allSucceeded = false
                }
            }
            return allSucceeded
        }

        func saveImageFile(_ data: Data, id: UUID, type: FileType) -> Bool {
            let fileURL = fileURL(for: id, type: type)
            do {
                try data.write(to: fileURL)
                return true
            } catch {
                print("failed to save image \(type) for \(id): \(error)")
                return false
            }
        }

        func loadImage(id: UUID, type: FileType) -> UIImage? {
            let url = fileURL(for: id, type: type)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }

        func loadImageData(id: UUID, type: FileType) -> Data? {
            let url = fileURL(for: id, type: type)
            return try? Data(contentsOf: url)
        }

        func deleteImage(id: UUID, type: FileType) -> Bool {
            let url = fileURL(for: id, type: type)
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.removeItem(at: url)
                    return true
                } catch {
                    print("failed to delete image at \(url): \(error)")
                    return false
                }
            }
            return true
        }

        func deleteImage(id: UUID, types: [FileType] = FileType.allCases) -> Bool {
            var allSucceeded = true
            for type in types {
                if !deleteImage(id: id, type: type) {
                    allSucceeded = false
                }
            }
            return allSucceeded
        }
    }
}

extension UIImage {
    func resizedPreservingOrientation(toMaxDimension max: CGFloat) -> UIImage {
        guard let cgImage = self.cgImage else { return self }
        let originalSize = CGSize(width: cgImage.width, height: cgImage.height)
        let aspectRatio = originalSize.width / originalSize.height
        
        let newSize: CGSize
        if originalSize.width > originalSize.height {
            newSize = CGSize(width: max, height: max / aspectRatio)
        } else {
            newSize = CGSize(width: max * aspectRatio, height: max)
        }
        guard let context = CGContext(
            data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else { return self }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: newSize))
        guard let scaledCGImage = context.makeImage() else { return self }
        return UIImage(cgImage: scaledCGImage, scale: self.scale, orientation: self.imageOrientation)
    }
}


enum DataValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    enum CodingKeys: String, CodingKey {
        case type, value
    }

    enum ValueType: String, Codable {
        case string, int, double, bool
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let str):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(str, forKey: .value)
        case .int(let int):
            try container.encode(ValueType.int, forKey: .type)
            try container.encode(int, forKey: .value)
        case .double(let dbl):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(dbl, forKey: .value)
        case .bool(let bool):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(bool, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .string:
            let value = try container.decode(String.self, forKey: .value)
            self = .string(value)
        case .int:
            let value = try container.decode(Int.self, forKey: .value)
            self = .int(value)
        case .double:
            let value = try container.decode(Double.self, forKey: .value)
            self = .double(value)
        case .bool:
            let value = try container.decode(Bool.self, forKey: .value)
            self = .bool(value)
        }
    }
}

@Model
class Tag: Codable {
    var id = UUID()
    var created = Date()
    var timestamp = Date()
    var name: String
    var note: String
    var color: String?
    
    @Relationship(inverse: \ImageData.tags)
    var images: [ImageData] = []
    
    required init(name: String,
                  note: String = "") {
        self.name = name
        self.note = note
    }
    
    enum CodingKeys: String, CodingKey {
        case id, created, timestamp, name, note, color
    }
    
    required init(from decoder: Decoder) throws {
       let container = try decoder.container(keyedBy: CodingKeys.self)
       id = try container.decode(UUID.self, forKey: .id)
       created = try container.decode(Date.self, forKey: .created)
       timestamp = try container.decode(Date.self, forKey: .timestamp)
       name = try container.decode(String.self, forKey: .name)
       note = try container.decode(String.self, forKey: .name)
       color = try container.decode(String.self, forKey: .color)
   }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(created, forKey: .created)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(name, forKey: .name)
        try container.encode(note, forKey: .note)
        try container.encode(color, forKey: .color)
    }
}

extension Tag {
    var defaultColor: Color {
        if let hex = color, let resolved = Color(hex: hex) {
            return resolved
        } else {
            return Color.gray
        }
    }

    var isDefaultColor: Bool {
        (color == nil) || (color?.lowercased() == "#808080") || (defaultColor == .gray)
    }
}

@Model
class ImageData: Codable {
    var id = UUID()
    var created = Date()
    var timestamp = Date()
    var referenceCount: Int
    var name: String?
    var note: String?
    var creator: String?
    var metadata: [String: DataValue] = [:]
    
    var lastModified: Date {
        return timestamp
    }

    var original: UIImage? {
        ImageUtils.FileStorage.shared.loadImage(id: id, type: .original)
    }
    
    var thumbnail: UIImage? {
        ImageUtils.FileStorage.shared.loadImage(id: id, type: .thumbnail)
    }
    
    @Relationship var tags: [Tag] = []
    
    var orderedCategories: [Tag] {
        tags.sorted(by: { $0.timestamp < $1.timestamp })
    }

    func updateFile(to newImage: UIImage?) -> Bool {
        guard let newImage else { return false }
        var allRemoved = true
        if referenceCount == 1 {
            allRemoved = deleteFile()
        }
        let success = ImageUtils.FileStorage.shared.saveImage(
            newImage,
            id: id,
            types: ImageUtils.FileType.allCases
        )
        if success {
            timestamp = Date()
        } else {
            print("failed to save image for id: \(id)")
        }
        return success && allRemoved
    }
    
    func deleteFile() -> Bool {
        var allDeleted = true
        for type in ImageUtils.FileType.allCases {
            let success = ImageUtils.FileStorage.shared.deleteImage(id: id, type: type)
            if !success {
                print("failed to delete image file for id: \(id), type: \(type)")
                allDeleted = false
            }
        }
        return allDeleted
    }
    
    required init(
        tags: [Tag] = [],
        name: String? = nil,
        note: String? = nil,
        creator: String? = nil,
        metadata: [String: DataValue] = [:]
    ) {
        self.referenceCount = 1
        self.tags = tags
        self.name = name
        self.note = note
        self.creator = creator
        self.metadata = metadata
    }
    
    func cleanup(context: ModelContext) { // handled by reference counting
    }
    
    func incrementReference() {
        referenceCount += 1
    }

    func decrementReference() -> Bool {
        referenceCount -= 1
        var allDeleted = true
        if referenceCount <= 0 {
            for type in ImageUtils.FileType.allCases {
                let success = ImageUtils.FileStorage.shared.deleteImage(id: id, type: type)
                if !success {
                    print("failed to delete image \(id) for type: \(type)")
                    allDeleted = false
                }
            }
        }
        return referenceCount <= 0 && allDeleted
    }

    enum CodingKeys: String, CodingKey {
        case id, created, timestamp, referenceCount, tags, name, note, fcreator, metadata
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        created = try container.decode(Date.self, forKey: .timestamp)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        referenceCount = try container.decodeIfPresent(Int.self, forKey: .referenceCount) ?? 1
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags) ?? []
        name = try container.decodeIfPresent(String.self, forKey: .name)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        metadata = try container.decodeIfPresent([String: DataValue].self, forKey: .metadata) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(created, forKey: .created)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(referenceCount, forKey: .referenceCount)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(metadata, forKey: .metadata)
    }
}

@Model
class Gallery: Codable {
    var id = UUID()
    var timestamp = Date()
    
    @Relationship var tags: [Tag] = []
    
    var orderedTags: [Tag] {
        tags.sorted(by: { $0.created < $1.created })
    }

    var orderedImages: [ImageData] {
        images.sorted(by: { $0.timestamp < $1.timestamp })
    }
    
    @Relationship private var images: [ImageData] = []
    
    func addImage(_ image: ImageData) {
        if !images.contains(where: { $0.id == image.id }) {
            image.incrementReference()
            images.append(image)
        }
    }
    
    func deleteImage(_ image: ImageData, context: ModelContext) {
        if let index = images.firstIndex(where: { $0.id == image.id }) {
            images.remove(at: index)
            if image.decrementReference() {
                context.delete(image)
            }
        }
    }
    
    required init(images: [ImageData] = [], tags: [Tag] = []) {
        self.images = images
        self.tags = tags
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        images = try container.decodeIfPresent([ImageData].self, forKey: .images) ?? []
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags) ?? []
    }
    
    func cleanup(context: ModelContext) {
        for image in images {
            deleteImage(image, context: context)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, images, tags
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(images, forKey: .images)
        try container.encode(tags, forKey: .tags)
    }
}

@Model
class Project: Codable {
    var id = UUID()
    var created = Date()
    var timestamp = Date()
    var name: String
    var note: String
    var camera: String
    var counter: Int
    var pushPull: String
    var filmDate: Date
    var filmSize: String
    var filmStock: String
    var isArchived: Bool
    var isLocked: Bool

    @Relationship var shots: [Shot] = []
    
    var orderedShots: [Shot] {
        shots.sorted(by: { $0.timestamp < $1.timestamp })
    }
    
    var lastModified: Date {
        if let latestShotDate = shots.map(\.timestamp).max() {
            return max(timestamp, latestShotDate)
        } else {
            return timestamp
        }
    }
    
    func deleteShot(_ shot: Shot, context: ModelContext) {
        if let index = shots.firstIndex(where: { $0.id == shot.id }) {
            shots.remove(at: index)
            context.delete(shot)
        }
    }

    required init(name: String = "",
         note: String = "",
         camera: String = "-",
         counter: Int = 24,
         pushPull: String = "0",
         filmDate: Date = Date(),
         filmSize: String = "135 (35mm)",
         filmStock: String = "100",
         image: ImageData? = nil,
         lightMeterImage: ImageData? = nil,
         archived: Bool = false,
         isLocked: Bool = false) {
        self.name = name
        self.note = note
        self.camera = camera
        self.counter = counter
        self.pushPull = pushPull
        self.filmDate = filmDate
        self.filmSize = filmSize
        self.filmStock = filmStock
        self.isArchived = archived
        self.isLocked = isLocked
    }
    
    func cleanup(context: ModelContext) {
    }

    enum CodingKeys: String, CodingKey {
        case id, created, timestamp, name, note, camera, counter, pushPull, filmDate, filmSize, filmStock, image, isArchived, isLocked, shots
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        created = try container.decode(Date.self, forKey: .created)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        name = try container.decode(String.self, forKey: .name)
        note = try container.decode(String.self, forKey: .note)
        camera = try container.decode(String.self, forKey: .camera)
        counter = try container.decode(Int.self, forKey: .counter)
        pushPull = try container.decode(String.self, forKey: .pushPull)
        filmDate = try container.decode(Date.self, forKey: .filmDate)
        filmSize = try container.decode(String.self, forKey: .filmSize)
        filmStock = try container.decode(String.self, forKey: .filmStock)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
        shots = try container.decodeIfPresent([Shot].self, forKey: .shots) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(created, forKey: .created)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(name, forKey: .name)
        try container.encode(note, forKey: .note)
        try container.encode(camera, forKey: .camera)
        try container.encode(counter, forKey: .counter)
        try container.encode(pushPull, forKey: .pushPull)
        try container.encode(filmDate, forKey: .filmDate)
        try container.encode(filmSize, forKey: .filmSize)
        try container.encode(filmStock, forKey: .filmStock)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(shots, forKey: .shots)
    }
}

extension Project {
    static func createDefault(in context: ModelContext) -> Project {
        let baseName = "Untitled"
        var name = baseName
        var index = 1

        let projects = try? context.fetch(FetchDescriptor<Project>())
        let names = Set(projects?.map { $0.name } ?? [])
        while names.contains(name) {
            name = "\(baseName) \(index)"
            index += 1
        }

        let project = Project(name: name)
        context.insert(project)

        let firstShot = Shot.createDefault(for: project, in: context)
        project.shots.append(firstShot)

        return project
    }
}

@Model
class Shot: Codable {
    var id = UUID()
    var created = Date()
    var timestamp = Date()
    var filmSize: String
    var filmStock: String
    var aspectRatio: String
    var name: String
    var note: String
    var location: LocationUtils.Location?
    var locationTimestamp: Date?
    var locationColorTemperature: Int?
    var locationElevation: Double?
    var aperture: String
    var shutter: String
    var exposureCompensation: String
    var lens: String
    var colorFilter: String
    var ndFilter: String
    var focalLength: String
    var focusDistance: Double
    var focusDepthOfField: Double
    var focusNearLimit: Double
    var focusFarLimit: Double
    var focusHyperfocalDistance: Double
    var focusHyperfocalNearLimit: Double
    var exposureSky: String
    var exposureFoliage: String
    var exposureHighlights: String
    var exposureMidGray: String
    var exposureShadows: String
    var exposureSkinKey: String
    var exposureSkinFill: String
    var deviceRoll: Double
    var deviceTilt: Double
    var deviceCameraMode: String
    var deviceLens: String
    var isLocked: Bool
    
    var lastModified: Date {
        return timestamp
    }

    @Relationship private var image: ImageData?
    
    public var imageData: ImageData? {
        return image
    }
    
    func updateImage(to newImage: ImageData?, context: ModelContext) {
        deleteImage(context: context)
        if let newImage = newImage {
            newImage.incrementReference()
        }
        self.timestamp = Date()
        self.image = newImage
    }
    
    func deleteImage(context: ModelContext) {
        if let image = self.image {
            if image.decrementReference() {
                context.delete(image)
            }
            self.timestamp = Date()
            self.image = nil
        }
    }

    required init(filmSize: String = "135 (35mm)",
         filmStock: String = "100",
         aspectRatio: String = "-",
         name: String = "",
         note: String = "",
         location: LocationUtils.Location? = nil,
         locationTimestamp: Date? = nil,
         locationColorTemperature: Int? = 0,
         locationElevation: Double? = 0.0,
         aperture: String = "f/2.8",
         shutter: String = "1/125",
         exposureCompensation: String = "0",
         lens: String = "-",
         colorFilter: String = "-",
         ndFilter: String = "-",
         focalLength: String = "50mm",
         focusDistance: Double = 500,
         focusDepthOfField: Double = 0.0,
         focusNearLimit: Double = 0.0,
         focusFarLimit: Double = 0.0,
         focusHyperfocalDistance: Double = 0.0,
         focusHyperfocalNearLimit: Double = 0.0,
         exposureSky: String = "0",
         exposureFoliage: String = "0",
         exposureHighlights: String = "0",
         exposureMidGray: String = "0",
         exposureShadows: String = "0",
         exposureSkinKey: String = "0",
         exposureSkinFill: String = "0",
         deviceRoll: Double = 0.0,
         deviceTilt: Double = 0.0,
         deviceCameraMode: String = "",
         deviceLens: String = "",
         image: ImageData? = nil,
         isLocked: Bool = false) {
        self.filmSize = filmSize
        self.filmStock = filmStock
        self.aspectRatio = aspectRatio
        self.name = name
        self.note = note
        self.location = location
        self.locationTimestamp = locationTimestamp
        self.locationColorTemperature = locationColorTemperature
        self.locationElevation = locationElevation
        self.aperture = aperture
        self.shutter = shutter
        self.exposureCompensation = exposureCompensation
        self.lens = lens
        self.colorFilter = colorFilter
        self.ndFilter = ndFilter
        self.focalLength = focalLength
        self.focusDistance = focusDistance
        self.focusDepthOfField = focusDepthOfField
        self.focusNearLimit = focusNearLimit
        self.focusFarLimit = focusFarLimit
        self.focusHyperfocalDistance = focusHyperfocalDistance
        self.focusHyperfocalNearLimit = focusHyperfocalNearLimit
        self.exposureSky = exposureSky
        self.exposureFoliage = exposureFoliage
        self.exposureHighlights = exposureHighlights
        self.exposureMidGray = exposureMidGray
        self.exposureShadows = exposureShadows
        self.exposureSkinKey = exposureSkinKey
        self.exposureSkinFill = exposureSkinFill
        self.deviceRoll = deviceRoll
        self.deviceTilt = deviceTilt
        self.deviceCameraMode = deviceCameraMode
        self.deviceLens = deviceLens
        self.image = image
        self.isLocked = isLocked
    }
    
    func cleanup(context: ModelContext) {
        deleteImage(context: context)
    }

    func copy(context: ModelContext) -> Shot {
        let newShot = Shot()
        newShot.created = self.created
        newShot.filmSize = self.filmSize
        newShot.filmStock = self.filmStock
        newShot.aspectRatio = self.aspectRatio
        newShot.name = self.name
        newShot.note = self.note
        newShot.location = self.location
        newShot.locationTimestamp = self.locationTimestamp
        newShot.locationColorTemperature = self.locationColorTemperature
        newShot.locationElevation = self.locationElevation
        newShot.aperture = self.aperture
        newShot.shutter = self.shutter
        newShot.exposureCompensation = self.exposureCompensation
        newShot.lens = self.lens
        newShot.colorFilter = self.colorFilter
        newShot.ndFilter = self.ndFilter
        newShot.focalLength = self.focalLength
        newShot.focusDistance = self.focusDistance
        newShot.focusDepthOfField = self.focusDepthOfField
        newShot.focusNearLimit = self.focusNearLimit
        newShot.focusFarLimit = self.focusFarLimit
        newShot.focusHyperfocalDistance = self.focusHyperfocalDistance
        newShot.focusHyperfocalNearLimit = self.focusHyperfocalNearLimit
        newShot.exposureSky = self.exposureSky
        newShot.exposureFoliage = self.exposureFoliage
        newShot.exposureHighlights = self.exposureHighlights
        newShot.exposureMidGray = self.exposureMidGray
        newShot.exposureShadows = self.exposureShadows
        newShot.exposureSkinKey = self.exposureSkinKey
        newShot.exposureSkinFill = self.exposureSkinFill
        newShot.deviceRoll = self.deviceRoll
        newShot.deviceTilt = self.deviceTilt
        newShot.deviceCameraMode = self.deviceCameraMode
        newShot.deviceLens = self.deviceLens

        newShot.updateImage(to: self.image, context: context)

        return newShot
    }

    enum CodingKeys: String, CodingKey {
        case id, created, timestamp, filmSize, filmStock, aspectRatio, name, note,
             location, locationTimestamp, locationColorTemperature, locationElevation,
             aperture, shutter, exposureCompensation, lens, colorFilter, ndFilter, focalLength,
             focusDistance, focusDepthOfField, focusNearLimit, focusFarLimit, focusHyperfocalDistance, focusHyperfocalNearLimit,
             exposureSky, exposureFoliage, exposureHighlights, exposureMidGray, exposureShadows, exposureSkinKey, exposureSkinFill,
             deviceRoll, deviceTilt, deviceCameraMode, deviceLens,
             image, isLocked
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        created = try container.decode(Date.self, forKey: .created)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        filmSize = try container.decode(String.self, forKey: .filmSize)
        filmStock = try container.decode(String.self, forKey: .filmStock)
        aspectRatio = try container.decode(String.self, forKey: .aspectRatio)
        name = try container.decode(String.self, forKey: .name)
        note = try container.decode(String.self, forKey: .note)
        location = try container.decodeIfPresent(LocationUtils.Location.self, forKey: .location)
        locationTimestamp = try container.decodeIfPresent(Date.self, forKey: .locationTimestamp)
        locationColorTemperature = try container.decode(Int.self, forKey: .locationColorTemperature)
        locationElevation = try container.decode(Double.self, forKey: .locationElevation)
        aperture = try container.decode(String.self, forKey: .aperture)
        shutter = try container.decode(String.self, forKey: .shutter)
        exposureCompensation = try container.decode(String.self, forKey: .exposureCompensation)
        lens = try container.decode(String.self, forKey: .lens)
        colorFilter = try container.decode(String.self, forKey: .colorFilter)
        ndFilter = try container.decode(String.self, forKey: .ndFilter)
        focalLength = try container.decode(String.self, forKey: .focalLength)
        focusDistance = try container.decode(Double.self, forKey: .focusDistance)
        focusDepthOfField = try container.decode(Double.self, forKey: .focusDepthOfField)
        focusNearLimit = try container.decode(Double.self, forKey: .focusNearLimit)
        focusFarLimit = try container.decode(Double.self, forKey: .focusFarLimit)
        focusHyperfocalDistance = try container.decode(Double.self, forKey: .focusHyperfocalDistance)
        focusHyperfocalNearLimit = try container.decode(Double.self, forKey: .focusHyperfocalNearLimit)
        exposureSky = try container.decode(String.self, forKey: .exposureSky)
        exposureFoliage = try container.decode(String.self, forKey: .exposureFoliage)
        exposureHighlights = try container.decode(String.self, forKey: .exposureHighlights)
        exposureMidGray = try container.decode(String.self, forKey: .exposureMidGray)
        exposureShadows = try container.decode(String.self, forKey: .exposureShadows)
        exposureSkinKey = try container.decode(String.self, forKey: .exposureSkinKey)
        exposureSkinFill = try container.decode(String.self, forKey: .exposureSkinFill)
        deviceRoll = try container.decode(Double.self, forKey: .deviceRoll)
        deviceTilt = try container.decode(Double.self, forKey: .deviceTilt)
        deviceCameraMode = try container.decode(String.self, forKey: .deviceCameraMode)
        deviceLens = try container.decode(String.self, forKey: .deviceLens)
        image = try container.decodeIfPresent(ImageData.self, forKey: .image)
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(created, forKey: .created)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(filmSize, forKey: .filmSize)
        try container.encode(filmStock, forKey: .filmStock)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(name, forKey: .name)
        try container.encode(note, forKey: .note)
        try container.encode(location, forKey: .location)
        try container.encode(locationTimestamp, forKey: .locationTimestamp)
        try container.encode(locationElevation, forKey: .locationElevation)
        try container.encode(locationColorTemperature, forKey: .locationColorTemperature)
        try container.encode(aperture, forKey: .aperture)
        try container.encode(shutter, forKey: .shutter)
        try container.encode(exposureCompensation, forKey: .exposureCompensation)
        try container.encode(lens, forKey: .lens)
        try container.encode(colorFilter, forKey: .colorFilter)
        try container.encode(ndFilter, forKey: .ndFilter)
        try container.encode(focalLength, forKey: .focalLength)
        try container.encode(focusDistance, forKey: .focusDistance)
        try container.encode(focusDepthOfField, forKey: .focusDepthOfField)
        try container.encode(focusNearLimit, forKey: .focusNearLimit)
        try container.encode(focusFarLimit, forKey: .focusFarLimit)
        try container.encode(focusHyperfocalDistance, forKey: .focusHyperfocalDistance)
        try container.encode(focusHyperfocalNearLimit, forKey: .focusHyperfocalNearLimit)
        try container.encode(exposureSky, forKey: .exposureSky)
        try container.encode(exposureFoliage, forKey: .exposureFoliage)
        try container.encode(exposureHighlights, forKey: .exposureHighlights)
        try container.encode(exposureMidGray, forKey: .exposureMidGray)
        try container.encode(exposureShadows, forKey: .exposureShadows)
        try container.encode(exposureSkinKey, forKey: .exposureSkinKey)
        try container.encode(exposureSkinFill, forKey: .exposureSkinFill)
        try container.encode(deviceRoll, forKey: .deviceRoll)
        try container.encode(deviceTilt, forKey: .deviceTilt)
        try container.encode(deviceCameraMode, forKey: .deviceCameraMode)
        try container.encode(deviceLens, forKey: .deviceLens)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encode(isLocked, forKey: .isLocked)
    }
}

extension Shot {
    static func createDefault(for project: Project, in context: ModelContext) -> Shot {
        let baseName = "Shot"
        var name = baseName
        var index = 1
        let names = Set(project.shots.map { $0.name })
        while names.contains(name) {
            name = "\(baseName) \(index)"
            index += 1
        }
        let shot = Shot(
            filmSize: project.filmSize,
            filmStock: project.filmStock,
            name: name
        )
        context.insert(shot)
        return shot
    }
}

extension ModelContext {
    func safelyDelete(_ gallery: Gallery) {
        gallery.cleanup(context: self)
        self.delete(gallery)
    }
    
    func safelyDelete(_ project: Project) {
        project.cleanup(context: self)
        self.delete(project)
    }
    
    func safelyDelete(_ shot: Shot) {
        shot.cleanup(context: self)
        self.delete(shot)
    }
    
    func safelyDelete(_ image: ImageData) {
        image.cleanup(context: self)
        self.delete(image)
    }
}
