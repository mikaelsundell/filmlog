// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import AppKit
import SwiftUI

struct ContentView: View {
    @State private var inputImage: NSImage?
    @State private var inputImageURL: URL?
    @State private var aiOutput = "Drop an image on the left to test the AI service.\n\nThe service response will be shown here."
    @State private var isAnalyzing = false

    private let analysisService = AIAnalysisService()

    var body: some View {
        HSplitView {
            leftPanel
                .frame(minWidth: 360, idealWidth: 520)

            rightPanel
                .frame(minWidth: 420, idealWidth: 620)
        }
        .frame(minWidth: 1000, minHeight: 640)
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader(
                title: "Image Input",
                subtitle: "Drag and drop an image for analysis."
            )

            ImageDropView(
                image: $inputImage,
                imageURL: $inputImageURL,
                onImageDropped: analyzeImage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader(
                title: "AI Output",
                subtitle: isAnalyzing ? "Analyzing image..." : "AI service response."
            )

            ZStack(alignment: .topTrailing) {
                ScrollView {
                    MarkdownOutputView(text: aiOutput)
                        .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))

                if isAnalyzing {
                    ProgressView()
                        .padding(16)
                }
            }
        }
    }

    private func analyzeImage(_ image: NSImage) {
        isAnalyzing = true
        aiOutput = "Analyzing image..."

        Task {
            do {
                let analysis = try await analysisService.analyze(image: image)

                await MainActor.run {
                    aiOutput = analysis
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    aiOutput = "Analysis failed:\n\n\(error.localizedDescription)"
                    isAnalyzing = false
                }
            }
        }
    }

    private func panelHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial)
    }
}

private struct MarkdownOutputView: View {
    let text: String

    private var lines: [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                markdownLine(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func markdownLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            Spacer()
                .frame(height: 6)
        }
        else if trimmed.hasPrefix("# ") {
            Text(clean(trimmed, prefix: "# "))
                .font(.title2.bold())
                .padding(.bottom, 4)
        }
        else if trimmed.hasPrefix("## ") {
            Text(clean(trimmed, prefix: "## "))
                .font(.headline.bold())
                .padding(.top, 12)
                .padding(.bottom, 2)
        }
        else if trimmed.hasPrefix("### ") {
            Text(clean(trimmed, prefix: "### "))
                .font(.subheadline.bold())
                .padding(.top, 6)
        }
        else if trimmed.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                Text(inlineMarkdown(clean(trimmed, prefix: "- ")))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.body)
        }
        else {
            Text(inlineMarkdown(trimmed))
                .font(.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func clean(_ text: String, prefix: String) -> String {
        String(text.dropFirst(prefix.count))
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }

        return AttributedString(text)
    }
}

#Preview {
    ContentView()
}
