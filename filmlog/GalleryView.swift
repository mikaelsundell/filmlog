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
    @State private var searchText: String = ""
    @State private var selectedTag: Tag? = nil
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: ImageData? = nil

    @State private var showTagSheet = false
    @State private var showSlideShow = false
    @State private var showImagePicker = false
    
    @State private var selectedItems: [PhotosPickerItem] = []
    
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
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search images...", text: $searchText)
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
                    } label: {
                        HStack(spacing: 4) {
                            Text("Select")
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundColor(.white.opacity(0.6))
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("Select images")
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
                                    ImageView(imageData: image, size: gridWidth)
                                        .contentShape(Rectangle())
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(.top)
                }
                
                HStack {
                    Button {
                        //showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .help("Delete project")
                    
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
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color.black)
                .ignoresSafeArea(edges: .bottom)
  
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
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        do {
                            let newImage = ImageData()
                            if newImage.updateFile(to: uiImage) {
                                modelContext.insert(newImage)
                                try modelContext.save()

                                withAnimation {
                                    currentGallery.addImage(newImage)
                                }

                                try modelContext.save()
                            } else {
                                print("failed to save image file for new image")
                            }
                        } catch {
                            print("failed to insert image: \(error)")
                        }
                    } else {
                        print("could not load image from PhotosPicker")
                    }
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
                    gallery: currentGallery,
                    selectedTag: $selectedTag
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
    }
    
    private func sortedImages(_ images: [ImageData], option: SortOption) -> [ImageData] {
        switch option {
        case .name:
            return images.sorted {
                ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
            }
        case .created:
            return images.sorted {
                $0.created > $1.created
            }

        case .lastModified:
            return images.sorted {
                $0.lastModified > $1.lastModified
            }
        }
    }

    private func icon(for option: SortOption) -> String {
        switch option {
        case .name: return "textformat"
        case .created: return "calendar"
        case .lastModified: return "clock"
        }
    }

    private var currentGallery: Gallery {
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
        var imgs = currentGallery.orderedImages
        if let tag = selectedTag {
            imgs = imgs.filter { $0.tags.contains(tag) }
        }
        if !searchText.isEmpty {
            imgs = imgs.filter {
                ($0.note?.localizedCaseInsensitiveContains(searchText) == true) ||
                ($0.name?.localizedCaseInsensitiveContains(searchText) == true)
            }
        }
        return imgs
    }
    
    private func deleteImage(_ image: ImageData) {
        do {
            currentGallery.deleteImage(image, context: modelContext)
            try modelContext.save()
        } catch {
            print("failed to delete image: \(error)")
        }
    }

    private func importSharedImages() {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.mikaelsundell.filmlog") else {
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
                return
            }
            
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
                        if let timestampString = jsonObject["timestamp"] as? String {
                            let formatter = ISO8601DateFormatter()
                            timestamp = formatter.date(from: timestampString)
                        }
                    }

                    let newImage = ImageData(name: name, note: note, creator: creator)
                    newImage.timestamp = timestamp ?? Date()

                    if let selectedTag {
                        newImage.tags.append(selectedTag)
                    }

                    if newImage.updateFile(to: image) {
                        modelContext.insert(newImage)
                        try modelContext.save()
                        currentGallery.addImage(newImage)
                        try? fileManager.removeItem(at: imageFile)
                        if fileManager.fileExists(atPath: jsonFile.path) {
                            try? fileManager.removeItem(at: jsonFile)
                        }
                    } else {
                        print("failed to save image data for file: \(imageFile.lastPathComponent)")
                    }
                } else {
                    print("could not load image from file: \(imageFile.lastPathComponent)")
                }
            }
            try modelContext.save()
        } catch {
            print("error reading shared images: \(error)")
        }
    }
}

struct TagView: View {
    let gallery: Gallery
    @Binding var selectedTag: Tag?

    @State private var filterText: String = ""
    @State private var activeTag: Tag? = nil
    @State private var selectedTags: Set<Tag> = []
    
    enum ActiveField {
        case name, note
    }
    @FocusState private var activeField: ActiveField?
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            if activeTag == nil {
                
                VStack(spacing: 0) {
                    Form {
                        Section {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                TextField("Filter tags...", text: $filterText)
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled()
                                /*Button(action: addTagAction) {
                                    Image(systemName: "plus.circle")
                                        .font(.title2)
                                        .foregroundColor(.accentColor)
                                }*/
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color(red: 0.05, green: 0.05, blue: 0.05))
                    .frame(maxHeight: 100)

                    let filteredTags = gallery.orderedTags.filter {
                        filterText.isEmpty || $0.name.localizedCaseInsensitiveContains(filterText)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if filteredTags.isEmpty {
                                Text("No tags available")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                            } else {
                                FlowLayout(spacing: 8, lineSpacing: 10) {
                                    ForEach(filteredTags) { tag in
                                        let isSelected = selectedTags.contains(tag)
                                        
                                        Text(tag.name)
                                            .font(.caption)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(isSelected ? tag.defaultColor : Color.clear)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(
                                                        tag.defaultColor.opacity(tag.isDefaultColor ? 0.4 : 1.0),
                                                        lineWidth: 1.2
                                                    )
                                            )
                                            .foregroundColor(isSelected ? .white : .gray)
                                            .cornerRadius(12)
                                            .transition(.asymmetric(
                                                insertion: .opacity,
                                                removal: .scale.combined(with: .opacity)
                                            ))
                                            .onTapGesture {
                                                toggleTagSelection(tag)
                                            }
                                            .contextMenu {
                                                Button {
                                                    activeTag = tag
                                                } label: {
                                                    Label("Edit", systemImage: "pencil")
                                                }

                                                Button(role: .destructive) {
                                                    withAnimation(.easeInOut(duration: 0.25)) {
                                                        deleteTag(tag)
                                                    }
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Color(red: 0.05, green: 0.05, blue: 0.05))
            }
            
            if let tag = activeTag,
               let index = gallery.orderedTags.firstIndex(where: { $0.id == tag.id }) {
                TagDetailView(
                    tag: tag,
                    index: index,
                    count: gallery.orderedTags.count,
                    onSelect: { newIndex in
                        guard newIndex >= 0 && newIndex < gallery.orderedTags.count else { return }
                        activeTag = gallery.orderedTags[newIndex]
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeTag = nil
                        }
                    }
                )
            }
        }
    }

    private func deleteTag(_ tag: Tag) {
        do {
            for image in gallery.orderedImages {
                image.tags.removeAll(where: { $0.id == tag.id })
            }
            gallery.tags.removeAll(where: { $0.id == tag.id })
            modelContext.delete(tag)
            try modelContext.save()
        } catch {
            print("failed to delete tag: \(error)")
        }
    }
    
    private func toggleTagSelection(_ tag: Tag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}
