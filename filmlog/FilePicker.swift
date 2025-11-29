// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import UniformTypeIdentifiers

struct FilePicker: UIViewControllerRepresentable {
    let kind: LocalStorageKind
    let allowsMultiple: Bool
    let onPick: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = kind.contentTypes
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: types,
            asCopy: true
        )

        picker.allowsMultipleSelection = allowsMultiple
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ controller: UIDocumentPickerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        
        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }
        
        private func prepareURL(_ url: URL, completion: @escaping (URL?) -> Void) {
            guard url.startAccessingSecurityScopedResource() else {
                completion(nil)
                return
            }

            let nsurl = url as NSURL
            var value: AnyObject?

            try? nsurl.getResourceValue(
                &value,
                forKey: URLResourceKey.ubiquitousItemDownloadingStatusKey
            )

            let status = value as? String
            let isReady =
                status == URLUbiquitousItemDownloadingStatus.current.rawValue ||
                status == URLUbiquitousItemDownloadingStatus.downloaded.rawValue

            if isReady {
                completion(url)
                return
            }

            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            DispatchQueue.global().async {
                while true {
                    var newStatus: AnyObject?
                    try? nsurl.getResourceValue(
                        &newStatus,
                        forKey: URLResourceKey.ubiquitousItemDownloadingStatusKey
                    )

                    let s = newStatus as? String ?? ""

                    if s == URLUbiquitousItemDownloadingStatus.downloaded.rawValue ||
                        s == URLUbiquitousItemDownloadingStatus.current.rawValue {

                        DispatchQueue.main.async {
                            completion(url)
                        }
                        return
                    }

                    usleep(200_000)
                }
            }
        }
        
        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            var results: [URL] = []
            let group = DispatchGroup()
            
            for url in urls {
                group.enter()
                prepareURL(url) { readyURL in
                    if let readyURL = readyURL {
                        results.append(readyURL)
                    }
                    url.stopAccessingSecurityScopedResource()
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                self.onPick(results)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick([])
        }
    }
}

extension LocalStorageKind {
    var contentTypes: [UTType] {
        switch self {
        case .ar:
            return [
                .realityFile,
                .usd,
                .sceneKitScene
            ]
            
        case .image:
            return [.image]
            
        case .text:
            return [
                .plainText,
                .json,
                .xml,
                .rtf,
                .html
            ]
            
        case .other:
            return [.item]
        }
    }
}
