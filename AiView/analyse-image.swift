// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import Foundation
import AppKit

struct AIAnalysisResponse: Decodable {
    let analysis: String
}

final class AIAnalysisService {
    enum AnalysisMode: String, CaseIterable, Identifiable, Codable {
        case imageCritique
        case composition
        case storytelling

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .imageCritique:
                return "Image Critique"
            case .composition:
                return "Composition Analysis"
            case .storytelling:
                return "Storytelling Analysis"
            }
        }

        var description: String {
            switch self {
            case .imageCritique:
                return "Improvement-focused image critique."
            case .composition:
                return "Perception and storytelling composition read."
            case .storytelling:
                return "Intent, attention, fixation, composition, and validation mentor."
            }
        }
    }

    private let endpoint = URL(string: "https://45kitmd9sh.execute-api.eu-north-1.amazonaws.com/analyze-image")!

    func analyze(
        image: NSImage,
        mode: AnalysisMode = .imageCritique
    ) async throws -> String {
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
            "imageBase64": jpegData.base64EncodedString(),
            "mode": mode.rawValue
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