// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import AppKit
import SwiftUI

struct ContentView: View {
    @State private var inputImage: NSImage?
    @State private var inputImageURL: URL?
    @State private var analysisMode: AIAnalysisService.AnalysisMode = .imageCritique
    @State private var aiOutput = "Drop an image on the left to test the AI service.\n\nThe service response will be shown here."
    @State private var isAnalyzing = false
    @State private var didCopyRaw = false

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
            outputHeader

            ZStack(alignment: .topTrailing) {
                ScrollView {
                    MarkdownOutputView(text: aiOutput)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
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

    private var outputHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Output")
                    .font(.headline)

                Text(isAnalyzing ? "Analyzing image..." : analysisMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Mode", selection: $analysisMode) {
                ForEach(AIAnalysisService.AnalysisMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 220)
            .disabled(isAnalyzing)

            Button {
                if let inputImage {
                    analyzeImage(inputImage)
                }
            } label: {
                Label("Analyze", systemImage: "sparkles")
            }
            .disabled(inputImage == nil || isAnalyzing)

            Button {
                copyRawResponse()
            } label: {
                Label(
                    didCopyRaw ? "Copied" : "Copy Raw",
                    systemImage: didCopyRaw ? "checkmark" : "doc.on.doc"
                )
            }
            .disabled(aiOutput.isEmpty || isAnalyzing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private func analyzeImage(_ image: NSImage) {
        isAnalyzing = true
        didCopyRaw = false
        aiOutput = "Analyzing image..."

        let mode = analysisMode

        Task {
            do {
                let analysis = try await analysisService.analyze(
                    image: image,
                    mode: mode
                )

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

    private func copyRawResponse() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(aiOutput, forType: .string)

        didCopyRaw = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopyRaw = false
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

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(font(forHeadingLevel: level))
                .padding(.top, topPadding(forHeadingLevel: level))
                .padding(.bottom, bottomPadding(forHeadingLevel: level))
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.body)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)

        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.body)

                Text(inlineMarkdown(text))
                    .font(.body)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 1)

        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(.headline.bold())

                Text(inlineMarkdown(text))
                    .font(.headline.bold())
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .padding(.bottom, 2)

        case .quote(let text):
            Text(inlineMarkdown(text))
                .font(.body.italic())
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .padding(.leading, 12)
                .padding(.vertical, 2)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 3)
                }

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .spacer:
            Spacer()
                .frame(height: 2)
        }
    }

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(inlineMarkdown(header))
                        .font(.body.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 6)

            Divider()

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(normalizedRow(row, columnCount: headers.count).enumerated()), id: \.offset) { _, value in
                        Text(inlineMarkdown(value))
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 6)

                Divider()
            }
        }
        .padding(.vertical, 6)
    }

    private func normalizedRow(_ row: [String], columnCount: Int) -> [String] {
        if row.count == columnCount {
            return row
        }

        if row.count > columnCount {
            return Array(row.prefix(columnCount))
        }

        return row + Array(repeating: "", count: max(0, columnCount - row.count))
    }

    private func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1:
            return .title2.bold()
        case 2:
            return .title3.bold()
        case 3:
            return .headline.bold()
        case 4:
            return .subheadline.bold()
        default:
            return .body.bold()
        }
    }

    private func topPadding(forHeadingLevel level: Int) -> CGFloat {
        switch level {
        case 1:
            return 8
        case 2:
            return 12
        case 3:
            return 8
        case 4:
            return 4
        default:
            return 3
        }
    }

    private func bottomPadding(forHeadingLevel level: Int) -> CGFloat {
        switch level {
        case 1:
            return 3
        case 2:
            return 2
        case 3:
            return 1
        default:
            return 0
        }
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

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(number: Int, text: String)
    case quote(String)
    case table(headers: [String], rows: [[String]])
    case spacer
}

private enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else {
                return
            }

            let paragraph = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")

            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
            }

            paragraphLines.removeAll()
        }

        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()

                if blocks.last.map({ !isSpacer($0) }) ?? true {
                    blocks.append(.spacer)
                }

                index += 1
                continue
            }

            if isTableLine(line) {
                flushParagraph()

                let tableLines = collectTableLines(from: lines, startingAt: index)
                blocks.append(parseTable(tableLines))
                index += tableLines.count
                continue
            }

            if let heading = parseHeading(line) {
                flushParagraph()
                blocks.append(heading)
                index += 1
                continue
            }

            if let numbered = parseNumbered(line) {
                flushParagraph()
                blocks.append(numbered)
                index += 1
                continue
            }

            if let bullet = parseBullet(line) {
                flushParagraph()
                blocks.append(bullet)
                index += 1
                continue
            }

            if line.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                index += 1
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()

        while blocks.last.map({ isSpacer($0) }) == true {
            blocks.removeLast()
        }

        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let level = line.prefix(while: { $0 == "#" }).count

        guard level > 0, level <= 6 else {
            return nil
        }

        let index = line.index(line.startIndex, offsetBy: level)

        guard index < line.endIndex, line[index] == " " else {
            return nil
        }

        let text = String(line[line.index(after: index)...])
            .trimmingCharacters(in: .whitespaces)

        return .heading(level: level, text: text)
    }

    private static func parseBullet(_ line: String) -> MarkdownBlock? {
        if line.hasPrefix("- ") {
            return .bullet(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }

        if line.hasPrefix("* ") {
            return .bullet(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }

        return nil
    }

    private static func parseNumbered(_ line: String) -> MarkdownBlock? {
        guard let dotIndex = line.firstIndex(of: ".") else {
            return nil
        }

        let numberText = String(line[..<dotIndex])

        guard let number = Int(numberText) else {
            return nil
        }

        let afterDot = line.index(after: dotIndex)

        guard afterDot < line.endIndex, line[afterDot] == " " else {
            return nil
        }

        let textStart = line.index(after: afterDot)
        let text = String(line[textStart...])
            .trimmingCharacters(in: .whitespaces)

        return .numbered(number: number, text: text)
    }

    private static func isTableLine(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|")
    }

    private static func collectTableLines(from lines: [String], startingAt index: Int) -> [String] {
        var result: [String] = []
        var current = index

        while current < lines.count {
            let line = lines[current].trimmingCharacters(in: .whitespaces)

            guard isTableLine(line) else {
                break
            }

            result.append(line)
            current += 1
        }

        return result
    }

    private static func parseTable(_ lines: [String]) -> MarkdownBlock {
        guard let headerLine = lines.first else {
            return .table(headers: [], rows: [])
        }

        let headers = splitTableRow(headerLine)

        let rows = lines
            .dropFirst()
            .filter { !isTableSeparator($0) }
            .map(splitTableRow)

        return .table(headers: headers, rows: rows)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        line
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let stripped = line
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)

        return stripped.isEmpty
    }

    private static func isSpacer(_ block: MarkdownBlock) -> Bool {
        if case .spacer = block {
            return true
        }

        return false
    }
}

#Preview {
    ContentView()
}
