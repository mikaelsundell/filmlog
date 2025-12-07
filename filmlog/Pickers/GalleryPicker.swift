// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import SwiftData

struct GalleryPicker: View {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query private var galleries: [Gallery]
    @State private var filterText: String = ""
    
    @State private var selectedTags: [Tag] = []
    @State private var showTagSheet = false
    
    @State private var selectedImageSortRawValue: String = SortOption.lastModified.rawValue
    
    enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case created = "Created"
        case lastModified = "Last modified"
        var id: String { rawValue }
    }
    
    private var selectedSort: SortOption {
        get { SortOption(rawValue: selectedImageSortRawValue) ?? .lastModified }
        set { selectedImageSortRawValue = newValue.rawValue }
    }
    
    private var gallery: Gallery {
        if let existing = galleries.first { return existing }
        let newGallery = Gallery()
        modelContext.insert(newGallery)
        try? modelContext.save()
        return newGallery
    }
    
    private var filteredImages: [ImageData] {
        var imgs = gallery.orderedImages
        if !selectedTags.isEmpty {
            imgs = imgs.filter { !$0.tags.filter { selectedTags.contains($0) }.isEmpty }
        }
        if !filterText.isEmpty {
            imgs = imgs.filter {
                ($0.name?.localizedCaseInsensitiveContains(filterText) == true) ||
                ($0.note?.localizedCaseInsensitiveContains(filterText) == true)
            }
        }

        return sortImages(imgs, by: selectedSort)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search images...", text: $filterText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
                
                HStack {
                    Menu {
                        Picker("Sort by", selection: $selectedImageSortRawValue) {
                            ForEach(SortOption.allCases) { option in
                                Label(option.rawValue, systemImage: icon(for: option))
                                    .tag(option.rawValue)
                            }
                        }
                        .textCase(nil)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Images")
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
                    if filteredImages.isEmpty {
                        Text("No images found")
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        let gridWidth = UIScreen.main.bounds.width / 3 - 8
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
                        
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(filteredImages, id: \.id) { image in
                                ImageView(imageData: image, size: gridWidth)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(borderColor(for: image), lineWidth: 3)
                                    )
                                    .onTapGesture {
                                        // Convert ImageData to UIImage (prefer full-size original if available)
                                        if let uiImage = image.original ?? image.thumbnail {
                                            selectedImage = uiImage
                                            dismiss()
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                
                HStack {
                    
                    Circle()
                            .frame(width: 40, height: 40)
                            .opacity(0)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 14, weight: .medium))
                        Text("\(filteredImages.count) image\(filteredImages.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .fontWeight(.regular)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .foregroundColor(.blue)
                    .shadow(radius: 1)
                    
                    Spacer()
                    
                    Button {
                        showTagSheet = true
                    } label: {
                        Image(systemName: "tag")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .foregroundColor(
                                filteredImages.isEmpty
                                    ? .gray.opacity(0.3)
                                    : .blue
                            )
                    }
                    .disabled(filteredImages.isEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.black)
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Pick Image")
            .sheet(isPresented: $showTagSheet) {
                TagPicker(
                    gallery: gallery,
                    selectedTags: $selectedTags
                )
                .presentationDetents([.medium, .large])
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
    }
    
    private func sortImages(_ images: [ImageData], by option: SortOption) -> [ImageData] {
        switch option {
        case .name:
            return images.sorted { ($0.name ?? "") < ($1.name ?? "") }
        case .created:
            return images.sorted { $0.created > $1.created }
        case .lastModified:
            return images.sorted { $0.lastModified > $1.lastModified }
        }
    }
    
    private func icon(for option: SortOption) -> String {
        switch option {
        case .name: return "textformat"
        case .created: return "calendar"
        case .lastModified: return "clock"
        }
    }
    
    private func borderColor(for image: ImageData) -> Color {
        if let uiImage = image.thumbnail, uiImage.pngData() == selectedImage?.pngData() {
            return .accentColor
        }
        return .clear
    }
}
