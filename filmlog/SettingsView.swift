// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var rolls: [Roll] = []
    @State private var showFileImporter = false
    @State private var showFileExporter = false
    @State private var exportData: Data? = nil
    @State private var importError: String? = nil
    @State private var exportError: String? = nil
    @State private var restoreSuccess: String? = nil
    @State private var backupSuccess: String? = nil
    
    var body: some View {
        Form {
            Section(header: Text("Data Management")) {
                Button("Backup rolls to JSON") {
                    backupRolls()
                }
                .fileExporter(
                    isPresented: $showFileExporter,
                    document: JSONFile(data: exportData ?? Data()),
                    contentType: .json,
                    defaultFilename: backupFilename()
                ) { result in
                    if case .failure(let error) = result {
                        exportError = "Backup failed: \(error.localizedDescription)"
                    }
                }
                
                Button("Restore rolls from JSON") {
                    showFileImporter = true
                }
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.json]
                ) { result in
                    switch result {
                    case .success(let url):
                        restoreRolls(from: url)
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
        .alert("Restore complete", isPresented: .constant(restoreSuccess != nil)) {
            Button("OK", role: .cancel) { restoreSuccess = nil }
        } message: {
            Text(restoreSuccess ?? "Successfully restored.")
        }
        .alert("Backup error", isPresented: .constant(exportError != nil)) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Unknown error")
        }
        .alert("Backup complete", isPresented: .constant(backupSuccess != nil)) {
            Button("OK", role: .cancel) { backupSuccess = nil }
        } message: {
            Text(backupSuccess ?? "")
        }
        .navigationTitle("Settings")
        .onAppear {
            fetchRolls()
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

    private func backupRolls() {
        do {
            var imageMap: [UUID: ImageData] = [:]
            for roll in rolls {
                if let img = roll.image { imageMap[img.id] = img }
                for frame in roll.frames {
                    if let img = frame.photoImage { imageMap[img.id] = img }
                    if let img = frame.lightMeterImage { imageMap[img.id] = img }
                }
            }
            
            let exportImages = imageMap.values.map {
                ImageDataExport(id: $0.id, data: $0.data.base64EncodedString())
            }
            
            let exportRolls = rolls.map { roll in
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
                    frames: roll.frames.map { frame in
                        FrameExport(
                            id: frame.id,
                            timestamp: frame.timestamp,
                            filmSize: frame.filmSize,
                            aspectRatio: frame.aspectRatio,
                            name: frame.name,
                            note: frame.note,
                            location: frame.location,
                            elevation: frame.elevation,
                            colorTemperature: frame.colorTemperature,
                            fstop: frame.fstop,
                            shutter: frame.shutter,
                            exposureCompensation: frame.exposureCompensation,
                            lensName: frame.lensName,
                            lensFocalLength: frame.lensFocalLength,
                            focusDistance: frame.focusDistance,
                            focusDepthOfField: frame.focusDepthOfField,
                            focusNearLimit: frame.focusNearLimit,
                            focusFarLimit: frame.focusFarLimit,
                            focusHyperfocalDistance: frame.focusHyperfocalDistance,
                            exposureSky: frame.exposureSky,
                            exposureFoliage: frame.exposureFoliage,
                            exposureHighlights: frame.exposureHighlights,
                            exposureMidGray: frame.exposureMidGray,
                            exposureShadows: frame.exposureShadows,
                            exposureSkinKey: frame.exposureSkinKey,
                            exposureSkinFill: frame.exposureSkinFill,
                            photoImage: frame.photoImage?.id,
                            lightMeterImage: frame.lightMeterImage?.id,
                            isLocked: frame.isLocked
                        )
                    }
                )
            }
            
            let backup = BackupData(images: exportImages, rolls: exportRolls)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            exportData = try encoder.encode(backup)
            
            showFileExporter = true
            backupSuccess = "Backup successful: \(exportRolls.count) rolls and \(exportImages.count) images."
        } catch {
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

    private func restoreRolls(from url: URL) {
        do {
            let data = try readFile(from: url)
            let decoder = JSONDecoder()
            let backup = try decoder.decode(BackupData.self, from: data)
            
            var imageMap: [UUID: ImageData] = [:]
            for imgExport in backup.images {
                if let imgData = Data(base64Encoded: imgExport.data) {
                    let img = ImageData(data: imgData)
                    img.id = imgExport.id
                    imageMap[imgExport.id] = img
                }
            }
            
            let existingRolls = try modelContext.fetch(FetchDescriptor<Roll>())
            for roll in existingRolls { modelContext.delete(roll) }
            
            for rollExport in backup.rolls {
                let roll = Roll(timestamp: rollExport.timestamp)
                roll.id = rollExport.id
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
                
                for frameExport in rollExport.frames {
                    let frame = Frame(timestamp: frameExport.timestamp)
                    frame.id = frameExport.id
                    frame.filmSize = frameExport.filmSize
                    frame.aspectRatio = frameExport.aspectRatio
                    frame.name = frameExport.name
                    frame.note = frameExport.note
                    frame.location = frameExport.location
                    frame.elevation = frameExport.elevation
                    frame.colorTemperature = frameExport.colorTemperature
                    frame.fstop = frameExport.fstop
                    frame.shutter = frameExport.shutter
                    frame.exposureCompensation = frameExport.exposureCompensation
                    frame.lensName = frameExport.lensName
                    frame.lensFocalLength = frameExport.lensFocalLength
                    frame.focusDistance = frameExport.focusDistance
                    frame.focusDepthOfField = frameExport.focusDepthOfField
                    frame.focusNearLimit = frameExport.focusNearLimit
                    frame.focusFarLimit = frameExport.focusFarLimit
                    frame.focusHyperfocalDistance = frameExport.focusHyperfocalDistance
                    frame.exposureSky = frameExport.exposureSky
                    frame.exposureFoliage = frameExport.exposureFoliage
                    frame.exposureHighlights = frameExport.exposureHighlights
                    frame.exposureMidGray = frameExport.exposureMidGray
                    frame.exposureShadows = frameExport.exposureShadows
                    frame.exposureSkinKey = frameExport.exposureSkinKey
                    frame.exposureSkinFill = frameExport.exposureSkinFill
                    frame.photoImage = frameExport.photoImage.flatMap { imageMap[$0] }
                    frame.lightMeterImage = frameExport.lightMeterImage.flatMap { imageMap[$0] }
                    frame.isLocked = frameExport.isLocked
                    roll.frames.append(frame)
                }
                
                modelContext.insert(roll)
            }
            
            try modelContext.save()
            restoreSuccess = "Successfully restored \(backup.rolls.count) rolls and \(backup.images.count) images."
        } catch {
            importError = "Failed to restore rolls: \(error.localizedDescription)"
        }
    }
}

struct BackupData: Codable {
    var images: [ImageDataExport]
    var rolls: [RollExport]
}

struct ImageDataExport: Codable {
    var id: UUID
    var data: String
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
    var frames: [FrameExport]
}

struct FrameExport: Codable {
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
