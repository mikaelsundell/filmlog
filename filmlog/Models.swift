// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import SwiftData

struct LocationOptions {
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

struct CameraOptions {
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
        static let defaultFilmSize = CameraOptions.FilmSize(width: 36.0, height: 24.0)
    }
    
    struct AspectRatio: Equatable {
        let numerator: Int
        let denominator: Int

        var ratio: Double {
            return Double(numerator) / Double(denominator)
        }
        
        static let defaultAspectRatio = CameraOptions.AspectRatio(numerator: 0, denominator: 1)
    }
    
    struct FilmStock {
        let speed: Double
        let colorTemperature: Double
        
        static let defaultFilmStock = CameraOptions.FilmStock(speed: 100, colorTemperature: 5600)
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
        
        static let defaultAperture = CameraOptions.Aperture(fstop: 2.8)
    }
    
    struct Shutter: Equatable {
        let numerator: Int
        let denominator: Int

        var shutter: Double {
            return Double(numerator) / Double(denominator)
        }
        
        static let defaultShutter = CameraOptions.Shutter(numerator: 1, denominator: 125)
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
    ]
    
    static let filters: [(label: String, value: Filter)] = [
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
        ("82C", Filter(exposureCompensation: -0.3, colorTemperatureShift: +600)),
        ("ND 0.3", Filter(exposureCompensation: -1.0, colorTemperatureShift: 0)),
        ("ND 0.6", Filter(exposureCompensation: -2.0, colorTemperatureShift: 0)),
        ("ND 0.9", Filter(exposureCompensation: -3.0, colorTemperatureShift: 0)),
        ("PL", Filter(exposureCompensation: -1.0, colorTemperatureShift: 0))
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
        ("1/125", Shutter(numerator: 1, denominator: 125)),
        ("1/250", Shutter(numerator: 1, denominator: 250)),
        ("1/500", Shutter(numerator: 1, denominator: 500)),
        ("1/1000", Shutter(numerator: 1, denominator: 1000)),
        ("1", Shutter(numerator: 1, denominator: 1)),
        ("2", Shutter(numerator: 2, denominator: 1)),
        ("4", Shutter(numerator: 4, denominator: 1)),
    ]
}

@Model
class Category: Codable {
    var id = UUID()
    var timestamp = Date()
    var name: String
    
    init(name: String) {
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
    var data: Data
    var referenceCount: Int
    var name: String?
    var note: String?
    var creator: String?

    @Relationship var category: Category?

    init(data: Data, category: Category? = nil, name: String? = nil, note: String? = nil, creator: String? = nil) {
        self.data = data
        self.referenceCount = 1
        self.category = category
        self.name = name
        self.note = note
        self.creator = creator
    }

    enum CodingKeys: String, CodingKey {
        case id, data, referenceCount, category, name, note, creator, timestamp
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        data = try container.decode(Data.self, forKey: .data)
        referenceCount = try container.decodeIfPresent(Int.self, forKey: .referenceCount) ?? 1
        category = try container.decodeIfPresent(Category.self, forKey: .category)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        creator = try container.decodeIfPresent(String.self, forKey: .creator)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(data, forKey: .data)
        try container.encode(referenceCount, forKey: .referenceCount)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(creator, forKey: .creator)
    }

    func incrementReference() {
        referenceCount += 1
    }

    func decrementReference() -> Bool {
        referenceCount -= 1
        return referenceCount <= 0
    }
}


@Model
class Gallery: Codable {
    var id = UUID()
    var timestamp = Date()
    @Relationship var images: [ImageData] = []
    @Relationship var categories: [Category] = []

    var orderedCategories: [Category] {
        categories.sorted(by: { $0.timestamp < $1.timestamp })
    }

    var orderedImages: [ImageData] {
        images.sorted(by: { $0.timestamp < $1.timestamp })
    }
    
    init(images: [ImageData] = [], categories: [Category] = []) {
        self.images = images
        self.categories = categories
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, images, categories
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        images = try container.decodeIfPresent([ImageData].self, forKey: .images) ?? []
        categories = try container.decodeIfPresent([Category].self, forKey: .categories) ?? []
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

    @Relationship var image: ImageData?
    @Relationship var shots: [Shot] = []
    
    var orderedShots: [Shot] {
        shots.sorted(by: { $0.timestamp < $1.timestamp })
    }

    init(name: String = "",
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

    func updateImage(to newImage: ImageData?, context: ModelContext) {
        if let current = self.image {
            if current.decrementReference() {
                context.delete(current)
            }
            
        }
        if let newImage = newImage {
            newImage.incrementReference()
        }
        self.image = newImage
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
    var location: LocationOptions.Location?
    var locationTimestamp: Date?
    var locationColorTemperature: Int?
    var locationElevation: Double?
    var aperture: String
    var shutter: String
    var exposureCompensation: String
    var lensName: String
    var lensFilter: String
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

    @Relationship var image: ImageData?
    @Relationship var lightMeterImage: ImageData?

    init(filmSize: String = "",
         filmStock: String = "",
         aspectRatio: String = "-",
         name: String = "",
         note: String = "",
         location: LocationOptions.Location? = nil,
         locationTimestamp: Date? = nil,
         locationColorTemperature: Int? = 0,
         locationElevation: Double? = 0.0,
         aperture: String = "f/2.8",
         shutter: String = "1/125",
         exposureCompensation: String = "0",
         lensName: String = "Other",
         lensFilter: String = "-",
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
        self.lensFilter = lensFilter
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
        if let img = image, img.decrementReference() {
            context.delete(img)
        }
        if let meter = lightMeterImage, meter.decrementReference() {
            context.delete(meter)
        }
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
        newShot.lensFilter = self.lensFilter
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

    func updateImage(to newImage: ImageData?, context: ModelContext) {
        if let current = self.image {
            if current.decrementReference() {
                context.delete(current)
            }
        }
        if let newImage = newImage {
            newImage.incrementReference()
        }
        self.image = newImage
    }

    func updateLightMeterImage(to newImage: ImageData?, context: ModelContext) {
        if let current = self.lightMeterImage {
            if current.decrementReference() {
                context.delete(current)
            }
        }
        if let newImage = newImage {
            newImage.incrementReference()
        }
        self.lightMeterImage = newImage
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, filmSize, filmStock, aspectRatio, name, note, location, locationTimestamp, locationColorTemperature,
             locationElevation, aperture, shutter, exposureCompensation, lensName, lensFilter, lensFocalLength,
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
        location = try container.decodeIfPresent(LocationOptions.Location.self, forKey: .location)
        locationTimestamp = try container.decodeIfPresent(Date.self, forKey: .locationTimestamp)
        locationColorTemperature = try container.decode(Int.self, forKey: .locationColorTemperature)
        locationElevation = try container.decode(Double.self, forKey: .locationElevation)
        aperture = try container.decode(String.self, forKey: .aperture)
        shutter = try container.decode(String.self, forKey: .shutter)
        exposureCompensation = try container.decode(String.self, forKey: .exposureCompensation)
        lensName = try container.decode(String.self, forKey: .lensName)
        lensFilter = try container.decode(String.self, forKey: .lensFilter)
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
        try container.encode(lensFilter, forKey: .lensName)
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
    func safelyDelete(_ shot: Shot) {
        shot.cleanup(context: self)
        self.delete(shot)
    }
    
    func safelyDelete(_ roll: Roll) {
        roll.cleanup(context: self)
        self.delete(roll)
    }
}
