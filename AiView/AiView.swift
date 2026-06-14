// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageDropView: View {
    @Binding var image: NSImage?
    @Binding var imageURL: URL?

    var onImageDropped: (NSImage) -> Void = { _ in }

    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))

            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: image == nil ? [8, 6] : [])
                )

            if let image {
                VStack(spacing: 12) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)

                    if let imageURL {
                        Text(imageURL.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(.secondary)

                    Text("Drag and drop an image")
                        .font(.headline)

                    Text("The image will be sent to the AI analysis service.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
        }
        .padding(16)
        .onDrop(
            of: [UTType.fileURL.identifier, UTType.image.identifier],
            isTargeted: $isDropTargeted,
            perform: handleDrop
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = fileURL(from: item), let image = NSImage(contentsOf: url) else { return }
                setImage(image, url: url)
            }
            return true
        }

        if let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                setImage(image, url: nil)
            }
            return true
        }

        return false
    }

    private func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            return URL(string: string)
        }

        return nil
    }

    private func setImage(_ image: NSImage, url: URL?) {
        DispatchQueue.main.async {
            self.image = image
            self.imageURL = url
            self.onImageDropped(image)
        }
    }
}
