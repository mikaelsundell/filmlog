// Copyright (c) 2025 Mikael Sundell
// SPDX-License-Identifier: MIT
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI
import SwiftData

struct ImageView: View {
    let imageData: ImageData
    let size: CGFloat
    var body: some View {
        Group {
            if let uiImage = imageData.thumbnail {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
                    .cornerRadius(0)
                    .contentShape(Rectangle())
            } else {
                Color.gray
                    .frame(width: size, height: size)
                    .cornerRadius(4)
            }
        }
    }
}

struct GalleryView: View {
    @Query private var galleries: [Gallery]
    @State private var filterText: String = ""
    @State private var filterTags: [Tag] = []
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: ImageData? = nil
    
    @State private var showTagSheet = false
    @State private var showSlideShow = false
    @State private var showImagePicker = false
    @State private var showDeleteAlert = false
    
    @State private var activeImage: ImageData? = nil
    
    @State private var selectedItems: [PhotosPickerItem] = []
    
    @State private var isSelecting = false
    @State private var selectedImages = Set<UUID>()
    
    enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case created = "Created"
        case lastModified = "Last modified"
        var id: String { rawValue }
    }
    
    @AppStorage("selectedImageSortOption") private var selectedImageSortRawValue: String = SortOption.lastModified.rawValue
    private var selectedImageSort: SortOption {
        get { SortOption(rawValue: selectedImageSortRawValue) ?? .lastModified }
        set { selectedImageSortRawValue = newValue.rawValue }
    }
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if activeImage == nil {
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
                    .padding()
                    
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .menuStyle(.button)
                        .help("Sort images")
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.easeInOut) {
                                isSelecting.toggle()
                                if !isSelecting { selectedImages.removeAll() }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isSelecting ? "Cancel" : "Select")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .foregroundColor(.white.opacity(0.6))
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help(isSelecting ? "Cancel selection" : "Select images")
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 2)
                    
                    let images = sortedImages(filteredImages, option: selectedImageSort)
                    VStack(alignment: .leading, spacing: 12) {
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
                                    ForEach(images, id: \.id) { image in
                                        ZStack(alignment: .topTrailing) {
                                            ImageView(imageData: image, size: gridWidth)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .stroke(selectedImages.contains(image.id) ? Color.accentColor : Color.clear, lineWidth: 3)
                                                )
                                                .opacity(isSelecting ? (selectedImages.contains(image.id) ? 1.0 : 0.8) : 1.0)
                                                .onTapGesture {
                                                    if isSelecting {
                                                        if selectedImages.contains(image.id) {
                                                            selectedImages.remove(image.id)
                                                        } else {
                                                            selectedImages.insert(image.id)
                                                        }
                                                    } else {
                                                        activeImage = image
                                                    }
                                                }
                                            
                                            if isSelecting {
                                                Circle()
                                                    .fill(selectedImages.contains(image.id) ? Color.accentColor : Color.gray.opacity(0.4))
                                                    .frame(width: 20, height: 20)
                                                    .overlay(
                                                        Group {
                                                            if selectedImages.contains(image.id) {
                                                                Image(systemName: "checkmark")
                                                                    .font(.system(size: 10, weight: .bold))
                                                                    .foregroundColor(.white)
                                                            } else {
                                                                EmptyView()
                                                            }
                                                        }
                                                    )
                                                    .padding(6)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                        .padding(.top)
                    }
                    
                    HStack {
                        Button {
                            if isSelecting && !selectedImages.isEmpty {
                                showDeleteAlert = true  // 👈 trigger confirmation alert
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .foregroundColor(isSelecting && !selectedImages.isEmpty ? .red : .gray.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Delete selected images")
                        .alert("Are you sure?", isPresented: $showDeleteAlert) {
                            Button("Delete", role: .destructive) {
                                withAnimation(.easeInOut) {
                                    for id in selectedImages {
                                        if let image = images.first(where: { $0.id == id }) {
                                            deleteImage(image)
                                        }
                                    }
                                    selectedImages.removeAll()
                                    isSelecting = false
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will delete \(selectedImages.count) image\(selectedImages.count == 1 ? "" : "s"). Are you sure you want to proceed?")
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 14, weight: .medium))
                            Text("\(images.count) image\(images.count == 1 ? "" : "s")")
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
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                        .opacity(isSelecting ? 0.4 : 1.0)
                        .disabled(isSelecting)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.black)
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            
            let images = sortedImages(filteredImages, option: selectedImageSort)
            if let image = activeImage,
               let index = images.firstIndex(where: { $0.id == image.id }) {
                ImageDetailView(
                    image: images[index],
                    gallery: gallery,
                    index: index,
                    count: images.count,
                    onPrevious: {
                        let previousIndex = (index - 1 + images.count) % images.count
                        activeImage = images[previousIndex]
                    },
                    onNext: {
                        let nextIndex = (index + 1) % images.count
                        activeImage = images[nextIndex]
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeImage = nil
                        }
                    },
                    onDelete: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            gallery.deleteImage(image, context: modelContext)
                            activeImage = nil
                        }
                    }
                )
                .navigationBarHidden(true)
                .transition(.opacity)
            }
        }
        .navigationTitle("Gallery")
        .onAppear {
            importSharedImages()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                importSharedImages()
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }

            Task {
                for newItem in newItems {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        do {
                            let newImage = ImageData()
                            if newImage.updateFile(to: uiImage) {
                                modelContext.insert(newImage)
                                try modelContext.save()

                                withAnimation {
                                    gallery.addImage(newImage)
                                }

                                try modelContext.save()
                            } else {
                                print("failed to save image file for new image")
                            }
                        } catch {
                            print("failed to insert image: \(error)")
                        }
                    } else {
                        print("ould not load image from PhotosPicker item")
                    }
                }
                selectedItems.removeAll()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: { showImagePicker = true }) {
                    Label("Add image", systemImage: "plus")
                }

                Button(action: {
                    showSlideShow = true
                }) {
                    Image(systemName: "display")
                }
                .help("Play slideshow of images")

                Menu {
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gear")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showTagSheet) {
            TagView(
                gallery: gallery,
                filterTags: $filterTags
            )
            .presentationDetents([.medium, .large])
        }
        .photosPicker(
            isPresented: $showImagePicker,
            selection: $selectedItems,
            maxSelectionCount: 10,
            matching: .images
        )
    }

    private func sortedImages(_ images: [ImageData], option: SortOption) -> [ImageData] {
        switch option {
        case .name:
            return images.sorted {
                ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
            }
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

    private var gallery: Gallery {
        if let gallery = galleries.first {
            return gallery
        } else {
            let gallery = Gallery()
            modelContext.insert(gallery)
            try? modelContext.save()
            return gallery
        }
    }

    private var filteredImages: [ImageData] {
        var imgs = gallery.orderedImages
        if !filterTags.isEmpty {
            imgs = imgs.filter { !$0.tags.filter { filterTags.contains($0) }.isEmpty }
        }
        if !filterText.isEmpty {
            imgs = imgs.filter {
                ($0.note?.localizedCaseInsensitiveContains(filterText) == true) ||
                ($0.name?.localizedCaseInsensitiveContains(filterText) == true)
            }
        }
        return imgs
    }
    
    private func deleteImage(_ image: ImageData) {
        do {
            gallery.deleteImage(image, context: modelContext)
            try modelContext.save()
        } catch {
            print("failed to delete image: \(error)")
        }
    }

    private func importSharedImages() {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.mikaelsundell.filmlog") else {
            print("could not access shared app group container.")
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let imageFiles = files.filter {
                let fileName = $0.lastPathComponent.lowercased()
                let ext = $0.pathExtension.lowercased()
                return fileName.hasPrefix("shared_") && ["jpg", "jpeg", "png"].contains(ext)
            }

            if imageFiles.isEmpty {
                print("no shared images found in: \(containerURL.path)")
                return
            }
            
            var importedCount = 0
            for imageFile in imageFiles {
                let baseName = imageFile.deletingPathExtension().lastPathComponent
                let jsonFile = containerURL.appendingPathComponent("\(baseName).json")
                if let data = try? Data(contentsOf: imageFile),
                   let image = UIImage(data: data) {

                    var name: String? = nil
                    var note: String? = nil
                    var creator: String? = nil
                    var timestamp: Date? = nil

                    if fileManager.fileExists(atPath: jsonFile.path),
                       let jsonData = try? Data(contentsOf: jsonFile),
                       let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        name = jsonObject["name"] as? String
                        note = jsonObject["note"] as? String
                        creator = jsonObject["creator"] as? String

                        if let timestampValue = jsonObject["timestamp"] {
                            if let timestampString = timestampValue as? String {
                                let formatter = ISO8601DateFormatter()
                                timestamp = formatter.date(from: timestampString)
                            } else if let timestampInt = timestampValue as? Int {
                                timestamp = Date(timeIntervalSince1970: TimeInterval(timestampInt))
                            }
                        }
                    }

                    let newImage = ImageData(name: name, note: note, creator: creator)
                    newImage.timestamp = timestamp ?? Date()

                    if !filterTags.isEmpty {
                        newImage.tags.append(contentsOf: filterTags)
                    }

                    if newImage.updateFile(to: image) {
                        modelContext.insert(newImage)
                        try modelContext.save()
                        gallery.addImage(newImage)

                        try? fileManager.removeItem(at: imageFile)
                        if fileManager.fileExists(atPath: jsonFile.path) {
                            try? fileManager.removeItem(at: jsonFile)
                        }

                        importedCount += 1
                    } else {
                        print("failed to update file for image: \(imageFile.lastPathComponent)")
                    }
                } else {
                    print("could not load image data from: \(imageFile.lastPathComponent)")
                }
            }
            try modelContext.save()

        } catch {
            print("error reading shared images: \(error)")
        }
    }
}
