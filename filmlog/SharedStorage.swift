// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import SwiftUI
import QuickLookThumbnailing

// -------------------------------------------------------------
// MARK: - Shared Storage Kind
// -------------------------------------------------------------

enum SharedStorageKind: String, CaseIterable, Identifiable {
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
            return [] // no filtering
        }
    }
}

// -------------------------------------------------------------
// MARK: - Directory Helpers
// -------------------------------------------------------------

struct SharedStorage {
    static func directory(for kind: SharedStorageKind) -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedStorage", isDirectory: true)

        let dir = base.appendingPathComponent(kind.folderName, isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func clear(kind: SharedStorageKind) {
        let dir = directory(for: kind)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

// -------------------------------------------------------------
// MARK: - File Entry Model
// -------------------------------------------------------------

class SharedStorageFile: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let created: Date
    let modified: Date
    let fileSize: Int64
    let fileExtension: String
    let kind: SharedStorageKind

    @Published var thumbnail: UIImage?

    init?(url: URL, kind: SharedStorageKind) {
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

    // ---------------------------------------------------------
    // MARK: - Thumbnail Generation
    // ---------------------------------------------------------

    private func generateThumbnail() {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 256, height: 256),
            scale: UIScreen.main.scale,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, err in
            DispatchQueue.main.async {
                self.thumbnail = rep?.uiImage
            }
        }
    }
}

// -------------------------------------------------------------
// MARK: - Load Files for a Storage Kind
// -------------------------------------------------------------

func loadSharedStorageFiles(kind: SharedStorageKind) -> [SharedStorageFile] {
    let fm = FileManager.default
    let dir = SharedStorage.directory(for: kind)
    let allowed = kind.supportedExtensions.map { $0.lowercased() }

    guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
        return []
    }

    let filtered: [URL]

    if kind == .other {
        filtered = items // skip filtering
    } else {
        filtered = items.filter { allowed.contains($0.pathExtension.lowercased()) }
    }

    return filtered
        .compactMap { SharedStorageFile(url: $0, kind: kind) }
        .sorted { $0.modified > $1.modified }
}

// -------------------------------------------------------------
// MARK: - Save File to Shared Storage
// -------------------------------------------------------------

@discardableResult
func saveToSharedStorage(_ sourceURL: URL, as kind: SharedStorageKind) -> URL? {
    let fm = FileManager.default
    let destDir = SharedStorage.directory(for: kind)
    let destURL = destDir.appendingPathComponent(sourceURL.lastPathComponent)

    let hasAccess = sourceURL.startAccessingSecurityScopedResource()
    defer {
        if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
    }

    do {
        // Ensure reachable (iCloud files may need downloading)
        if try sourceURL.checkResourceIsReachable() == false {
            try fm.startDownloadingUbiquitousItem(at: sourceURL)
        }

        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }

        try fm.copyItem(at: sourceURL, to: destURL)
        return destURL

    } catch {
        print("❌ Failed to save to SharedStorage:", error)
        return nil
    }
}
