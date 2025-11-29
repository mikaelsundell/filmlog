// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI

struct ARPicker: View {
    @Binding var selectedModel: URL?
    @Environment(\.dismiss) private var dismiss
    
    @State private var filterText: String = ""
    @State private var showImporter = false
    @State private var localFiles: [LocalStorageFile] = []

    enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case created = "Created"
        case modified = "Last modified"
        var id: String { rawValue }
    }

    @State private var selectedSortRawValue = SortOption.modified.rawValue

    private var selectedSort: SortOption {
        get { SortOption(rawValue: selectedSortRawValue) ?? .modified }
        set { selectedSortRawValue = newValue.rawValue }
    }
    
    private func sortFiles(_ files: [LocalStorageFile], by option: SortOption) -> [LocalStorageFile] {
        switch option {
        case .name:
            return files.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .created:
            return files.sorted { $0.created > $1.created }
        case .modified:
            return files.sorted { $0.modified > $1.modified }
        }
    }

    private var filteredFiles: [LocalStorageFile] {
        let filtered = filterText.isEmpty
            ? localFiles
            : localFiles.filter { $0.name.localizedCaseInsensitiveContains(filterText) }

        return sortFiles(filtered, by: selectedSort)
    }
    
    private func reloadFiles() {
        localFiles = loadLocalStorageFiles(kind: .ar)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)

                        TextField("Search models…", text: $filterText)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 16)
                
                HStack {
                    Menu {
                        Picker("Sort by", selection: $selectedSortRawValue) {
                            ForEach(SortOption.allCases) { option in
                                Label(option.rawValue, systemImage: icon(for: option))
                                    .tag(option.rawValue)
                            }
                        }
                        .textCase(nil)
                    } label: {
                        HStack(spacing: 4) {
                            Text("AR Models")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .textCase(.uppercase)

                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.accentColor)
                                .offset(y: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .menuStyle(.button)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
                
                ScrollView {
                    if filteredFiles.isEmpty {
                        Text("No models found")
                            .foregroundColor(.gray)
                            .padding(.top, 40)
                    } else {
                        let gridWidth = UIScreen.main.bounds.width / 3 - 8
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(filteredFiles) { file in
                                FileGridItem(file: file, gridWidth: gridWidth)
                                    .onTapGesture {
                                        selectedModel = file.url
                                        dismiss()
                                    }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
            .navigationTitle("Pick AR Model")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
        .onAppear { reloadFiles() }
        .sheet(isPresented: $showImporter) {
            FilePicker(kind: .ar, allowsMultiple: false) { urls in
                guard let importedURL = urls.first else { return }

                if let saved = saveToLocalStorageDirectory(importedURL, as: .ar) {
                    print("[ARPicker] Imported:", saved)
                }

                reloadFiles()
            }
        }
    }

    private func icon(for option: SortOption) -> String {
        switch option {
        case .name: return "textformat"
        case .created: return "calendar"
        case .modified: return "clock"
        }
    }
}

struct FileGridItem: View {
    @ObservedObject var file: LocalStorageFile
    let gridWidth: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5).opacity(0.3))
                )
                .overlay(
                    Group {
                        if let thumbnail = file.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .clipped()
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                )
                .frame(width: gridWidth, height: gridWidth)

            Text(file.name)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
        }
    }
}
