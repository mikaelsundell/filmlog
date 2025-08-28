// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import SwiftData
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
    struct FilmSize {
        let width: Double
        let height: Double
        
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
        static let defaultFilmSize = CameraUtils.FilmSize(width: 36.0, height: 24.0)
    }
    
    struct AspectRatio: Equatable {
        let numerator: Int
        let denominator: Int

        var ratio: Double {
            return Double(numerator) / Double(denominator)
        }
        
        static let defaultAspectRatio = CameraUtils.AspectRatio(numerator: 0, denominator: 1)
    }
    
    struct FilmStock {
        let speed: Double
        let colorTemperature: Double
        
        static let defaultFilmStock = CameraUtils.FilmStock(speed: 100, colorTemperature: 5600)
    }
    
    struct Filter: Equatable {
        let exposureCompensation: Double
        let colorTemperatureShift: Double
        
        static let defaultFilter = Filter(exposureCompensation: 0.0, colorTemperatureShift: 0.0)
    }
    
    struct FocalLength: Equatable {
        let length: Double
        
        static let defaultFocalLength = FocalLength(length: 50)
    }
    
    struct Aperture: Equatable {
        let fstop: Double
        
        static let defaultAperture = CameraUtils.Aperture(fstop: 2.8)
    }
    
    struct Shutter: Equatable {
        let numerator: Int
        let denominator: Int

        var shutter: Double {
            return Double(numerator) / Double(denominator)
        }
        
        static let defaultShutter = CameraUtils.Shutter(numerator: 1, denominator: 125)
    }
    
    static let aspectRatios: [(label: String, value: AspectRatio)] = [
        ("-", AspectRatio(numerator: 0, denominator: 1)),
        ("1:1", AspectRatio(numerator: 1, denominator: 1)),
        ("5:4", AspectRatio(numerator: 5, denominator: 4)),
        ("4:3", AspectRatio(numerator: 4, denominator: 3)),
        ("3:2", AspectRatio(numerator: 3, denominator: 2)),
        ("16:10", AspectRatio(numerator: 16, denominator: 10)),
        ("16:9", AspectRatio(numerator: 16, denominator: 9)),
        ("1.43", AspectRatio(numerator: 143, denominator: 100)),
        ("1.66", AspectRatio(numerator: 166, denominator: 100)),
        ("1.85", AspectRatio(numerator: 185, denominator: 100)),
        ("1.90", AspectRatio(numerator: 190, denominator: 100)),
        ("2.00", AspectRatio(numerator: 200, denominator: 100)),
        ("2.20", AspectRatio(numerator: 220, denominator: 100)),
        ("2.35", AspectRatio(numerator: 235, denominator: 100)),
        ("2.39", AspectRatio(numerator: 239, denominator: 100)),
        ("2.55", AspectRatio(numerator: 255, denominator: 100))
    ]
    
    static let cameras: [String] = [
        "-",
        "Canon AE-1",
        "Canon A-1",
        "Canon F-1",
        "Nikon FM2",
        "Nikon FE2",
        "Nikon F3",
        "Olympus OM-1",
        "Olympus OM-2",
        "Pentax K1000",
        "Minolta X-700",
        "Leica M3",
        "Leica M6",
        "Contax T2",
        "Hasselblad 500C/M",
        "Mamiya RB67",
        "Yashica Mat-124G",
        "Other"];
    
    static let filmSizes: [(label: String, value: FilmSize)] = [
        ("135 (35mm)", FilmSize(width: 36.0, height: 24.0)),
        ("120 (6x6)", FilmSize(width: 60.0, height: 60.0)),
        ("120 (6x7)", FilmSize(width: 70.0, height: 60.0)),
        ("120 (6x9)", FilmSize(width: 90.0, height: 60.0)),
        ("Large Format (4x5)", FilmSize(width: 127.0, height: 101.6)),
        ("35mm Academy (4-perf)", FilmSize(width: 21.95, height: 16.00)),
        ("35mm Full Aperture (Silent)", FilmSize(width: 24.89, height: 18.66)),
        ("Super 35 (4-perf)", FilmSize(width: 24.89, height: 18.66)),
        ("Super 35 (3-perf)", FilmSize(width: 24.89, height: 13.87)),
        ("Techniscope (2-perf)", FilmSize(width: 22.00, height: 9.47)),
        ("70mm (5-perf)", FilmSize(width: 48.56, height: 22.10)),
        ("IMAX 70mm (15-perf)", FilmSize(width: 70.41, height: 52.63)),
        ("Alexa Mini / Classic (Open Gate)", FilmSize(width: 28.17, height: 18.13)),
        ("Alexa Mini / Classic (16:9)", FilmSize(width: 23.76, height: 13.37)),
        ("Alexa Mini / Classic (4:3)", FilmSize(width: 23.76, height: 17.82)),
        ("Alexa LF (Open Gate)", FilmSize(width: 36.70, height: 25.54)),
        ("Alexa LF (16:9)", FilmSize(width: 31.68, height: 17.82)),
        ("Alexa 65 (Open Gate)", FilmSize(width: 54.12, height: 25.58))
    ]
    
    static let filmStocks: [(label: String, value: FilmStock)] = [
        ("Vision3 50D 5203", FilmStock(speed: 50, colorTemperature: 5600)),
        ("Vision3 250D 5207", FilmStock(speed: 250, colorTemperature: 5600)),
        ("Vision3 200T 5213", FilmStock(speed: 200, colorTemperature: 3200)),
        ("Vision3 500T 5219", FilmStock(speed: 500, colorTemperature: 3200)),
        ("Kodak Ektachrome", FilmStock(speed: 100, colorTemperature: 5600)),
        ("Kodak Double X 5222", FilmStock(speed: 250, colorTemperature: 5600)),
        ("EI 50", FilmStock(speed: 50, colorTemperature: 5600)),
        ("EI 100", FilmStock(speed: 100, colorTemperature: 5600)),
        ("EI 200", FilmStock(speed: 200, colorTemperature: 5600)),
        ("EI 400", FilmStock(speed: 400, colorTemperature: 5600)),
        ("EI 800", FilmStock(speed: 800, colorTemperature: 5600)),
        ("EI 1600", FilmStock(speed: 1600, colorTemperature: 5600)),
        ("EI 3200", FilmStock(speed: 3200, colorTemperature: 5600)),
        ("Q2 Test", FilmStock(speed: 400, colorTemperature: 5600)),
    ]
    
    static let colorFilters: [(label: String, value: Filter)] = [
        ("-", Filter(exposureCompensation: 0, colorTemperatureShift: 0)),
        ("85", Filter(exposureCompensation: -0.6, colorTemperatureShift: -2100)),
        ("85B", Filter(exposureCompensation: -0.6, colorTemperatureShift: -2300)),
        ("85C", Filter(exposureCompensation: -0.3, colorTemperatureShift: -1700)),
        ("80A", Filter(exposureCompensation: -1.0, colorTemperatureShift: +2300)),
        ("80B", Filter(exposureCompensation: -1.0, colorTemperatureShift: +1900)),
        ("80C", Filter(exposureCompensation: -0.6, colorTemperatureShift: +1200)),
        ("81A", Filter(exposureCompensation: -0.3, colorTemperatureShift: -300)),
        ("81B", Filter(exposureCompensation: -0.3, colorTemperatureShift: -450)),
        ("81C", Filter(exposureCompensation: -0.3, colorTemperatureShift: -600)),
        ("82A", Filter(exposureCompensation: -0.3, colorTemperatureShift: +200)),
        ("82B", Filter(exposureCompensation: -0.3, colorTemperatureShift: +400)),
        ("82C", Filter(exposureCompensation: -0.3, colorTemperatureShift: +600))
    ]
    
    static let ndFilters: [(label: String, value: Filter)] = [
        ("-", Filter(exposureCompensation: 0, colorTemperatureShift: 0)),
        ("0.3", Filter(exposureCompensation: -1.0, colorTemperatureShift: 0)),
        ("0.6", Filter(exposureCompensation: -2.0, colorTemperatureShift: 0)),
        ("0.9", Filter(exposureCompensation: -3.0, colorTemperatureShift: 0)),
        ("1.2", Filter(exposureCompensation: -4.0, colorTemperatureShift: 0)),
        ("2.1", Filter(exposureCompensation: -6.0, colorTemperatureShift: 0))
    ]
    
    static let focalLengths: [(label: String, value: FocalLength)] = [
        ("12mm", FocalLength(length: 12)),
        ("14mm", FocalLength(length: 14)),
        ("19mm", FocalLength(length: 19)),
        ("20mm", FocalLength(length: 20)),
        ("24mm", FocalLength(length: 24)),
        ("28mm", FocalLength(length: 28)),
        ("35mm", FocalLength(length: 35)),
        ("40mm", FocalLength(length: 40)),
        ("50mm", FocalLength(length: 50)),
        ("70mm", FocalLength(length: 70)),
        ("80mm", FocalLength(length: 80)),
        ("85mm", FocalLength(length: 85)),
        ("105mm", FocalLength(length: 105)),
        ("135mm", FocalLength(length: 135)),
        ("200mm", FocalLength(length: 200)),
        ("300mm", FocalLength(length: 300)),
    ]

    static let apertures: [(label: String, value: Aperture)] = [
        ("f/1.4", Aperture(fstop: 1.4)),
        ("f/2", Aperture(fstop: 2.0)),
        ("f/2.8", Aperture(fstop: 2.8)),
        ("f/4", Aperture(fstop: 4)),
        ("f/5.6", Aperture(fstop: 5.6)),
        ("f/8", Aperture(fstop: 8)),
        ("f/11", Aperture(fstop: 11)),
        ("f/16", Aperture(fstop: 16)),
        ("f/22", Aperture(fstop: 22))
    ]
    
    static let lensNames: [String] = [
         "-",
         "Canon FD",
         "Canon CN-E",
         "Nikon",
         "Leica R",
         "Other"
    ]
    
    static let shutters: [(label: String, value: Shutter)] = [
        ("24 fps", Shutter(numerator: 1, denominator: 48)),
        ("25 fps", Shutter(numerator: 1, denominator: 50)),
        ("30 fps", Shutter(numerator: 1, denominator: 60)),
        ("50 fps", Shutter(numerator: 1, denominator: 100)),
        ("60 fps", Shutter(numerator: 1, denominator: 120)),
        ("1/2", Shutter(numerator: 1, denominator: 2)),
        ("1/4", Shutter(numerator: 1, denominator: 4)),
        ("1/8", Shutter(numerator: 1, denominator: 8)),
        ("1/15", Shutter(numerator: 1, denominator: 15)),
        ("1/30", Shutter(numerator: 1, denominator: 30)),
        ("1/50", Shutter(numerator: 1, denominator: 50)),
        ("1/60", Shutter(numerator: 1, denominator: 60)),
        ("1/100", Shutter(numerator: 1, denominator: 100)),
        ("1/125", Shutter(numerator: 1, denominator: 125)),
        ("1/250", Shutter(numerator: 1, denominator: 250)),
        ("1/500", Shutter(numerator: 1, denominator: 500)),
        ("1/1000", Shutter(numerator: 1, denominator: 1000)),
        ("1/2000", Shutter(numerator: 1, denominator: 2000)),
        ("1/4000", Shutter(numerator: 1, denominator: 4000)),
        ("1", Shutter(numerator: 1, denominator: 1)),
        ("2", Shutter(numerator: 2, denominator: 1)),
        ("4", Shutter(numerator: 4, denominator: 1)),
    ]
}

