// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import SwiftUI
import QuickLookThumbnailing

class LocalStorageFile: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let created: Date
    let modified: Date
    let fileSize: Int64
    let fileExtension: String
    let kind: LocalStorageKind
    
    @Published var thumbnail: UIImage? = nil
    
    init?(url: URL, kind: LocalStorageKind) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        
        self.url = url
        self.name = url.lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
        self.kind = kind
        
        self.created = attrs[.creationDate] as? Date ?? .distantPast
        self.modified = attrs[.modificationDate] as? Date ?? .distantPast
        self.fileSize = attrs[.size] as? Int64 ?? 0

        generateThumbnail()
    }
    
    func generateThumbnail() {
        let size = CGSize(width: 256, height: 256)
        let scale = UIScreen.main.scale
        
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, err in
            DispatchQueue.main.async {
                self.thumbnail = rep?.uiImage
            }
        }
    }
}

enum LocalStorageKind: String, CaseIterable, Identifiable {
    case ar
    case image
    case text
    case other
    
    var id: String { rawValue }
    
    var folderName: String {
        switch self {
        case .ar: return "AR"
        case .image: return "Images"
        case .text: return "Text"
        case .other: return "Other"
        }
    }
    
    var supportedExtensions: [String] {
        switch self {
        case .ar:
            return ["usdz", "reality", "scn"]
            
        case .image:
            return ["jpg", "jpeg", "png", "heic", "tiff"]
            
        case .text:
            return ["txt", "md", "rtf", "json", "xml", "html"]
            
        case .other:
            return []
        }
    }
}

func localStorageDirectory(for kind: LocalStorageKind) -> URL {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("LocalStorage")
    let dir = base.appendingPathComponent(kind.folderName, isDirectory: true)
    
    if !FileManager.default.fileExists(atPath: dir.path) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
}

func loadLocalStorageFiles(kind: LocalStorageKind) -> [LocalStorageFile] {
    let fm = FileManager.default
    let dir = localStorageDirectory(for: kind)
    
    print("Local Storage dir: \(dir)")
    
    let allowed = kind.supportedExtensions.map { $0.lowercased() }
    
    guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
        return []
    }
    
    if kind == .other {
        return files.compactMap { url in
            LocalStorageFile(url: url, kind: .other)
        }
        .sorted { $0.modified > $1.modified }
    }
    
    return files
        .filter { allowed.contains($0.pathExtension.lowercased()) }
        .compactMap { LocalStorageFile(url: $0, kind: kind) }
        .sorted { $0.modified > $1.modified }
}

@discardableResult
func saveToLocalStorageDirectory(_ sourceURL: URL, as kind: LocalStorageKind) -> URL? {
    let fm = FileManager.default
    let destDir = localStorageDirectory(for: kind)
    let destURL = destDir.appendingPathComponent(sourceURL.lastPathComponent)
    
    let access = sourceURL.startAccessingSecurityScopedResource()
    defer {
        if access { sourceURL.stopAccessingSecurityScopedResource() }
    }

    do {
        if try sourceURL.checkResourceIsReachable() == false {
            try fm.startDownloadingUbiquitousItem(at: sourceURL)
        }

        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }

        try fm.copyItem(at: sourceURL, to: destURL)

        print("[LocalStorage] Saved \(sourceURL.lastPathComponent) → \(destURL.path)")
        return destURL

    } catch {
        print("[LocalStorage] Error saving \(sourceURL.lastPathComponent): \(error)")
        return nil
    }
}
