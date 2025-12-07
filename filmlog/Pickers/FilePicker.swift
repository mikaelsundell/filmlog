// DEBUG ENHANCED FILE PICKER
// Copyright (c) 2025

import SwiftUI
import UniformTypeIdentifiers

struct FilePicker: UIViewControllerRepresentable {
    let kind: SharedStorageKind
    let allowsMultiple: Bool
    let onPick: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: kind.contentTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = allowsMultiple
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {

        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }
        
        private func prepareURL(_ url: URL, completion: @escaping (URL?) -> Void) {
            if url.path.contains("-Inbox/") {
                completion(url)
                return
            }
            
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

            let status = value as? String ?? "unknown"
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

                    let s = (newStatus as? String) ?? "unknown"
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

extension SharedStorageKind {
    var contentTypes: [UTType] {
        switch self {
        case .ar:
            return [.realityFile, .usd, .sceneKitScene]
        case .image:
            return [.image]
        case .text:
            return [.plainText, .json, .xml, .rtf, .html]
        case .other:
            return [.item]
        }
    }
}
