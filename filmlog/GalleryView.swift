// Copyright 2022-present Contributors to the filmlog project.
// SPDX-License-Identifier: Apache-2.0
// https://github.com/mikaelsundell/filmlog

import SwiftUI
import PhotosUI
import SwiftData

struct GalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var galleries: [Gallery]
    @State private var searchText: String = ""
    @State private var selectedCategoryId: UUID? = nil
    @State private var showImagePicker = false
    @State private var selectedItem: PhotosPickerItem? = nil
    
    @State private var selectedCategoryForEdit: Category? = nil
    @State private var showEditOptions = false
    @State private var showRenameDialog = false
    @State private var renameText = ""

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

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Categories (\(currentGallery.categories.count))")
                                .font(.headline)
                            Spacer()
                            Button(action: addCategory) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(currentGallery.categories) { category in
                                    Text(category.name)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedCategoryId == category.id ? Color.blue : Color.blue.opacity(0.1))
                                        .foregroundColor(selectedCategoryId == category.id ? .white : .blue)
                                        .cornerRadius(12)
                                        .onTapGesture {
                                            selectedCategoryId = selectedCategoryId == category.id ? nil : category.id
                                        }
                                        .onLongPressGesture {
                                            selectedCategoryForEdit = category
                                            showEditOptions = true
                                        }
                                }
                            }
                            .padding(.horizontal)
                        }

                        Divider()
                            .padding(.horizontal)
                        
                        HStack {
                            Text("Categories (\(filteredImages.count))")
                                .font(.headline)
                            Spacer()
                            Button(action: addCategory) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)

                        if filteredImages.isEmpty {
                            Text("No images found")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        } else {
                            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(filteredImages, id: \.id) { image in
                                    if let uiImage = UIImage(data: image.data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: UIScreen.main.bounds.width / 3 - 4,
                                                   height: UIScreen.main.bounds.width / 3 - 4)
                                            .clipped()
                                            .cornerRadius(6)
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
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
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        let newImage = ImageData(data: data, categoryId: selectedCategoryId)
                        modelContext.insert(newImage)
                        do {
                            try modelContext.save()
                        } catch {
                            print("failed to insert image: \(error)")
                        }

                        withAnimation {
                            currentGallery.images.append(newImage)
                        }

                        do {
                            try modelContext.save()
                        } catch {
                            print("failed to save gallery relationship: \(error)")
                        }
                    } else {
                        print("could not load image from PhotosPicker")
                    }
                }
            }
            .alert("Rename category", isPresented: $showRenameDialog) {
                TextField("Category name", text: $renameText)
                Button("Save") {
                    if let category = selectedCategoryForEdit {
                        category.name = renameText
                        try? modelContext.save()
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog("Edit category", isPresented: $showEditOptions, titleVisibility: .visible) {
                Button("Rename") {
                    renameText = selectedCategoryForEdit?.name ?? ""
                    showRenameDialog = true
                }
                Button("Delete", role: .destructive) {
                    if let category = selectedCategoryForEdit {
                        if let index = currentGallery.categories.firstIndex(where: { $0.id == category.id }) {
                            currentGallery.categories.remove(at: index)
                            try? modelContext.save()
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showImagePicker = true }) {
                        Label("Add Image", systemImage: "plus")
                    }
                }
            }
            .photosPicker(isPresented: $showImagePicker, selection: $selectedItem, matching: .images)
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
        let allImages = currentGallery.images
        var imgs = allImages
        if let categoryId = selectedCategoryId {
            imgs = imgs.filter { $0.categoryId == categoryId }
        }
        if !searchText.isEmpty {
            imgs = imgs.filter { $0.id.uuidString.localizedCaseInsensitiveContains(searchText) }
        }
        return imgs
    }

    private func addCategory() {
        do {
            let newCategory = Category(name: "Category \(currentGallery.categories.count + 1)")
            modelContext.insert(newCategory)
            try modelContext.save()
            
            currentGallery.categories.append(newCategory)
            try modelContext.save()
        } catch {
            print("failed to add category: \(error)")
        }
    }

    private func importSharedImages() {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.mikaelsundell.filmlog") else {
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let imageFiles = files.filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            if imageFiles.isEmpty {
                return
            }

            for imageFile in imageFiles {
                let baseName = imageFile.deletingPathExtension().lastPathComponent
                let jsonFile = containerURL.appendingPathComponent("\(baseName).json")

                if let data = try? Data(contentsOf: imageFile) {
                    var comment: String? = nil
                    var creator: String? = nil
                    var timestamp: Int? = nil

                    if fileManager.fileExists(atPath: jsonFile.path),
                       let jsonData = try? Data(contentsOf: jsonFile),
                       let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        comment = jsonObject["comment"] as? String
                        creator = jsonObject["creator"] as? String
                        timestamp = jsonObject["timestamp"] as? Int
                    }

                    let newImage = ImageData(
                        data: data,
                        categoryId: selectedCategoryId,
                        comment: comment,
                        creator: creator,
                        timestamp: timestamp
                    )

                    modelContext.insert(newImage)
                    try modelContext.save()
                    
                    currentGallery.images.append(newImage)

                    try? fileManager.removeItem(at: imageFile)
                    if fileManager.fileExists(atPath: jsonFile.path) {
                        try? fileManager.removeItem(at: jsonFile)
                    }
                }
            }
            try modelContext.save()

        } catch {
            print("error reading shared images: \(error)")
        }
    }
}
