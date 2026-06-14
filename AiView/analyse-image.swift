// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import AppKit

struct AIAnalysisResponse: Decodable {
    let analysis: String
}

final class AIAnalysisService {
    private let endpoint = URL(string: "https://45kitmd9sh.execute-api.eu-north-1.amazonaws.com/analyze-image")!

    func analyze(image: NSImage) async throws -> String {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else {
            throw NSError(domain: "AIAnalysisService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode image."
            ])
        }

        let payload: [String: String] = [
            "mimeType": "image/jpeg",
            "imageBase64": jpegData.base64EncodedString()
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "AIAnalysisService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid server response."
            ])
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw NSError(domain: "AIAnalysisService", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        let decoded = try JSONDecoder().decode(AIAnalysisResponse.self, from: data)
        return decoded.analysis
    }
}