struct ImageUtils {
    enum FileType: String, CaseIterable {
        case original
        case thumbnail
        
        var maxDimension: CGFloat {
            switch self {
            case .original:
                return 3840
            case .thumbnail:
                return 320
            }
        }

        var compressionQuality: CGFloat {
            switch self {
            case .original:
                return 0.9
            case .thumbnail:
                return 0.7
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
            let resizedImage = image.resized(toMaxDimension: type.maxDimension)
            guard let data = resizedImage.jpegData(compressionQuality: type.compressionQuality) else {
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
                    print("Failed to delete image at \(url): \(error)")
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
    func resized(toMaxDimension max: CGFloat) -> UIImage {
        let originalSize = self.size
        let aspectRatio = originalSize.width / originalSize.height

        let newSize: CGSize
        if originalSize.width > originalSize.height {
            newSize = CGSize(width: max, height: max / aspectRatio)
        } else {
            newSize = CGSize(width: max * aspectRatio, height: max)
        }
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
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
class Category: Codable {
    var id = UUID()
    var timestamp = Date()
    var name: String
    
    required init(name: String) {
        self.name = name
    }
    
    enum CodingKeys: String, CodingKey {
        case id, timestamp, name
    }
    
    required init(from decoder: Decoder) throws {
       let container = try decoder.container(keyedBy: CodingKeys.self)
       id = try container.decode(UUID.self, forKey: .id)
       timestamp = try container.decode(Date.self, forKey: .timestamp)
       name = try container.decode(String.self, forKey: .name)
   }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(name, forKey: .name)
    }
}

@Model
class ImageData: Codable {
    var id = UUID()
    var timestamp = Date()
    var referenceCount: Int
    var name: String?
    var note: String?
    var creator: String?
    var metadata: [String: DataValue] = [:]

    var original: UIImage? {
        ImageUtils.FileStorage.shared.loadImage(id: id, type: .original)
    }
    
    var thumbnail: UIImage? {
        ImageUtils.FileStorage.shared.loadImage(id: id, type: .thumbnail)
    }
    
    @Relationship var categories: [Category] = []
    
    var orderedCategories: [Category] {
        categories.sorted(by: { $0.timestamp < $1.timestamp })
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
        categories: [Category] = [],
        name: String? = nil,
        note: String? = nil,
        creator: String? = nil,
        metadata: [String: DataValue] = [:]
    ) {
        self.referenceCount = 1
        self.categories = categories
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
        case id, filePath, thumbnailPath, referenceCount, categories, name, note, creator, timestamp, metadata
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        referenceCount = try container.decodeIfPresent(Int.self, forKey: .referenceCount) ?? 1
        categories = try container.decodeIfPresent([Category].self, forKey: .categories) ?? []
        name = try container.decodeIfPresent(String.self, forKey: .name)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        creator = try container.decodeIfPresent(String.self, forKey: .creator)
        metadata = try container.decodeIfPresent([String: DataValue].self, forKey: .metadata) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(referenceCount, forKey: .referenceCount)
        try container.encodeIfPresent(categories, forKey: .categories)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(creator, forKey: .creator)
        try container.encode(metadata, forKey: .metadata)
    }
}

@Model
class Gallery: Codable {
    var id = UUID()
    var timestamp = Date()
    
    @Relationship var categories: [Category] = []
    
    var orderedCategories: [Category] {
        categories.sorted(by: { $0.timestamp < $1.timestamp })
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
    
    required init(images: [ImageData] = [], categories: [Category] = []) {
        self.images = images
        self.categories = categories
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        images = try container.decodeIfPresent([ImageData].self, forKey: .images) ?? []
        categories = try container.decodeIfPresent([Category].self, forKey: .categories) ?? []
    }
    
    func cleanup(context: ModelContext) {
        for image in images {
            deleteImage(image, context: context)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, images, categories
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(images, forKey: .images)
        try container.encode(categories, forKey: .categories)
    }
}

@Model
class Roll: Codable {
    var id = UUID()
    var timestamp = Date()
    var name: String
    var note: String
    var camera: String
    var counter: Int
    var pushPull: String
    var filmDate: Date
    var filmSize: String
    var filmStock: String
    var status: String
    var isLocked: Bool

    @Relationship var shots: [Shot] = []
    
    var orderedShots: [Shot] {
        shots.sorted(by: { $0.timestamp < $1.timestamp })
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
        self.image = newImage
    }
    
    func deleteImage(context: ModelContext) {
        if let image = self.image {
            if image.decrementReference() {
                context.delete(image)
            }
            self.image = nil
        }
    }

    required init(name: String = "",
         note: String = "",
         camera: String = "Other",
         counter: Int = 24,
         pushPull: String = "0",
         filmDate: Date = Date(),
         filmSize: String = "135 (35mm)",
         filmStock: String = "Vision3 50D 5203",
         image: ImageData? = nil,
         lightMeterImage: ImageData? = nil,
         status: String = "new",
         isLocked: Bool = false) {
        self.name = name
        self.note = note
        self.camera = camera
        self.counter = counter
        self.pushPull = pushPull
        self.filmDate = filmDate
        self.filmSize = filmSize
        self.filmStock = filmStock
        self.image = image
        self.status = status
        self.isLocked = isLocked
    }
    
    func cleanup(context: ModelContext) {
        if let img = image, img.decrementReference() {
            context.delete(img)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, name, note, camera, counter, pushPull, filmDate, filmSize, filmStock, image, status, isLocked, shots
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        name = try container.decode(String.self, forKey: .name)
        note = try container.decode(String.self, forKey: .note)
        camera = try container.decode(String.self, forKey: .camera)
        counter = try container.decode(Int.self, forKey: .counter)
        pushPull = try container.decode(String.self, forKey: .pushPull)
        filmDate = try container.decode(Date.self, forKey: .filmDate)
        filmSize = try container.decode(String.self, forKey: .filmSize)
        filmStock = try container.decode(String.self, forKey: .filmStock)
        image = try container.decodeIfPresent(ImageData.self, forKey: .image)
        status = try container.decode(String.self, forKey: .status)
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
        shots = try container.decodeIfPresent([Shot].self, forKey: .shots) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(name, forKey: .name)
        try container.encode(note, forKey: .note)
        try container.encode(camera, forKey: .camera)
        try container.encode(counter, forKey: .counter)
        try container.encode(pushPull, forKey: .pushPull)
        try container.encode(filmDate, forKey: .filmDate)
        try container.encode(filmSize, forKey: .filmSize)
        try container.encode(filmStock, forKey: .filmStock)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encode(status, forKey: .status)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(shots, forKey: .shots)
    }
}

@Model
class Shot: Codable {
    var id = UUID()
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
    var lensName: String
    var lensColorFilter: String
    var lensNdFilter: String
    var lensFocalLength: String
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
    var isLocked: Bool

    @Relationship private var image: ImageData?
    
    public var imageData: ImageData? {
        return image
    }
    
    func updateImage(to newImage: ImageData?, context: ModelContext) {
        deleteImage(context: context)
        if let newImage = newImage {
            newImage.incrementReference()
        }
        self.image = newImage
    }
    
    func deleteImage(context: ModelContext) {
        if let image = self.image {
            if image.decrementReference() {
                context.delete(image)
            }
            self.image = nil
        }
    }
    
    @Relationship private var lightMeterImage: ImageData?
    
    public var lightMeterImageData: ImageData? {
        return lightMeterImage
    }
    
    func updateLightMeterImage(to newImage: ImageData?, context: ModelContext) {
        deleteLightMeterImage(context: context)
        if let newImage = newImage {
            newImage.incrementReference()
        }
        self.lightMeterImage = newImage
    }
    
    func deleteLightMeterImage(context: ModelContext) {
        if let image = self.lightMeterImage {
            if image.decrementReference() {
                context.delete(image)
            }
            self.lightMeterImage = nil
        }
    }

    required init(filmSize: String = "",
         filmStock: String = "",
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
         lensName: String = "Other",
         lensColorFilter: String = "-",
         lensNdFilter: String = "-",
         lensFocalLength: String = "50mm",
         focusDistance: Double = 500,
         focusDepthOfField: Double = 0.0,
         focusNearLimit: Double = 0.0,
         focusFarLimit: Double = 0.0,
         focusHyperfocalDistance: Double = 0.0,
         focusHyperfocalNearLimit: Double = 0.0,
         exposureSky: String = "-",
         exposureFoliage: String = "-",
         exposureHighlights: String = "-",
         exposureMidGray: String = "-",
         exposureShadows: String = "-",
         exposureSkinKey: String = "-",
         exposureSkinFill: String = "-",
         image: ImageData? = nil,
         lightMeterImage: ImageData? = nil,
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
        self.lensName = lensName
        self.lensColorFilter = lensColorFilter
        self.lensNdFilter = lensNdFilter
        self.lensFocalLength = lensFocalLength
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
        self.image = image
        self.lightMeterImage = lightMeterImage
        self.isLocked = isLocked
    }
    
    func cleanup(context: ModelContext) {
        deleteImage(context: context)
        deleteLightMeterImage(context: context)
    }

    func copy(context: ModelContext) -> Shot {
        let newShot = Shot()
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
        newShot.lensName = self.lensName
        newShot.lensColorFilter = self.lensColorFilter
        newShot.lensNdFilter = self.lensNdFilter
        newShot.lensFocalLength = self.lensFocalLength
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

        newShot.updateImage(to: self.image, context: context)
        newShot.updateLightMeterImage(to: self.lightMeterImage, context: context)

        return newShot
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, filmSize, filmStock, aspectRatio, name, note, location, locationTimestamp, locationColorTemperature,
             locationElevation, aperture, shutter, exposureCompensation, lensName, lensColorFilter, lensNdFilter, lensFocalLength,
             focusDistance, focusDepthOfField, focusNearLimit, focusFarLimit, focusHyperfocalDistance,
             focusHyperfocalNearLimit, exposureSky, exposureFoliage, exposureHighlights, exposureMidGray,
             exposureShadows, exposureSkinKey, exposureSkinFill, image, lightMeterImage, isLocked
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
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
        lensName = try container.decode(String.self, forKey: .lensName)
        lensColorFilter = try container.decode(String.self, forKey: .lensColorFilter)
        lensNdFilter = try container.decode(String.self, forKey: .lensNdFilter)
        lensFocalLength = try container.decode(String.self, forKey: .lensFocalLength)
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
        image = try container.decodeIfPresent(ImageData.self, forKey: .image)
        lightMeterImage = try container.decodeIfPresent(ImageData.self, forKey: .lightMeterImage)
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
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
        try container.encode(lensName, forKey: .lensName)
        try container.encode(lensColorFilter, forKey: .lensColorFilter)
        try container.encode(lensNdFilter, forKey: .lensNdFilter)
        try container.encode(lensFocalLength, forKey: .lensFocalLength)
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
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(lightMeterImage, forKey: .lightMeterImage)
        try container.encode(isLocked, forKey: .isLocked)
    }
}

extension ModelContext {
    func safelyDelete(_ gallery: Gallery) {
        gallery.cleanup(context: self)
        self.delete(gallery)
    }
    
    func safelyDelete(_ roll: Roll) {
        roll.cleanup(context: self)
        self.delete(roll)
    }
    
    func safelyDelete(_ shot: Shot) {
        shot.cleanup(context: self)
        self.delete(shot)
    }

}
