// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AppDataStats {
    var rolls: Int
    var shots: Int
    var galleries: Int
    var categories: Int
    var images: Int
    var totalSize: Int
}

struct SharedContainerStats {
    let path: String
    let imageCount: Int
    let jsonCount: Int
    let totalSize: UInt64
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var appDataStats: AppDataStats? = nil
    @State private var sharedContainerStats: SharedContainerStats?
    @State private var rolls: [Roll] = []
    @State private var galleries: [Gallery] = []
    @State private var showFileImporter = false
    @State private var showFileExporter = false
    @State private var exportData: Data? = nil
    @State private var importError: String? = nil
    @State private var exportError: String? = nil
    @State private var restoreSuccess: String? = nil
    @State private var backupSuccess: String? = nil

    var body: some View {
        Form {
            Section(header: Text("Application Data")) {
                VStack(alignment: .leading, spacing: 12) {
                    if let stats = appDataStats {
                        HStack {
                            Text("Rolls")
                            Spacer()
                            Text("\(stats.rolls)")
                        }
                        HStack {
                            Text("Shots")
                            Spacer()
                            Text("\(stats.shots)")
                        }
                        HStack {
                            Text("Galleries")
                            Spacer()
                            Text("\(stats.galleries)")
                        }
                        HStack {
                            Text("Categories")
                            Spacer()
                            Text("\(stats.categories)")
                        }
                        HStack {
                            Text("Total Images")
                            Spacer()
                            Text("\(stats.images)")
                        }
                        HStack {
                            Text("Total Size")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(stats.totalSize), countStyle: .file))
                        }
                    } else {
                        Text("App data stats not available")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .onAppear {
                    calculateAppDataStats()
                }
            }
            
            Section(header: Text("Shared Container")) {
                VStack(alignment: .leading, spacing: 12) {
                    if let stats = sharedContainerStats {
                        HStack {
                            Text("Image Files")
                            Spacer()
                            Text("\(stats.imageCount)")
                                .foregroundColor(.primary)
                        }
                        HStack {
                            Text("JSON Files")
                            Spacer()
                            Text("\(stats.jsonCount)")
                                .foregroundColor(.primary)
                        }
                        HStack {
                            Text("Total Size")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(stats.totalSize), countStyle: .file))
                                .foregroundColor(.primary)
                        }
                        Text("Path: \(stats.path)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            deleteSharedContainerFiles()
                        } label: {
                            Text("Delete files")
                                .foregroundColor(.red)
                        }
                        .padding(.top, 8)
                    } else {
                        Text("Shared container data not available")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .onAppear {
                    calculateSharedContainerStats()
                }
            }
            
            Section(header: Text("Backup Management")) {
                Button("Backup data to JSON") {
                    backupData()
                }
                .fileExporter(
                    isPresented: $showFileExporter,
                    document: JSONFile(data: exportData ?? Data()),
                    contentType: .json,
                    defaultFilename: backupFilename()
                ) { result in
                    switch result {
                    case .success(let url):
                        backupSuccess = "Backup saved to:\n\(url.lastPathComponent)"
                    case .failure(let error):
                        exportError = "Backup failed: \(error.localizedDescription)"
                    }
                }
                
                Button("Restore data from JSON") {
                    showFileImporter = true
                }
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.json]
                ) { result in
                    switch result {
                    case .success(let url):
                        restoreData(from: url)
                        if importError == nil {
                            restoreSuccess = "Restored data from:\n\(url.lastPathComponent)"
                        }
                    case .failure(let error):
                        importError = "Restore failed: \(error.localizedDescription)"
                    }
                }
            }
        }
        .alert("Restore error", isPresented: .constant(importError != nil)) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "Unknown error")
        }
        .alert("Restore complete", isPresented: Binding(
            get: { restoreSuccess != nil },
            set: { if !$0 { restoreSuccess = nil } }
        )) {
            Button("OK", role: .cancel) { restoreSuccess = nil }
        } message: {
            Text(restoreSuccess ?? "")
        }
        .alert("Backup error", isPresented: .constant(exportError != nil)) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Unknown error")
        }
        .alert("Backup complete", isPresented: Binding(
            get: { backupSuccess != nil },
            set: { if !$0 { backupSuccess = nil } }
        )) {
            Button("OK", role: .cancel) { backupSuccess = nil }
        } message: {
            Text(backupSuccess ?? "")
        }
        .navigationTitle("Settings")
        .onAppear {
            fetchRolls()
            fetchGalleries()
        }
    }
    
    private func calculateAppDataStats() {
        var rollCount = 0;
        var shotCount = 0;
        var imageCount = 0;
        var galleryCount = 0;
        var categoryCount = 0;
        var totalImageSize = 0
        
        for roll in rolls {
            rollCount += roll.shots.count
            if let img = roll.image {
                imageCount += 1
                totalImageSize += img.data.count
            }
            for shot in roll.shots {
                shotCount += 1
                if let img = shot.photoImage {
                    imageCount += 1
                    totalImageSize += img.data.count
                }
                if let img = shot.lightMeterImage {
                    imageCount += 1
                    totalImageSize += img.data.count
                }
            }
        }
    
        for gallery in galleries {
            galleryCount += 1
            for image in gallery.images {
                imageCount += 1
                totalImageSize += image.data.count
            }
            for _ in gallery.categories {
                categoryCount += 1
            }
        }
        
        appDataStats = AppDataStats(
            rolls: rolls.count,
            shots: shotCount,
            galleries: galleryCount,
            categories: categoryCount,
            images: imageCount,
            totalSize: totalImageSize
        )
    }
    
    private func calculateSharedContainerStats() {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.mikaelsundell.filmlog") else {
            return
        }
        
        do {
            let files = try fileManager.contentsOfDirectory(
                at: containerURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )

            let fileURLs = files.filter {
                ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false)
                && $0.lastPathComponent.lowercased().hasPrefix("shared_")
            }
            
            var totalSize: UInt64 = 0
            var imageCount = 0
            var jsonCount = 0
            
            for file in fileURLs {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                if let fileSize = attributes[.size] as? UInt64 {
                    totalSize += fileSize
                }
                
                let ext = file.pathExtension.lowercased()
                if ["jpg", "jpeg", "png"].contains(ext) {
                    imageCount += 1
                } else if ext == "json" {
                    jsonCount += 1
                }
            }
            
            sharedContainerStats = SharedContainerStats(
                path: containerURL.path,
                imageCount: imageCount,
                jsonCount: jsonCount,
                totalSize: totalSize
            )
            
        } catch {
            print("failed to read shared container: \(error)")
        }
    }
    
    private func deleteSharedContainerFiles() {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.mikaelsundell.filmlog") else {
            return
        }
        
        do {
            let files = try fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let removableFiles = files.filter {
                let ext = $0.pathExtension.lowercased()
                return ["jpg", "json"].contains(ext)
            }
            for file in removableFiles {
                try fileManager.removeItem(at: file)
            }
            calculateSharedContainerStats()
            
        } catch {
            print("failed to delete files: \(error)")
        }
    }

    private func backupFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "filmlog_backup_\(formatter.string(from: Date())).json"
    }

    private func fetchRolls() {
        let descriptor = FetchDescriptor<Roll>()
        rolls = (try? modelContext.fetch(descriptor)) ?? []
    }
    
    private func fetchGalleries() {
        let descriptor = FetchDescriptor<Gallery>()
        galleries = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func backupData() {
        do {
            var imageMap: [UUID: ImageData] = [:]
            var shotMap: [UUID: Shot] = [:]
            var categoryMap: [UUID: Category] = [:]
            
            for roll in rolls {
                if let img = roll.image { imageMap[img.id] = img }
                
                for shot in roll.shots {
                    shotMap[shot.id] = shot
                    if let img = shot.photoImage { imageMap[img.id] = img }
                    if let img = shot.lightMeterImage { imageMap[img.id] = img }
                }
            }

            for gallery in galleries {
                for category in gallery.categories {
                    categoryMap[category.id] = category
                }
                for img in gallery.images {
                    imageMap[img.id] = img
                }
            }
            
            let exportImages = imageMap.values
                .sorted(by: { $0.timestamp < $1.timestamp })
                .map {
                    ImageDataExport(
                        id: $0.id,
                        timestamp: $0.timestamp,
                        data: $0.data.base64EncodedString(),
                        creator: $0.creator,
                        category: $0.category?.id
                    )
                }

            let exportShots = shotMap.values
                .sorted(by: { $0.timestamp < $1.timestamp })
                .map { shot in
                    ShotExport(
                    id: shot.id,
                    timestamp: shot.timestamp,
                    filmSize: shot.filmSize,
                    aspectRatio: shot.aspectRatio,
                    name: shot.name,
                    note: shot.note,
                    location: shot.location,
                    elevation: shot.elevation,
                    colorTemperature: shot.colorTemperature,
                    fstop: shot.fstop,
                    shutter: shot.shutter,
                    exposureCompensation: shot.exposureCompensation,
                    lensName: shot.lensName,
                    lensFocalLength: shot.lensFocalLength,
                    focusDistance: shot.focusDistance,
                    focusDepthOfField: shot.focusDepthOfField,
                    focusNearLimit: shot.focusNearLimit,
                    focusFarLimit: shot.focusFarLimit,
                    focusHyperfocalDistance: shot.focusHyperfocalDistance,
                    exposureSky: shot.exposureSky,
                    exposureFoliage: shot.exposureFoliage,
                    exposureHighlights: shot.exposureHighlights,
                    exposureMidGray: shot.exposureMidGray,
                    exposureShadows: shot.exposureShadows,
                    exposureSkinKey: shot.exposureSkinKey,
                    exposureSkinFill: shot.exposureSkinFill,
                    photoImage: shot.photoImage?.id,
                    lightMeterImage: shot.lightMeterImage?.id,
                    isLocked: shot.isLocked
                )
            }
            
            let exportRolls = rolls
                .sorted(by: { $0.timestamp < $1.timestamp })
                .map { roll in
                    RollExport(
                    id: roll.id,
                    timestamp: roll.timestamp,
                    name: roll.name,
                    note: roll.note,
                    status: roll.status,
                    camera: roll.camera,
                    counter: roll.counter,
                    pushPull: roll.pushPull,
                    filmDate: roll.filmDate,
                    filmSize: roll.filmSize,
                    filmStock: roll.filmStock,
                    isLocked: roll.isLocked,
                    image: roll.image?.id,
                    shots: roll.shots.map { $0.id }
                )
            }
            
            let exportGalleries = galleries
                .sorted(by: { $0.timestamp < $1.timestamp })
                .map { gallery in
                GalleryExport(
                    id: gallery.id,
                    timestamp: gallery.timestamp,
                    categories: gallery.categories.map { $0.id },
                    images: gallery.images.map { $0.id }
                )
            }
            
            let exportCategories = categoryMap.values
                .sorted(by: { $0.timestamp < $1.timestamp })
                .map { CategoryExport(id: $0.id, name: $0.name)
            }
            
            let backup = BackupData(
                images: exportImages,
                rolls: exportRolls,
                shots: exportShots,
                galleries: exportGalleries,
                categories: exportCategories
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            exportData = try encoder.encode(backup)
            showFileExporter = true
            
        } catch {
            backupSuccess = nil
            exportError = "Failed to encode backup: \(error.localizedDescription)"
        }
    }
    
    private func readFile(from url: URL) throws -> Data {
        guard url.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "iCloud", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't access file"])
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try Data(contentsOf: url)
    }

    private func restoreData(from url: URL) {
        do {
            let data = try readFile(from: url)
            let decoder = JSONDecoder()
            let backup = try decoder.decode(BackupData.self, from: data)
            
            for roll in rolls { modelContext.delete(roll) }
            for gallery in galleries { modelContext.delete(gallery) }
            
            var categoryMap: [UUID: Category] = [:]
            var imageMap: [UUID: ImageData] = [:]
            var shotMap: [UUID: Shot] = [:]
            
            for categoryExport in backup.categories {
                let category = Category(name: categoryExport.name)
                category.id = categoryExport.id
                categoryMap[category.id] = category
            }
            
            for imgExport in backup.images {
                if let imgData = Data(base64Encoded: imgExport.data) {
                    let img = ImageData(data: imgData)
                    img.id = imgExport.id
                    img.creator = imgExport.creator
                    img.timestamp = imgExport.timestamp
                    if let categoryId = imgExport.category {
                        img.category = categoryMap[categoryId]
                    }
                    imageMap[img.id] = img
                }
            }
            
            for shotExport in backup.shots.sorted(by: { $0.timestamp < $1.timestamp }) {
                let shot = Shot()
                shot.id = shotExport.id
                shot.timestamp = shotExport.timestamp
                shot.filmSize = shotExport.filmSize
                shot.aspectRatio = shotExport.aspectRatio
                shot.name = shotExport.name
                shot.note = shotExport.note
                shot.location = shotExport.location
                shot.elevation = shotExport.elevation
                shot.colorTemperature = shotExport.colorTemperature
                shot.fstop = shotExport.fstop
                shot.shutter = shotExport.shutter
                shot.exposureCompensation = shotExport.exposureCompensation
                shot.lensName = shotExport.lensName
                shot.lensFocalLength = shotExport.lensFocalLength
                shot.focusDistance = shotExport.focusDistance
                shot.focusDepthOfField = shotExport.focusDepthOfField
                shot.focusNearLimit = shotExport.focusNearLimit
                shot.focusFarLimit = shotExport.focusFarLimit
                shot.focusHyperfocalDistance = shotExport.focusHyperfocalDistance
                shot.exposureSky = shotExport.exposureSky
                shot.exposureFoliage = shotExport.exposureFoliage
                shot.exposureHighlights = shotExport.exposureHighlights
                shot.exposureMidGray = shotExport.exposureMidGray
                shot.exposureShadows = shotExport.exposureShadows
                shot.exposureSkinKey = shotExport.exposureSkinKey
                shot.exposureSkinFill = shotExport.exposureSkinFill
                shot.photoImage = shotExport.photoImage.flatMap { imageMap[$0] }
                shot.lightMeterImage = shotExport.lightMeterImage.flatMap { imageMap[$0] }
                shot.isLocked = shotExport.isLocked

                shotMap[shot.id] = shot
            }
            
            for rollExport in backup.rolls.sorted(by: { $0.timestamp < $1.timestamp }) {
                let roll = Roll()
                roll.id = rollExport.id
                roll.timestamp = rollExport.timestamp
                roll.name = rollExport.name
                roll.note = rollExport.note
                roll.status = rollExport.status
                roll.camera = rollExport.camera
                roll.counter = rollExport.counter
                roll.pushPull = rollExport.pushPull
                roll.filmDate = rollExport.filmDate
                roll.filmSize = rollExport.filmSize
                roll.filmStock = rollExport.filmStock
                roll.isLocked = rollExport.isLocked
                roll.image = rollExport.image.flatMap { imageMap[$0] }
                for shotId in rollExport.shots {
                    if let shot = shotMap[shotId] {
                        roll.shots.append(shot)
                    }
                }
                modelContext.insert(roll)
            }

            for galleryExport in backup.galleries.sorted(by: { $0.timestamp < $1.timestamp }) {
                let gallery = Gallery()
                gallery.id = galleryExport.id
                gallery.timestamp = galleryExport.timestamp
                
                for categoryId in galleryExport.categories {
                    if let category = categoryMap[categoryId] {
                        gallery.categories.append(category)
                    }
                }
                
                for imageId in galleryExport.images {
                    if let img = imageMap[imageId] {
                        gallery.images.append(img)
                    }
                }
                
                modelContext.insert(gallery)
            }
            
            try modelContext.save()
            fetchRolls()
            fetchGalleries()
            calculateAppDataStats()
            
            restoreSuccess = "Successfully restored \(backup.rolls.count) rolls and \(backup.images.count) images."
        } catch {
            restoreSuccess = nil
            importError = "Failed to restore rolls: \(error.localizedDescription)"
        }
    }
}

struct BackupData: Codable {
    var images: [ImageDataExport]
    var rolls: [RollExport]
    var shots: [ShotExport]
    var galleries: [GalleryExport]
    var categories: [CategoryExport]
}

struct ImageDataExport: Codable {
    var id: UUID
    var timestamp: Date
    var data: String
    var creator: String?
    var category: UUID?
}

struct RollExport: Codable {
    var id: UUID
    var timestamp: Date
    var name: String
    var note: String
    var status: String
    var camera: String
    var counter: Int
    var pushPull: String
    var filmDate: Date
    var filmSize: String
    var filmStock: String
    var isLocked: Bool
    var image: UUID?
    var shots: [UUID]
}

struct ShotExport: Codable {
    var id: UUID
    var timestamp: Date
    var filmSize: String
    var aspectRatio: String
    var name: String
    var note: String
    var location: LocationOptions.Location?
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
    var exposureSky: String
    var exposureFoliage: String
    var exposureHighlights: String
    var exposureMidGray: String
    var exposureShadows: String
    var exposureSkinKey: String
    var exposureSkinFill: String
    var photoImage: UUID?
    var lightMeterImage: UUID?
    var isLocked: Bool
}

struct GalleryExport: Codable {
    var id: UUID
    var timestamp: Date
    var categories: [UUID]
    var images: [UUID]
}

struct CategoryExport: Codable {
    var id: UUID
    var name: String
}

struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return .init(regularFileWithContents: data)
    }
}
