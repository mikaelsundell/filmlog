// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
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
        
        func colorTemperature(for date: Date = Date(), timeZone: TimeZone = .current) -> Double {
            let elevationAngle = elevation(for: date, timeZone: timeZone)
            let clampedElevation = max(elevationAngle, 0.0)
            
            // empirical formula: 6500K at high sun, warmer when low
            // CCT = 2000K to 6500K approx
            // Formula: 2000 + (4500 * (clampedElevation / 60))
            // But to make it smoother, use an exponential approach
            let cct = 2000 + (4500 * (1.0 - exp(-0.045 * clampedElevation)))
            return cct
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

    
    static let aspectRatios: [(label: String, value: Double)] = [
        ("-", 0.0),
        ("1:0", 1.0),
        ("1.43", 1.43),
        ("1.77", 16.0 / 9.0),
        ("1.90", 1.90),
        ("3:2", 3.0 / 2.0),
        ("2.0", 2.0),
        ("2.35", 2.35),
        ("2.39", 2.39),
        ("2.55", 2.55),
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
    
    static let colorTemperatures: [Int] =
        [0,
         3200,
         4300,
         5000,
         5600,
         6500,
         500,
         9000];
    
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
    
    static let filmStocks: [String] = [
        "50D", 
        "250D",
        "200T",
        "500T",
        "Ektachrome",
        "Double X",
        "Other"
    ]
    
    static let focalLengths: [(label: String, value: Double)] = [
        ("19mm", 19),
        ("20mm", 20),
        ("24mm", 24),
        ("28mm", 28),
        ("35mm", 35),
        ("40mm", 40),
        ("50mm", 50),
        ("70mm", 70),
        ("80mm", 80),
        ("85mm", 85),
        ("105mm", 105),
        ("135mm", 135),
        ("200mm", 200),
        ("300mm", 300)
    ]

    static let fStops: [(label: String, value: Double)] = [
        ("f/1.4", 1.4),
        ("f/2", 2.0),
        ("f/2.8", 2.8),
        ("f/4", 4),
        ("f/5.6", 5.6),
        ("f/8", 8),
        ("f/11", 11),
        ("f/16", 16),
        ("f/22", 22)
    ]
    
    static let lensNames: [String] = [
         "-",
         "Canon FD",
         "Canon CN-E",
         "Nikon",
         "Leica R",
         "Other"
    ]
    
    static let shutterSpeeds: [(label: String, value: Double)] = [
        ("-", 0),
        ("1/1000", 1.0 / 1000),
        ("1/500", 1.0 / 500),
        ("1/250", 1.0 / 250),
        ("1/125", 1.0 / 125),
        ("1/60", 1.0 / 60),
        ("1/50", 1.0 / 50),
        ("1/30", 1.0 / 30),
        ("1/15", 1.0 / 15),
        ("1/8", 1.0 / 8),
        ("1/4", 1.0 / 4),
        ("1/2", 1.0 / 2),
        ("1", 1.0),
        ("2", 2.0),
        ("4", 4.0)
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
         filmStock: String = "50D",
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
    var aspectRatio: String
    var name: String
    var note: String
    var location: LocationOptions.Location?
    var locationTimestamp: Date?
    var elevation: Double
    var colorTemperature: Double
    var fstop: String
    var shutter: String
    var exposureCompensation: String
    var lensName: String
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
         aspectRatio: String = "-",
         name: String = "",
         note: String = "",
         location: LocationOptions.Location? = nil,
         locationTimestamp: Date? = nil,
         elevation: Double = 0.0,
         colorTemperature: Double = 0.0,
         fstop: String = "f/2.8",
         shutter: String = "1/125",
         exposureCompensation: String = "0",
         lensName: String = "Other",
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
        self.aspectRatio = aspectRatio
        self.name = name
        self.note = note
        self.location = location
        self.locationTimestamp = locationTimestamp
        self.elevation = elevation
        self.colorTemperature = colorTemperature
        self.fstop = fstop
        self.shutter = shutter
        self.exposureCompensation = exposureCompensation
        self.lensName = lensName
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
        newShot.aspectRatio = self.aspectRatio
        newShot.name = self.name
        newShot.note = self.note
        newShot.location = self.location
        newShot.locationTimestamp = self.locationTimestamp
        newShot.elevation = self.elevation
        newShot.colorTemperature = self.colorTemperature
        newShot.fstop = self.fstop
        newShot.shutter = self.shutter
        newShot.exposureCompensation = self.exposureCompensation
        newShot.lensName = self.lensName
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
        case id, timestamp, filmSize, aspectRatio, name, note, location, locationTimestamp, elevation,
             colorTemperature, fstop, shutter, exposureCompensation, lensName, lensFocalLength,
             focusDistance, focusDepthOfField, focusNearLimit, focusFarLimit, focusHyperfocalDistance,
             focusHyperfocalNearLimit, exposureSky, exposureFoliage, exposureHighlights, exposureMidGray,
             exposureShadows, exposureSkinKey, exposureSkinFill, image, lightMeterImage, isLocked
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        filmSize = try c.decode(String.self, forKey: .filmSize)
        aspectRatio = try c.decode(String.self, forKey: .aspectRatio)
        name = try c.decode(String.self, forKey: .name)
        note = try c.decode(String.self, forKey: .note)
        location = try c.decodeIfPresent(LocationOptions.Location.self, forKey: .location)
        locationTimestamp = try c.decodeIfPresent(Date.self, forKey: .locationTimestamp)
        elevation = try c.decode(Double.self, forKey: .elevation)
        colorTemperature = try c.decode(Double.self, forKey: .colorTemperature)
        fstop = try c.decode(String.self, forKey: .fstop)
        shutter = try c.decode(String.self, forKey: .shutter)
        exposureCompensation = try c.decode(String.self, forKey: .exposureCompensation)
        lensName = try c.decode(String.self, forKey: .lensName)
        lensFocalLength = try c.decode(String.self, forKey: .lensFocalLength)
        focusDistance = try c.decode(Double.self, forKey: .focusDistance)
        focusDepthOfField = try c.decode(Double.self, forKey: .focusDepthOfField)
        focusNearLimit = try c.decode(Double.self, forKey: .focusNearLimit)
        focusFarLimit = try c.decode(Double.self, forKey: .focusFarLimit)
        focusHyperfocalDistance = try c.decode(Double.self, forKey: .focusHyperfocalDistance)
        focusHyperfocalNearLimit = try c.decode(Double.self, forKey: .focusHyperfocalNearLimit)
        exposureSky = try c.decode(String.self, forKey: .exposureSky)
        exposureFoliage = try c.decode(String.self, forKey: .exposureFoliage)
        exposureHighlights = try c.decode(String.self, forKey: .exposureHighlights)
        exposureMidGray = try c.decode(String.self, forKey: .exposureMidGray)
        exposureShadows = try c.decode(String.self, forKey: .exposureShadows)
        exposureSkinKey = try c.decode(String.self, forKey: .exposureSkinKey)
        exposureSkinFill = try c.decode(String.self, forKey: .exposureSkinFill)
        image = try c.decodeIfPresent(ImageData.self, forKey: .image)
        lightMeterImage = try c.decodeIfPresent(ImageData.self, forKey: .lightMeterImage)
        isLocked = try c.decode(Bool.self, forKey: .isLocked)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(filmSize, forKey: .filmSize)
        try c.encode(aspectRatio, forKey: .aspectRatio)
        try c.encode(name, forKey: .name)
        try c.encode(note, forKey: .note)
        try c.encode(location, forKey: .location)
        try c.encode(locationTimestamp, forKey: .locationTimestamp)
        try c.encode(elevation, forKey: .elevation)
        try c.encode(colorTemperature, forKey: .colorTemperature)
        try c.encode(fstop, forKey: .fstop)
        try c.encode(shutter, forKey: .shutter)
        try c.encode(exposureCompensation, forKey: .exposureCompensation)
        try c.encode(lensName, forKey: .lensName)
        try c.encode(lensFocalLength, forKey: .lensFocalLength)
        try c.encode(focusDistance, forKey: .focusDistance)
        try c.encode(focusDepthOfField, forKey: .focusDepthOfField)
        try c.encode(focusNearLimit, forKey: .focusNearLimit)
        try c.encode(focusFarLimit, forKey: .focusFarLimit)
        try c.encode(focusHyperfocalDistance, forKey: .focusHyperfocalDistance)
        try c.encode(focusHyperfocalNearLimit, forKey: .focusHyperfocalNearLimit)
        try c.encode(exposureSky, forKey: .exposureSky)
        try c.encode(exposureFoliage, forKey: .exposureFoliage)
        try c.encode(exposureHighlights, forKey: .exposureHighlights)
        try c.encode(exposureMidGray, forKey: .exposureMidGray)
        try c.encode(exposureShadows, forKey: .exposureShadows)
        try c.encode(exposureSkinKey, forKey: .exposureSkinKey)
        try c.encode(exposureSkinFill, forKey: .exposureSkinFill)
        try c.encodeIfPresent(image, forKey: .image)
        try c.encodeIfPresent(lightMeterImage, forKey: .lightMeterImage)
        try c.encode(isLocked, forKey: .isLocked)
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
