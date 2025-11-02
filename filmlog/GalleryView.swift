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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var galleries: [Gallery]
    @State private var searchText: String = ""
    @State private var selectedTag: Tag? = nil
    @State private var showImagePicker = false
    @State private var selectedItem: PhotosPickerItem? = nil
    
    @State private var showTagManager = false
    
    @State private var showTagEditSheet = false
    @State private var selectedTagForEdit: Tag? = nil
    @State private var showRenameDialog = false
    @State private var renameText = ""

    @State private var showDeleteTagAlert = false
    @State private var tagToDelete: Tag? = nil
    
    @State private var selectedImageForEdit: ImageData? = nil
    @State private var newName = ""
    @State private var newNote = ""
    @State private var newTags: [Tag] = []
    @State private var newSelectedTags: Set<Tag> = []
    @FocusState private var selectedImageFocused: Bool
    
    @State private var showDeleteImageAlert = false
    @State private var imageToDelete: ImageData? = nil
    
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
                }
                .padding(.horizontal)
                .padding(.bottom, 2)

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
                                ForEach(sortedImages(filteredImages, option: selectedImageSort), id: \.id) { image in
                                    ImageView(imageData: image, size: gridWidth)
                                        .contentShape(Rectangle())
                                        .contextMenu {
                                            Button {
                                                selectedImageForEdit = image
                                                newName = image.name ?? ""
                                                newNote = image.note ?? ""
                                                newTags = image.tags
                                            } label: {
                                                Label("Edit image", systemImage: "pencil")
                                            }
                                            
                                            Button(role: .destructive) {
                                                imageToDelete = image
                                                showDeleteImageAlert = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .id(image.id)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(.top)
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
            .alert("Delete tag?", isPresented: $showDeleteTagAlert, presenting: tagToDelete) { tag in
                Button("Delete", role: .destructive) {
                    deleteTag(tag)
                }
                Button("Cancel", role: .cancel) { }
            } message: { tag in
                Text("Are you sure you want to delete the tag \(tag.name)?")
            }
            .alert("Delete Image?", isPresented: $showDeleteImageAlert, presenting: imageToDelete) { image in
                Button("Delete", role: .destructive) {
                    deleteImage(image)
                }
                Button("Cancel", role: .cancel) { }
            } message: { image in
                Text("Are you sure you want to delete \(image.name ?? "this image")?")
            }
            .sheet(isPresented: $showTagEditSheet) {
                if let tag = selectedTagForEdit {
                    NavigationView {
                        Form {
                            Section(header: Text("Rename tag")) {
                                TextField("Tag name", text: $renameText)
                            }
                        }
                        .navigationTitle("Edit tag")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    tag.name = renameText
                                    try? modelContext.save()
                                    showTagEditSheet = false
                                }
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    showTagEditSheet = false
                                }
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedImageForEdit) { image in
                NavigationView {
                    Form {
                        Section(header: Text("Image")) {
                            TextField("Name", text: $newName)
                                .focused($selectedImageFocused)
                            
                            TextEditor(text: $newNote)
                                .frame(height: 100)
                                .focused($selectedImageFocused)
                                .offset(x: -4)
                        }
                        
                        Section(header: Text("Tags")) {
                            NavigationLink("Select tags") {
                                TagPickerView(
                                    selectedTags: $newSelectedTags,
                                    allTags: currentGallery.orderedTags
                                )
                                .navigationTitle("Select Tags")
                            }

                            if !newSelectedTags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(Array(newSelectedTags)) { tag in
                                            Text(tag.name)
                                                .padding(8)
                                                .background(Color.accentColor.opacity(0.2))
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .onAppear {
                        selectedImageFocused = true
                    }
                    .navigationTitle("Edit image")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                image.name = newName
                                image.note = newNote
                                image.tags = Array(newSelectedTags)
                                try? modelContext.save()
                                selectedImageForEdit = nil
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                selectedImageForEdit = nil
                            }
                        }
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                selectedImageFocused = false
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showImagePicker = true }) {
                        Label("Add image", systemImage: "plus")
                    }

                    Button {
                        showTagManager = true
                    } label: {
                        Image(systemName: "tag")
                    }

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
            .sheet(isPresented: $showTagManager) {
                TagView(
                    gallery: currentGallery,
                    selectedTag: $selectedTag,
                    modelContext: modelContext,
                    showTagEditSheet: $showTagEditSheet,
                    selectedTagForEdit: $selectedTagForEdit,
                    showDeleteTagAlert: $showDeleteTagAlert,
                    tagToDelete: $tagToDelete,
                    addTagAction: addTag
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

    private func addTag() {
        do {
            let newTag = Tag(name: "Tag \(currentGallery.tags.count + 1)")
            modelContext.insert(newTag)
            try modelContext.save()

            currentGallery.tags.append(newTag)
            try modelContext.save()
        } catch {
            print("failed to add tag: \(error)")
        }
    }

    private func deleteTag(_ tag: Tag) {
        do {
            for image in currentGallery.orderedImages {
                if let index = image.tags.firstIndex(where: { $0.id == tag.id }) {
                    image.tags.remove(at: index)
                }
            }
            if let index = currentGallery.tags.firstIndex(where: { $0.id == tag.id }) {
                currentGallery.tags.remove(at: index)
            }
            modelContext.delete(tag)
            try modelContext.save()
        } catch {
            print("failed to delete tag: \(error)")
        }
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
    var modelContext: ModelContext

    @Binding var showTagEditSheet: Bool
    @Binding var selectedTagForEdit: Tag?
    @Binding var showDeleteTagAlert: Bool
    @Binding var tagToDelete: Tag?

    @State private var selectedTags: Set<Tag> = []
    
    var addTagAction: () -> Void

    @State private var tagFilterText: String = ""
    @Environment(\.dismiss) private var dismissSheet

    @State private var isEditingTag = false
    @State private var renameText: String = ""
    enum ActiveField {
        case name, note
    }
    @FocusState private var activeField: ActiveField?

    var body: some View {
        NavigationStack {
            VStack(spacing: 4) {
                if isEditingTag, let tag = selectedTagForEdit {
                    VStack(spacing: 0) {
                        Form {
                            Section(header:
                                HStack {
                                    Text("Tag")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                        .textCase(.uppercase)
                                    Spacer()
                                }
                            ) {
                                HStack {
                                    TextField("Name", text: $renameText)
                                        .focused($activeField, equals: .name)
                                        .submitLabel(.done)
                                        .textInputAutocapitalization(.words)

                                    if !renameText.isEmpty {
                                        Button {
                                            renameText = ""
                                            DispatchQueue.main.async {
                                                UIView.performWithoutAnimation {
                                                    activeField = .name
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.trailing, 2)
                                        .transition(.opacity.combined(with: .scale))
                                    }
                                }
                                
                                HStack {
                                    Text("Modified:")
                                    Text(tag.timestamp.formatted(date: .abbreviated, time: .shortened))
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                            
                            Section(header:
                                HStack {
                                    Text("Color")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                        .textCase(.uppercase)
                                    Spacer()
                                }
                            ) {
                                HStack {
                                    ColorPicker("Tag color", selection: Binding(
                                        get: {
                                            Color(hex: tag.color ?? "#007AFF") ?? .blue
                                        },
                                        set: { newColor in
                                            tag.color = newColor.toHex()
                                            tag.timestamp = Date()
                                            try? modelContext.save()
                                        }
                                    ))
                                    .labelsHidden()

                                    Circle()
                                        .fill(Color(hex: tag.color ?? "#007AFF") ?? .blue)
                                        .frame(width: 24, height: 24)
                                        .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color(red: 0.05, green: 0.05, blue: 0.05))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        isEditingTag = false
                                        selectedTagForEdit = nil
                                    }
                                } label: {
                                    Label("Tags", systemImage: "chevron.left")
                                        .labelStyle(.titleAndIcon)
                                }
                            }

                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        tag.name = trimmed
                                        try? modelContext.save()
                                    }
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        isEditingTag = false
                                        selectedTagForEdit = nil
                                    }
                                }
                                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .navigationTitle("Edit Tag")
                        .onAppear {
                            renameText = tag.name
                        }
                    }
                }
                else {
                    VStack(spacing: 0) {
                        Form {
                            Section {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.gray)
                                    TextField("Filter tags...", text: $tagFilterText)
                                        .textFieldStyle(.plain)
                                        .autocorrectionDisabled()
                                    Button(action: addTagAction) {
                                        Image(systemName: "plus.circle")
                                            .font(.title2)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color(red: 0.05, green: 0.05, blue: 0.05))
                        .frame(maxHeight: 60)

                        let filteredTags = gallery.orderedTags.filter {
                            tagFilterText.isEmpty || $0.name.localizedCaseInsensitiveContains(tagFilterText)
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
                                                        selectedTagForEdit = tag
                                                        renameText = tag.name
                                                        withAnimation(.easeInOut(duration: 0.25)) {
                                                            isEditingTag = true
                                                        }
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
            }
            .navigationTitle(isEditingTag ? "Edit Tags" : "Tags")
            .animation(.easeInOut(duration: 0.25), value: isEditingTag)
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
